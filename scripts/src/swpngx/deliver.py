"""Upload App Store metadata and framed screenshots with the `asc` CLI."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from typing import Annotated

from rich.console import Console
import typer

from swpngx.devices_config import load_screenshot_devices

console = Console()

BUNDLE_ID = "com.paulgessinger.swift-paperless"
PLATFORM = "IOS"
PRIMARY_LOCALE = "en-US"
DEFAULT_DIR = "default"
REVIEW_DIR = "review_information"
RELEASE_NOTES = "release_notes.txt"

# App Store Connect category files and the `asc categories set` flag each feeds.
CATEGORY_FLAGS = {
    "primary_category.txt": "--primary",
    "primary_first_sub_category.txt": "--primary-subcategory-one",
    "primary_second_sub_category.txt": "--primary-subcategory-two",
    "secondary_category.txt": "--secondary",
    "secondary_first_sub_category.txt": "--secondary-subcategory-one",
    "secondary_second_sub_category.txt": "--secondary-subcategory-two",
}

# asc reads ASC_*; these are the names the CI secrets use.
CREDENTIAL_ENV = {
    "APP_STORE_CONNECT_API_KEY_ID": "ASC_KEY_ID",
    "APP_STORE_CONNECT_ISSUER_ID": "ASC_ISSUER_ID",
    "APP_STORE_CONNECT_KEY_FILEPATH": "ASC_PRIVATE_KEY_PATH",
    "APP_STORE_CONNECT_KEY_CONTENT": "ASC_PRIVATE_KEY",
}


def asc(*args: str) -> None:
    subprocess.run(["asc", *args], check=True)


def asc_json(*args: str) -> dict:
    result = subprocess.run(
        ["asc", *args, "--output", "json"],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def stage_metadata(metadata_dir: Path, stage_dir: Path) -> list[str]:
    """Copy `metadata_dir` to `stage_dir/metadata` with `default/` expanded.

    `asc` skips `default/`, so every locale gets its files unless it overrides
    them. What's New is written once in `default/` and applies to every locale.
    """
    defaults = metadata_dir / DEFAULT_DIR
    locales = {
        path.name
        for path in metadata_dir.iterdir()
        if path.is_dir() and path.name not in (DEFAULT_DIR, REVIEW_DIR)
    } | {PRIMARY_LOCALE}

    for locale in sorted(locales):
        target = stage_dir / "metadata" / locale
        target.mkdir(parents=True)
        for source in (defaults, metadata_dir / locale):
            for file in source.glob("*.txt"):
                shutil.copy(file, target / file.name)
        shutil.copy(defaults / RELEASE_NOTES, target / RELEASE_NOTES)

    review = metadata_dir / REVIEW_DIR
    if review.is_dir() and any(review.iterdir()):
        shutil.copytree(review, stage_dir / "metadata" / REVIEW_DIR)
    return sorted(locales)


def read_categories(metadata_dir: Path) -> list[str]:
    """Return the `asc categories set` flags for the category files in use."""
    flags: list[str] = []
    for name, flag in CATEGORY_FLAGS.items():
        file = metadata_dir / name
        value = file.read_text(encoding="utf-8").strip() if file.exists() else ""
        if value:
            flags += [flag, value]
    return flags


def screenshot_display_types(screenshots_dir: Path, devices_file: Path) -> list[str]:
    """Return the display type of each device with framed screenshots."""
    devices = load_screenshot_devices(devices_file).devices
    types = [
        device.asc_display_type
        for device in devices
        if any(screenshots_dir.glob(f"*/{device.id}-*-framed.png"))
    ]
    if not types:
        console.print(
            f"[red]No framed screenshots in {screenshots_dir}; run `swpngx frame`.[/red]"
        )
        raise typer.Exit(1)
    return types


def find_app_id() -> str:
    apps = asc_json("apps", "list", "--bundle-id", BUNDLE_ID)["data"]
    if not apps:
        console.print(f"[red]No App Store Connect app for {BUNDLE_ID}[/red]")
        raise typer.Exit(1)
    return apps[0]["id"]


def find_version_id(app_id: str, version: str) -> str | None:
    versions = asc_json(
        "versions",
        "list",
        "--app",
        app_id,
        "--version",
        version,
        "--platform",
        PLATFORM,
    )["data"]
    return versions[0]["id"] if versions else None


def upload_metadata(
    app_id: str, version_id: str, stage_dir: Path, metadata_dir: Path, dry_run: bool
) -> None:
    mode = "--dry-run" if dry_run else "--confirm"
    asc(
        "migrate",
        "import",
        "--app",
        app_id,
        "--version-id",
        version_id,
        "--fastlane-dir",
        str(stage_dir),
        "--skip-screenshots",
        "--output",
        "table",
        mode,
    )

    copyright_file = metadata_dir / "copyright.txt"
    copyright_text = copyright_file.read_text(encoding="utf-8").strip()
    categories = read_categories(metadata_dir)
    if dry_run:
        console.print(f"Would set copyright: {copyright_text}")
        console.print(f"Would set categories: {' '.join(categories)}")
        return
    asc("versions", "update", "--version-id", version_id, "--copyright", copyright_text)
    asc("categories", "set", "--app", app_id, *categories)


def upload_screenshots(
    app_id: str,
    version_id: str,
    screenshots_dir: Path,
    display_types: list[str],
    dry_run: bool,
) -> None:
    for display_type in display_types:
        asc(
            "screenshots",
            "upload",
            "--app",
            app_id,
            "--version-id",
            version_id,
            "--path",
            str(screenshots_dir),
            "--device-type",
            display_type,
            "--replace",
            "--output",
            "table",
            "--dry-run" if dry_run else "--confirm",
        )


def main(
    version: Annotated[
        str,
        typer.Option(help="App Store version, created if it does not exist yet"),
    ],
    metadata_dir: Annotated[
        Path, typer.Option(help="Path to the metadata directory")
    ] = Path("fastlane/metadata"),
    screenshots_dir: Annotated[
        Path, typer.Option(help="Path to the framed screenshots directory")
    ] = Path("fastlane/screenshots/framed"),
    devices_file: Annotated[
        Path, typer.Option(help="Path to screenshot_devices.toml")
    ] = Path("screenshot_devices.toml"),
    skip_screenshots: Annotated[
        bool, typer.Option(help="Upload metadata only")
    ] = False,
    dry_run: Annotated[
        bool, typer.Option(help="Show what would change without changing anything")
    ] = False,
) -> None:
    """Upload metadata and framed screenshots, replacing the existing screenshots."""
    if shutil.which("asc") is None:
        console.print("[red]asc not found; install it with `brew install asc`[/red]")
        raise typer.Exit(1)

    for source, target in CREDENTIAL_ENV.items():
        if source in os.environ:
            os.environ.setdefault(target, os.environ[source])

    display_types = (
        []
        if skip_screenshots
        else screenshot_display_types(screenshots_dir, devices_file)
    )

    with tempfile.TemporaryDirectory(prefix="swpngx-deliver-") as tmp:
        stage_dir = Path(tmp)
        locales = stage_metadata(metadata_dir, stage_dir)
        console.print(f"Metadata locales: {', '.join(locales)}")
        asc(
            "migrate", "validate", "--fastlane-dir", str(stage_dir), "--output", "table"
        )

        app_id = find_app_id()
        version_id = find_version_id(app_id, version)
        if version_id is None and dry_run:
            console.print(
                f"Version {version} does not exist yet and would be created; "
                "nothing to compare against."
            )
            return
        if version_id is None:
            console.print(f"Creating version {version}")
            created = asc_json(
                "versions",
                "create",
                "--app",
                app_id,
                "--version",
                version,
                "--platform",
                PLATFORM,
            )
            version_id = created["data"]["id"]

        upload_metadata(app_id, version_id, stage_dir, metadata_dir, dry_run)
        if display_types:
            upload_screenshots(
                app_id, version_id, screenshots_dir, display_types, dry_run
            )
