#!/usr/bin/env python3
# /// script
# dependencies = [
#   "rich",
#   "typer",
#   "pypaperless",
#   "aiohttp>=3.9",
# ]
# ///

import asyncio
from dataclasses import dataclass
import os
from pathlib import Path
import re
import subprocess
import time
from typing import Annotated

import aiohttp
import typer
from pypaperless import Paperless
from pypaperless.exceptions import TaskNotFoundError
from rich.console import Console
from rich.table import Table

app = typer.Typer(no_args_is_help=True, help="Screenshot automation for Swift Paperless iOS app")
console = Console()


# ============================================================================
# Data Models
# ============================================================================


@dataclass(frozen=True)
class ScreenshotStep:
    name: str
    url: str | None = None
    post_url: str | None = None
    wait: float | None = None


DEFAULT_STEPS = [
    ScreenshotStep("documents"),
    ScreenshotStep(
        "filter_tags",
        "x-paperless://v1/open_filter/tags",
        "x-paperless://v1/close_filter",
    ),
    ScreenshotStep("document_view", "x-paperless://v1/document/3?edit=0"),
    ScreenshotStep("document_edit", "x-paperless://v1/document/3?edit=1", wait=4),
]


# Data model matching PreviewRepository.swift
TAGS = [
    {"name": "Inbox", "color": "#800080", "is_inbox_tag": True, "matching_algorithm": 1, "is_insensitive": True, "match": ""},
    {"name": "Bank", "color": "#0000FF", "matching_algorithm": 1, "is_insensitive": True, "match": "", "is_inbox_tag": False},
    {"name": "Travel Document", "color": "#008000", "matching_algorithm": 1, "is_insensitive": True, "match": "", "is_inbox_tag": False},
    {"name": "Important", "color": "#FF0000", "matching_algorithm": 1, "is_insensitive": True, "match": "", "is_inbox_tag": False},
    {"name": "Book", "color": "#FFFF00", "matching_algorithm": 1, "is_insensitive": True, "match": "", "is_inbox_tag": False},
]

CORRESPONDENTS = [
    {"name": "McMillan", "matching_algorithm": 1, "is_insensitive": True, "match": ""},
    {"name": "Credit Suisse", "matching_algorithm": 1, "is_insensitive": True, "match": ""},
    {"name": "UBS", "matching_algorithm": 1, "is_insensitive": True, "match": ""},
    {"name": "Home", "matching_algorithm": 1, "is_insensitive": True, "match": ""},
]

DOCUMENT_TYPES = [
    {"name": "Letter", "matching_algorithm": 1, "is_insensitive": True, "match": ""},
    {"name": "Invoice", "matching_algorithm": 1, "is_insensitive": True, "match": ""},
    {"name": "Receipt", "matching_algorithm": 1, "is_insensitive": True, "match": ""},
    {"name": "Bank Statement", "matching_algorithm": 1, "is_insensitive": True, "match": ""},
]

STORAGE_PATHS = [
    {"name": "Path A", "path": "aaa", "matching_algorithm": 1, "is_insensitive": True, "match": ""},
    {"name": "Path B", "path": "bbb", "matching_algorithm": 1, "is_insensitive": True, "match": ""},
]


# ============================================================================
# Exceptions
# ============================================================================


class BackendSetupError(Exception):
    """Base exception for backend setup failures."""
    pass


class BackendNotReadyError(BackendSetupError):
    """Backend didn't become ready in time."""
    pass


class AuthenticationError(BackendSetupError):
    """Failed to authenticate with backend."""
    pass


class DocumentUploadError(BackendSetupError):
    """Failed to upload documents."""
    pass


# ============================================================================
# Utility Functions
# ============================================================================


def sanitize_filename(value: str) -> str:
    return "".join(
        character if character.isalnum() or character in "-_" else "_"
        for character in value
    )


def run_command(args: list[str], *, check: bool = True, dry_run: bool = False, env: dict | None = None) -> None:
    display = " ".join(args)
    console.log(f"[bold blue]$ {display}[/bold blue]")
    if dry_run:
        return
    subprocess.run(args, check=check, env=env)


def simctl(args: list[str], *, check: bool = True, dry_run: bool = False, env: dict | None = None) -> None:
    run_command(["xcrun", "simctl", *args], check=check, dry_run=dry_run, env=env)


def parse_steps(raw_steps: list[str]) -> list[ScreenshotStep]:
    if not raw_steps:
        return DEFAULT_STEPS
    steps: list[ScreenshotStep] = []
    for raw_step in raw_steps:
        wait: float | None = None
        base_step = raw_step
        name_and_url, wait_separator, wait_value = raw_step.rpartition("@")
        if wait_separator:
            try:
                wait = float(wait_value)
                base_step = name_and_url
            except ValueError:
                base_step = raw_step
        name, separator, url = base_step.partition("=")
        name = name.strip()
        url = url.strip() if separator else None
        if not name:
            raise typer.BadParameter("Step name cannot be empty.")
        steps.append(ScreenshotStep(name=name, url=url or None, wait=wait))
    return steps


def display_plan(languages: list[str], steps: list[ScreenshotStep]) -> None:
    table = Table(title="Screenshot plan", header_style="bold magenta")
    table.add_column("Language")
    table.add_column("Screens")
    step_names = ", ".join(
        f"{step.name}@{step.wait:g}s" if step.wait is not None else step.name
        for step in steps
    )
    for language in languages:
        table.add_row(language, step_names)
    console.print(table)


def configure_simulator(
    *,
    status_bar_time: str,
    status_bar_cellular_bars: int,
    appearance: str,
    dry_run: bool,
) -> None:
    simctl(["ui", "booted", "appearance", appearance], dry_run=dry_run)
    simctl(
        [
            "status_bar",
            "booted",
            "override",
            "--time",
            status_bar_time,
            "--cellularBars",
            str(status_bar_cellular_bars),
        ],
        dry_run=dry_run,
    )


# ============================================================================
# Docker Compose Management
# ============================================================================


def docker_compose_cmd(compose_file: Path, *args) -> list[str]:
    """Build docker-compose command."""
    return ["docker", "compose", "-f", str(compose_file), *args]


def wait_for_docker_services(url: str, timeout: int) -> None:
    """Wait for backend API to become ready."""
    asyncio.run(wait_for_backend(url, timeout))


def manage_docker_backend(compose_file: Path, recreate: bool, wait_timeout: int, url: str) -> None:
    """Start or recreate Docker backend."""
    if recreate:
        console.log("[yellow]Tearing down existing containers...")
        subprocess.run(docker_compose_cmd(compose_file, "down", "-v"), check=False)

    console.log("[blue]Starting Docker backend...")
    subprocess.run(docker_compose_cmd(compose_file, "up", "-d"), check=True)

    console.log("[blue]Waiting for services to start...")
    wait_for_docker_services(url, wait_timeout)


# ============================================================================
# Backend Setup Functions
# ============================================================================


async def wait_for_backend(url: str, timeout: int) -> None:
    """Poll health endpoint until backend is ready."""
    start_time = time.time()
    api_url = f"{url.rstrip('/')}/api/"

    with console.status(f"[blue]Waiting for {api_url} to become ready..."):
        async with aiohttp.ClientSession() as session:
            while time.time() - start_time < timeout:
                try:
                    async with session.get(api_url, timeout=aiohttp.ClientTimeout(total=2)) as resp:
                        if resp.status == 200:
                            console.log(f"[green]Backend ready at {api_url}")
                            return
                except (aiohttp.ClientError, asyncio.TimeoutError):
                    await asyncio.sleep(2)

    raise BackendNotReadyError(f"Backend not ready after {timeout}s")


async def authenticate(url: str, username: str, password: str) -> str:
    """Get auth token from Paperless-ngx."""
    token_url = f"{url.rstrip('/')}/api/token/"

    async with aiohttp.ClientSession() as session:
        try:
            async with session.post(
                token_url,
                json={"username": username, "password": password}
            ) as resp:
                resp.raise_for_status()
                data = await resp.json()
                token = data["token"]
                console.log(f"[green]Authenticated successfully")
                return token
        except aiohttp.ClientError as e:
            raise AuthenticationError(f"Authentication failed: {e}")


async def create_tags(paperless: Paperless) -> None:
    """Create tags in backend."""
    console.log("[blue]Creating tags...")
    for tag_data in TAGS:
        try:
            draft = paperless.tags.draft(**tag_data)
            tag_id = await draft.save()
            console.log(f"  Created tag: {tag_data['name']} (ID: {tag_id})")
        except Exception as e:
            console.log(f"  [yellow]Tag {tag_data['name']} may already exist: {e}")


async def create_correspondents(paperless: Paperless) -> None:
    """Create correspondents in backend."""
    console.log("[blue]Creating correspondents...")
    for corr_data in CORRESPONDENTS:
        try:
            draft = paperless.correspondents.draft(**corr_data)
            corr_id = await draft.save()
            console.log(f"  Created correspondent: {corr_data['name']} (ID: {corr_id})")
        except Exception as e:
            console.log(f"  [yellow]Correspondent {corr_data['name']} may already exist: {e}")


async def create_document_types(paperless: Paperless) -> None:
    """Create document types in backend."""
    console.log("[blue]Creating document types...")
    for dt_data in DOCUMENT_TYPES:
        try:
            draft = paperless.document_types.draft(**dt_data)
            dt_id = await draft.save()
            console.log(f"  Created document type: {dt_data['name']} (ID: {dt_id})")
        except Exception as e:
            console.log(f"  [yellow]Document type {dt_data['name']} may already exist: {e}")


async def create_storage_paths(paperless: Paperless) -> None:
    """Create storage paths in backend."""
    console.log("[blue]Creating storage paths...")
    for sp_data in STORAGE_PATHS:
        try:
            draft = paperless.storage_paths.draft(**sp_data)
            sp_id = await draft.save()
            console.log(f"  Created storage path: {sp_data['name']} (ID: {sp_id})")
        except Exception as e:
            console.log(f"  [yellow]Storage path {sp_data['name']} may already exist: {e}")


async def upload_documents(paperless: Paperless, fixtures_dir: Path, num_documents: int = 3) -> list[str]:
    """Upload PDFs via direct API call and return task IDs."""
    pdf_files = sorted(fixtures_dir.glob("*.pdf"))[:num_documents]

    if len(pdf_files) < num_documents:
        console.log(f"[yellow]Warning: Only found {len(pdf_files)} PDFs in {fixtures_dir}")

    console.log(f"[blue]Uploading {len(pdf_files)} documents...")

    task_ids = []
    # Use paperless.request_json for upload
    for pdf_path in pdf_files:
        try:
            console.log(f"  Uploading {pdf_path.name}...")

            # Use direct aiohttp with proper authorization
            data = aiohttp.FormData()
            with open(pdf_path, 'rb') as f:
                data.add_field('document',
                              f,
                              filename=pdf_path.name,
                              content_type='application/pdf')

                headers = {"Authorization": f"Token {paperless._token}"}
                url = f"{paperless.base_url}/api/documents/post_document/"

                async with aiohttp.ClientSession() as session:
                    async with session.post(url, data=data, headers=headers) as resp:
                        resp.raise_for_status()
                        result = await resp.json(content_type=None)
                        task_id = None
                        if isinstance(result, dict):
                            task_id = result.get("task_id") or result.get("id")
                        elif isinstance(result, str):
                            import re
                            if re.fullmatch(r"[0-9a-fA-F-]{36}", result):
                                task_id = result
                        elif isinstance(result, list):
                            for item in result:
                                if isinstance(item, dict) and item.get("task_id"):
                                    task_id = item["task_id"]
                                    break
                        if task_id:
                            task_ids.append(task_id)
                            console.log(f"  Uploaded {pdf_path.name} (task: {task_id})")
                        else:
                            console.log(f"  Uploaded {pdf_path.name} (no task ID)")
        except Exception as e:
            console.log(f"  [yellow]Upload {pdf_path.name} may have failed: {e}")

    return task_ids


def is_duplicate_task(result: str | None) -> bool:
    if not result:
        return False
    return "duplicate" in result.lower()


def task_to_dict(task: object) -> dict:
    if isinstance(task, dict):
        return task
    return {
        "task_id": task.task_id,
        "status": task.status,
        "result": task.result,
        "related_document": task.related_document,
        "id": task.id,
        "task_file_name": task.task_file_name,
    }


def normalize_task_status(value: object) -> str | None:
    if value is None:
        return None
    if hasattr(value, "value"):
        value = value.value
    if isinstance(value, str):
        return value.upper()
    return str(value).upper()


def extract_document_id(task: dict) -> int | None:
    related = task.get("related_document")
    if related is not None:
        try:
            return int(related)
        except (TypeError, ValueError):
            pass
    result = task.get("result")
    if isinstance(result, str):
        match = re.search(r"document id (\d+)", result, re.IGNORECASE)
        if match:
            return int(match.group(1))
        match = re.search(r"#(\d+)", result)
        if match:
            return int(match.group(1))
    return None


async def fetch_resource_map(resource_helper: object) -> dict[str, int]:
    resource_map: dict[str, int] = {}
    async for item in resource_helper:
        try:
            resource_map[str(item.name)] = int(item.id)
        except (AttributeError, TypeError, ValueError):
            continue
    return resource_map


async def fetch_tasks_by_id(
    paperless: Paperless,
    task_ids: list[str],
) -> dict[str, dict]:
    async def fetch_one(task_id: str) -> tuple[str, dict | None]:
        try:
            task = await paperless.tasks(task_id)
            return (task_id, task_to_dict(task))
        except TaskNotFoundError:
            return (task_id, None)
        except Exception as exc:
            return (task_id, exc)

    results = await asyncio.gather(
        *(fetch_one(task_id) for task_id in task_ids),
        return_exceptions=False,
    )

    return {
        task_id: payload
        for task_id, payload in results
        if isinstance(payload, dict)
    }


async def wait_for_processing(
    paperless: Paperless,
    task_ids: list[str],
    *,
    timeout: int = 120,
    poll_interval: float = 2.0,
) -> dict[str, dict]:
    """Wait for document processing tasks to complete."""
    if not task_ids:
        console.log("[yellow]No task IDs returned; skipping processing wait")
        return {}

    start_time = time.time()
    remaining = set(task_ids)
    task_details: dict[str, dict] = {}
    duplicate_failures: dict[str, str | None] = {}
    other_failures: dict[str, str | None] = {}
    missing_counts: dict[str, int] = {task_id: 0 for task_id in remaining}
    max_missing_polls = 3

    with console.status("[blue]Waiting for document processing tasks...") as status:
        while time.time() - start_time < timeout:
            try:
                tasks_by_id = await fetch_tasks_by_id(paperless, list(remaining))
            except Exception as e:
                console.log(f"[yellow]Failed to fetch tasks via pypaperless: {e}")
                tasks_by_id = {}

            for task_id, task in tasks_by_id.items():
                task_details[task_id] = task

            still_pending: set[str] = set()

            for task_id in remaining:
                task = tasks_by_id.get(task_id)
                if not task:
                    missing_counts[task_id] = missing_counts.get(task_id, 0) + 1
                    if missing_counts[task_id] >= max_missing_polls:
                        console.log(
                            f"[yellow]Task {task_id} missing from task list; assuming complete"
                        )
                        continue
                    still_pending.add(task_id)
                    continue
                missing_counts[task_id] = 0
                status_value = normalize_task_status(task.get("status"))
                if status_value == "SUCCESS":
                    continue
                if status_value in ("FAILURE", "REVOKED"):
                    result = task.get("result")
                    if is_duplicate_task(result):
                        duplicate_failures[task_id] = result
                    else:
                        other_failures[task_id] = result
                else:
                    still_pending.add(task_id)

            remaining = still_pending
            if not remaining:
                if duplicate_failures:
                    failure_lines = ", ".join(
                        f"{task_id} ({result})" if result else task_id
                        for task_id, result in duplicate_failures.items()
                    )
                    console.log(f"[yellow]Duplicate uploads detected: {failure_lines}")
                if other_failures:
                    failure_lines = ", ".join(
                        f"{task_id} ({result})" if result else task_id
                        for task_id, result in other_failures.items()
                    )
                    console.log(f"[yellow]Document processing failures: {failure_lines}")
                console.log("[green]Document processing complete")
                return task_details

            status.update(f"[blue]Waiting for {len(remaining)} task(s) to finish...")
            await asyncio.sleep(poll_interval)

    raise DocumentUploadError(f"Timed out waiting for document processing after {timeout}s")


async def update_document_metadata(
    paperless: Paperless,
    document_id: int,
    payload: dict[str, object],
) -> None:
    doc = await paperless.documents(document_id)
    if "tags" in payload:
        doc.tags = payload["tags"]
    if "correspondent" in payload:
        doc.correspondent = payload["correspondent"]
    if "document_type" in payload:
        doc.document_type = payload["document_type"]
    if "storage_path" in payload:
        doc.storage_path = payload["storage_path"]
    await doc.update()


async def assign_metadata(paperless: Paperless, document_ids: list[int]) -> None:
    if not document_ids:
        console.log("[yellow]No document IDs found; skipping metadata assignment")
        return

    console.log("[blue]Assigning document metadata...")
    tag_map = await fetch_resource_map(paperless.tags)
    correspondent_map = await fetch_resource_map(paperless.correspondents)
    document_type_map = await fetch_resource_map(paperless.document_types)
    storage_path_map = await fetch_resource_map(paperless.storage_paths)

    tag_ids = [tag_map[name] for name in (tag["name"] for tag in TAGS) if name in tag_map]
    correspondent_ids = [
        correspondent_map[name]
        for name in (corr["name"] for corr in CORRESPONDENTS)
        if name in correspondent_map
    ]
    document_type_ids = [
        document_type_map[name]
        for name in (doc_type["name"] for doc_type in DOCUMENT_TYPES)
        if name in document_type_map
    ]
    storage_path_ids = [
        storage_path_map[name]
        for name in (path["name"] for path in STORAGE_PATHS)
        if name in storage_path_map
    ]

    if not tag_ids and not correspondent_ids and not document_type_ids and not storage_path_ids:
        console.log("[yellow]No metadata IDs found; skipping document updates")
        return

    for index, document_id in enumerate(document_ids):
        payload: dict[str, object] = {}
        if tag_ids:
            primary = tag_ids[index % len(tag_ids)]
            secondary = tag_ids[(index + 1) % len(tag_ids)] if len(tag_ids) > 1 else None
            tags = [primary] + ([secondary] if secondary and secondary != primary else [])
            payload["tags"] = tags
        if correspondent_ids:
            payload["correspondent"] = correspondent_ids[index % len(correspondent_ids)]
        if document_type_ids:
            payload["document_type"] = document_type_ids[index % len(document_type_ids)]
        if storage_path_ids:
            payload["storage_path"] = storage_path_ids[index % len(storage_path_ids)]

        if not payload:
            continue

        await update_document_metadata(paperless, document_id, payload)
        console.log(f"  Updated document {document_id}")


async def setup_backend_async(
    url: str,
    username: str,
    password: str,
    fixtures_dir: Path,
    timeout: int
) -> str:
    """Main backend setup orchestrator."""
    # 1. Authenticate and get token
    token = await authenticate(url, username, password)

    # 2. Create and initialize Paperless client
    # Paperless client expects base URL without /api suffix
    base_url = url.rstrip('/')
    async with Paperless(base_url, token) as paperless:
        console.log("[green]Paperless client initialized")

        # 3. Create metadata entities
        await create_tags(paperless)
        await create_correspondents(paperless)
        await create_document_types(paperless)
        await create_storage_paths(paperless)

        # 4. Upload documents
        task_ids = await upload_documents(paperless, fixtures_dir)

        # 5. Wait for processing
        task_details = await wait_for_processing(paperless, task_ids)

        document_ids = [
            document_id
            for task in task_details.values()
            if (document_id := extract_document_id(task)) is not None
        ]
        await assign_metadata(paperless, document_ids)

    console.print(f"\n[bold green]Backend setup complete!")
    console.print(f"[bold cyan]Auth token:[/bold cyan] {token}")
    console.print(f"[bold cyan]Use this token with the capture command's --preview-token option")

    return token


# ============================================================================
# Commands
# ============================================================================


@app.command()
def setup(
    recreate: Annotated[bool, typer.Option("--recreate", help="Tear down and recreate containers")] = False,
    url: Annotated[str, typer.Option("--url", help="Paperless-ngx URL")] = "http://localhost:9988",
    username: Annotated[str, typer.Option("--username", help="Admin username")] = "admin",
    password: Annotated[str, typer.Option("--password", help="Admin password")] = "admin",
    fixtures_dir: Annotated[Path, typer.Option("--fixtures-dir", help="PDF fixtures directory")] = Path("Preview PDFs"),
    wait_timeout: Annotated[int, typer.Option("--wait-timeout", help="Backend readiness timeout (seconds)")] = 120,
) -> None:
    """Setup backend: start Docker and populate with test data."""
    try:
        # 1. Manage Docker lifecycle
        compose_file = Path("docker-compose.screenshot.yml")
        if not compose_file.exists():
            console.print(f"[red]Error: {compose_file} not found")
            raise typer.Exit(1)

        manage_docker_backend(compose_file, recreate, wait_timeout, url)

        # 2. Validate fixtures directory
        if not fixtures_dir.exists():
            console.print(f"[red]Error: Fixtures directory not found: {fixtures_dir}")
            raise typer.Exit(1)

        pdf_files = list(fixtures_dir.glob("*.pdf"))
        if not pdf_files:
            console.print(f"[red]Error: No PDF files found in {fixtures_dir}")
            raise typer.Exit(1)

        console.log(f"Found {len(pdf_files)} PDF files in {fixtures_dir}")

        # 3. Populate backend
        asyncio.run(setup_backend_async(url, username, password, fixtures_dir, wait_timeout))

    except BackendNotReadyError:
        console.print(f"[red]Error: Backend not ready. Check Docker logs:")
        console.print(f"[yellow]  docker compose -f docker-compose.screenshot.yml logs")
        raise typer.Exit(1)
    except AuthenticationError as e:
        console.print(f"[red]Error: {e}")
        raise typer.Exit(1)
    except DocumentUploadError as e:
        raise e
        console.print(f"[red]Error: {e}")
        raise typer.Exit(1)
    except Exception as e:
        console.print(f"[red]Unexpected error: {e}")
        raise


@app.command()
def capture(
    languages: Annotated[list[str], typer.Option("--language", "-l", help="Language tags to capture")] = ["en-US"],
    output_dir: Annotated[Path, typer.Option("--output-dir", "-o", help="Screenshot output directory")] = Path("fastlane/screenshots"),
    bundle_id: Annotated[str, typer.Option("--bundle-id", help="App bundle identifier")] = "com.paulgessinger.swift-paperless",
    device_name: Annotated[str, typer.Option("--device-name", help="Device name for filenames")] = "iPhone-16-Pro",
    launch_wait: Annotated[float, typer.Option("--launch-wait", help="Seconds to wait after launching app")] = 2.0,
    url_wait: Annotated[float, typer.Option("--url-wait", help="Seconds to wait after opening URL")] = 2.0,
    status_bar_time: Annotated[str, typer.Option("--status-bar-time", help="Status bar time (ISO 8601)")] = "2007-01-09T09:41:00.000+01:00",
    status_bar_cellular_bars: Annotated[int, typer.Option("--status-bar-cellular-bars", min=0, max=4, help="Cellular signal strength")] = 4,
    appearance: Annotated[str, typer.Option("--appearance", help="Simulator appearance (light/dark)")] = "light",
    steps: Annotated[list[str], typer.Option("--step", help="Screenshot steps (name=url[@wait])")] = [],
    preview_mode: Annotated[bool, typer.Option("--preview-mode", help="Enable preview mode")] = False,
    preview_url: Annotated[str, typer.Option("--preview-url", help="Preview mode backend URL")] = "http://localhost:9988/api/",
    preview_token: Annotated[str, typer.Option("--preview-token", help="Preview mode auth token")] = "",
    dry_run: Annotated[bool, typer.Option("--dry-run", help="Print commands without executing")] = False,
) -> None:
    """Capture screenshots from iOS simulator."""
    screenshot_steps = parse_steps(steps)
    output_dir.mkdir(parents=True, exist_ok=True)
    display_plan(languages, screenshot_steps)

    configure_simulator(
        status_bar_time=status_bar_time,
        status_bar_cellular_bars=status_bar_cellular_bars,
        appearance=appearance,
        dry_run=dry_run,
    )

    # Prepare environment variables for preview mode
    env = os.environ.copy() if preview_mode else None
    if preview_mode:
        if not preview_token:
            console.print("[red]Error: --preview-token is required when --preview-mode is enabled")
            raise typer.Exit(1)

        env["PreviewMode"] = "1"
        env["PreviewURL"] = preview_url
        env["PreviewToken"] = preview_token
        console.log(f"[green]Preview mode enabled: {preview_url}")

    for language in languages:
        language_slug = sanitize_filename(language)
        language_dir = output_dir / language_slug
        language_dir.mkdir(parents=True, exist_ok=True)
        console.rule(f"[bold green]Language: {language}")

        simctl(["terminate", "booted", bundle_id], check=False, dry_run=dry_run)
        simctl(
            [
                "launch",
                "booted",
                bundle_id,
                "-AppleLanguages",
                f"({language})",
                "-AppleLocale",
                language,
            ],
            dry_run=dry_run,
            env=env,
        )
        if launch_wait > 0:
            time.sleep(launch_wait)

        for index, step in enumerate(screenshot_steps, start=1):
            wait_time = step.wait if step.wait is not None else url_wait
            if step.url:
                simctl(["openurl", "booted", step.url], dry_run=dry_run)
                if wait_time > 0:
                    time.sleep(wait_time)
            elif step.wait is not None and wait_time > 0:
                time.sleep(wait_time)

            screenshot_name = f"{device_name}-{index:02d}_{sanitize_filename(step.name)}.png"
            output_path = language_dir / screenshot_name
            simctl(
                ["io", "booted", "screenshot", "--type", "png", str(output_path)],
                dry_run=dry_run,
            )
            console.log(f"Saved {output_path}")

            if step.post_url:
                simctl(["openurl", "booted", step.post_url], dry_run=dry_run)
                if wait_time > 0:
                    time.sleep(wait_time)


if __name__ == "__main__":
    app()
