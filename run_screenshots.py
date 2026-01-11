#!/usr/bin/env python3
# /// script
# dependencies = [
#   "rich",
#   "typer",
#   "pydantic>=2",
#   "pypaperless",
#   "aiohttp>=3.9",
#   "tomli; python_version < '3.11'",
# ]
# ///

import asyncio
from dataclasses import dataclass
import json
from pathlib import Path
import re
import subprocess
import time
from typing import Annotated

import aiohttp
import typer
from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator
from pypaperless import Paperless
from pypaperless.exceptions import TaskNotFoundError
from rich.console import Console
from rich.table import Table

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - fallback for Python < 3.11
    import tomli as tomllib

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
    ScreenshotStep("documents", wait=2),
    ScreenshotStep(
        "filter_tags",
        "x-paperless://v1/open_filter/tags",
        "x-paperless://v1/close_filter",
    ),
    ScreenshotStep("document_view", "x-paperless://v1/document/3?edit=0", wait=4),
    ScreenshotStep("document_edit", "x-paperless://v1/document/3?edit=1", wait=4),
]


class ScreenshotStepConfig(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str
    url: str | None = None
    post_url: str | None = None
    wait: float | None = None


def default_step_configs() -> list[ScreenshotStepConfig]:
    return [
        ScreenshotStepConfig(
            name=step.name,
            url=step.url,
            post_url=step.post_url,
            wait=step.wait,
        )
        for step in DEFAULT_STEPS
    ]


class PreviewConfig(BaseModel):
    model_config = ConfigDict(extra="forbid")

    mode: bool = True
    url: str = "http://localhost:9988/api/"
    token: str = ""
    username: str = "admin"
    password: str = "admin"


class CaptureConfig(BaseModel):
    model_config = ConfigDict(extra="forbid")

    locales: list[str] = Field(default_factory=lambda: ["en-US"])
    steps: list[ScreenshotStepConfig] = Field(default_factory=default_step_configs)
    output_dir: Path = Path("fastlane/screenshots")
    bundle_id: str = "com.paulgessinger.swift-paperless"
    device_name: str = "iPhone-16-Pro"
    simulator: str | None = None
    launch_wait: float = 2.0
    url_wait: float = 2.0
    status_bar_time: str = "2007-01-09T09:41:00.000+01:00"
    status_bar_cellular_bars: int = Field(default=4, ge=0, le=4)
    appearance: str = "light"
    preview: PreviewConfig = Field(default_factory=PreviewConfig)

    @field_validator("locales")
    @classmethod
    def validate_locales(cls, value: list[str]) -> list[str]:
        if not value:
            raise ValueError("At least one locale is required.")
        return value

    @field_validator("appearance")
    @classmethod
    def validate_appearance(cls, value: str) -> str:
        if value not in {"light", "dark"}:
            raise ValueError("Appearance must be 'light' or 'dark'.")
        return value


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

DOCUMENT_TITLES = [
    "Quarterly Statement",
    "Travel Itinerary",
    "Home Insurance Renewal",
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


def load_capture_config(path: Path) -> CaptureConfig:
    if not path.exists():
        console.print(f"[red]Error: Config file not found: {path}")
        raise typer.Exit(1)
    try:
        raw = tomllib.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        console.print(f"[red]Error: Failed to parse config file: {exc}")
        raise typer.Exit(1)
    try:
        return CaptureConfig.model_validate(raw)
    except ValidationError as exc:
        console.print(f"[red]Error: Invalid config file:")
        console.print(str(exc))
        raise typer.Exit(1)


def configure_simulator(
    *,
    target: str,
    status_bar_time: str,
    status_bar_cellular_bars: int,
    appearance: str,
    dry_run: bool,
) -> None:
    simctl(["ui", target, "appearance", appearance], dry_run=dry_run)
    simctl(
        [
            "status_bar",
            target,
            "override",
            "--time",
            status_bar_time,
            "--cellularBars",
            str(status_bar_cellular_bars),
        ],
        dry_run=dry_run,
    )


def normalize_preview_base_url(preview_url: str) -> str:
    trimmed = preview_url.rstrip("/")
    if trimmed.endswith("/api"):
        return trimmed[: -len("/api")]
    return trimmed


def set_preview_defaults(target: str, bundle_id: str, preview_url: str, preview_token: str, *, dry_run: bool) -> None:
    simctl(
        ["spawn", target, "defaults", "write", bundle_id, "PreviewMode", "-bool", "YES"],
        dry_run=dry_run,
    )
    simctl(
        ["spawn", target, "defaults", "write", bundle_id, "PreviewURL", "-string", preview_url],
        dry_run=dry_run,
    )
    simctl(
        ["spawn", target, "defaults", "write", bundle_id, "PreviewToken", "-string", preview_token],
        dry_run=dry_run,
    )


def clear_preview_defaults(target: str, bundle_id: str, *, dry_run: bool) -> None:
    simctl(
        ["spawn", target, "defaults", "delete", bundle_id, "PreviewMode"],
        check=False,
        dry_run=dry_run,
    )
    simctl(
        ["spawn", target, "defaults", "delete", bundle_id, "PreviewURL"],
        check=False,
        dry_run=dry_run,
    )
    simctl(
        ["spawn", target, "defaults", "delete", bundle_id, "PreviewToken"],
        check=False,
        dry_run=dry_run,
    )


def list_booted_simulators() -> list[dict[str, str]]:
    result = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "--json"],
        check=True,
        capture_output=True,
        text=True,
    )
    data = json.loads(result.stdout)
    devices = data.get("devices", {})
    booted: list[dict[str, str]] = []
    for runtime, runtime_devices in devices.items():
        for device in runtime_devices:
            if device.get("state") == "Booted":
                booted.append(
                    {
                        "name": device.get("name", "Unknown"),
                        "udid": device.get("udid", ""),
                        "runtime": runtime,
                    }
                )
    return booted


def resolve_simulator(simulator: str | None) -> str:
    booted = list_booted_simulators()
    if simulator:
        matches = [
            device
            for device in booted
            if device["udid"] == simulator or device["name"] == simulator
        ]
        if not matches:
            console.print(f"[red]Error: Simulator '{simulator}' is not booted.")
            raise typer.Exit(1)
        if len(matches) > 1:
            console.print(f"[red]Error: Multiple booted simulators match '{simulator}'.")
            for device in matches:
                console.print(f"  {device['name']} ({device['udid']}) - {device['runtime']}")
            raise typer.Exit(1)
        return matches[0]["udid"]

    if not booted:
        console.print("[red]Error: No booted simulators found.")
        raise typer.Exit(1)
    if len(booted) == 1:
        return booted[0]["udid"]

    console.print("[red]Error: Multiple booted simulators found. Please specify one with --simulator.")
    for device in booted:
        console.print(f"  {device['name']} ({device['udid']}) - {device['runtime']}")
    raise typer.Exit(1)


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
    for index, pdf_path in enumerate(pdf_files):
        try:
            console.log(f"  Uploading {pdf_path.name}...")

            # Use direct aiohttp with proper authorization
            data = aiohttp.FormData()
            title = DOCUMENT_TITLES[index % len(DOCUMENT_TITLES)]
            with open(pdf_path, 'rb') as f:
                data.add_field('title', title)
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
    config: Annotated[
        Path,
        typer.Option(
            "--config",
            "-c",
            help="Path to screenshots TOML config",
        ),
    ] = Path("screenshots.toml"),
    dry_run: Annotated[bool, typer.Option("--dry-run", help="Print commands without executing")] = False,
) -> None:
    """Capture screenshots from iOS simulator."""
    capture_config = load_capture_config(config)
    screenshot_steps = [
        ScreenshotStep(
            name=step.name,
            url=step.url,
            post_url=step.post_url,
            wait=step.wait,
        )
        for step in capture_config.steps
    ]
    languages = capture_config.locales
    output_dir = capture_config.output_dir
    bundle_id = capture_config.bundle_id
    device_name = capture_config.device_name
    simulator = capture_config.simulator
    launch_wait = capture_config.launch_wait
    url_wait = capture_config.url_wait
    status_bar_time = capture_config.status_bar_time
    status_bar_cellular_bars = capture_config.status_bar_cellular_bars
    appearance = capture_config.appearance
    preview_mode = capture_config.preview.mode
    preview_url = capture_config.preview.url
    preview_token = capture_config.preview.token
    preview_username = capture_config.preview.username
    preview_password = capture_config.preview.password

    output_dir.mkdir(parents=True, exist_ok=True)
    display_plan(languages, screenshot_steps)

    target = resolve_simulator(simulator)
    configure_simulator(
        target=target,
        status_bar_time=status_bar_time,
        status_bar_cellular_bars=status_bar_cellular_bars,
        appearance=appearance,
        dry_run=dry_run,
    )

    try:
        if preview_mode:
            if not preview_token:
                preview_base_url = normalize_preview_base_url(preview_url)
                preview_token = asyncio.run(
                    authenticate(preview_base_url, preview_username, preview_password)
                )
            console.log(f"[green]Preview mode enabled: {preview_url}")
            set_preview_defaults(
                target,
                bundle_id,
                preview_url,
                preview_token,
                dry_run=dry_run,
            )
        for language in languages:
            language_slug = sanitize_filename(language)
            language_dir = output_dir / language_slug
            language_dir.mkdir(parents=True, exist_ok=True)
            console.rule(f"[bold green]Language: {language}")

            simctl(["terminate", target, bundle_id], check=False, dry_run=dry_run)
            simctl(
                [
                    "launch",
                    "--terminate-running-process",
                    target,
                    bundle_id,
                    "-AppleLanguages",
                    f"({language})",
                    "-AppleLocale",
                    language,
                ],
                dry_run=dry_run,
            )
            if launch_wait > 0:
                time.sleep(launch_wait)

            for index, step in enumerate(screenshot_steps, start=1):
                wait_time = step.wait if step.wait is not None else url_wait
                if step.url:
                    simctl(["openurl", target, step.url], dry_run=dry_run)
                    if wait_time > 0:
                        time.sleep(wait_time)
                elif step.wait is not None and wait_time > 0:
                    time.sleep(wait_time)

                screenshot_name = f"{device_name}-{index:02d}_{sanitize_filename(step.name)}.png"
                output_path = language_dir / screenshot_name
                simctl(
                    ["io", target, "screenshot", "--type", "png", str(output_path)],
                    dry_run=dry_run,
                )
                console.log(f"Saved {output_path}")

                if step.post_url:
                    simctl(["openurl", target, step.post_url], dry_run=dry_run)
                    if wait_time > 0:
                        time.sleep(wait_time)
    finally:
        if preview_mode:
            clear_preview_defaults(target, bundle_id, dry_run=dry_run)


if __name__ == "__main__":
    app()
