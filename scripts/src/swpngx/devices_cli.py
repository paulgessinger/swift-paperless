"""Validate and fix alignment between screenshot configs and files."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Annotated

import typer
from rich.console import Console
from rich.table import Table

from swpngx.devices_config import load_screenshot_devices, resolve_devices_path
from swpngx.frame import get_device_name, load_config

console = Console()

KNOWN_LEGACY_PREFIXES: dict[str, str] = {
    "iPad_Pro_13-inch__M5_": "iPad_Pro_13_M5",
    "iPad_Pro_13-inch": "iPad_Pro_13_M5",
}


def collect_screenshot_prefixes(input_dir: Path) -> dict[str, list[Path]]:
    prefixes: dict[str, list[Path]] = {}
    if not input_dir.is_dir():
        return prefixes
    skip_dirs = {"frames", "framed"}
    for png in input_dir.rglob("*.png"):
        if skip_dirs & set(png.parts):
            continue
        if png.stem.endswith("-framed"):
            continue
        prefix = get_device_name(png.stem)
        prefixes.setdefault(prefix, []).append(png)
    return prefixes


def check_devices(
    frames_config: Annotated[
        Path, typer.Option("--frames", exists=True, dir_okay=False)
    ] = Path("frames.toml"),
    devices_config: Annotated[
        Path | None, typer.Option("--devices", exists=True, dir_okay=False)
    ] = None,
    screenshots_config: Annotated[
        Path, typer.Option("--screenshots", exists=True, dir_okay=False)
    ] = Path("screenshots.toml"),
) -> None:
    """Verify screenshot_devices.toml matches capture output and frame assets."""
    frames_config = frames_config.resolve()
    repo_root = frames_config.parent
    devices_path = resolve_devices_path(frames_config, devices_config)
    screenshot_devices = load_screenshot_devices(devices_path)

    try:
        import tomllib
    except ModuleNotFoundError:  # pragma: no cover
        import tomli as tomllib

    screenshots_data = tomllib.loads(
        screenshots_config.resolve().read_text(encoding="utf-8")
    )
    configured_simulators = screenshots_data.get("simulators", [])
    configured_device_ids = {
        entry["device"] for entry in configured_simulators if "device" in entry
    }

    framing_config = load_config(frames_config)
    input_dir = repo_root / framing_config.input_folder
    prefixes = collect_screenshot_prefixes(input_dir)

    table = Table(title="Screenshot devices")
    table.add_column("id")
    table.add_column("simulator")
    table.add_column("bezel PNG")
    table.add_column("in screenshots.toml")
    table.add_column("screenshots on disk")

    issues: list[str] = []

    for device in screenshot_devices.devices:
        frame_path = (repo_root / device.frame_path).resolve()
        frame_ok = frame_path.is_file()
        in_capture = device.id in configured_device_ids
        on_disk = device.id in prefixes
        legacy_on_disk = [
            legacy
            for legacy, target in KNOWN_LEGACY_PREFIXES.items()
            if target == device.id and legacy in prefixes
        ]

        table.add_row(
            device.id,
            device.simulator_name,
            "yes" if frame_ok else "[red]missing[/red]",
            "yes" if in_capture else "[red]no[/red]",
            (
                "yes"
                if on_disk
                else (
                    f"[yellow]legacy: {', '.join(legacy_on_disk)}[/yellow]"
                    if legacy_on_disk
                    else "[red]none[/red]"
                )
            ),
        )

        if not frame_ok:
            issues.append(
                f"{device.id}: install bezel → uv run --project scripts swpngx frames download --pack {device.bezel_pack}"
            )
        if not in_capture:
            issues.append(
                f'{device.id}: add [[simulators]] device = "{device.id}" to screenshots.toml'
            )
        if not on_disk and legacy_on_disk:
            issues.append(
                f"{device.id}: rename screenshots from {legacy_on_disk[0]!r} prefix "
                f"(run: swpngx devices migrate-prefix)"
            )
        elif not on_disk:
            issues.append(f"{device.id}: no screenshots under {input_dir}")

    console.print(table)

    unknown_prefixes = set(prefixes) - {
        device.id for device in screenshot_devices.devices
    }
    for prefix in sorted(unknown_prefixes):
        issues.append(
            f"Unknown screenshot prefix {prefix!r} ({len(prefixes[prefix])} files) — "
            "add a [[device]] to screenshot_devices.toml or remove files"
        )

    if issues:
        console.print("\n[bold]Issues[/bold]")
        for issue in issues:
            console.log(f"[yellow]• {issue}")
        raise typer.Exit(1)

    console.log("[green]All devices aligned")


def migrate_prefix(
    frames_config: Annotated[
        Path, typer.Option("--frames", exists=True, dir_okay=False)
    ] = Path("frames.toml"),
    devices_config: Annotated[
        Path | None, typer.Option("--devices", exists=True, dir_okay=False)
    ] = None,
    dry_run: Annotated[
        bool, typer.Option("--dry-run", help="Print renames without applying")
    ] = False,
) -> None:
    """Rename screenshot files from legacy device prefixes to current ids."""
    frames_config = frames_config.resolve()
    repo_root = frames_config.parent
    devices_path = resolve_devices_path(frames_config, devices_config)
    screenshot_devices = load_screenshot_devices(devices_path)
    valid_targets = {device.id for device in screenshot_devices.devices}

    framing_config = load_config(frames_config)
    input_dir = repo_root / framing_config.input_folder
    prefixes = collect_screenshot_prefixes(input_dir)

    renames: list[tuple[Path, Path]] = []
    for legacy_prefix, target_id in KNOWN_LEGACY_PREFIXES.items():
        if target_id not in valid_targets:
            continue
        for path in prefixes.get(legacy_prefix, []):
            new_name = re.sub(
                rf"^{re.escape(legacy_prefix)}-",
                f"{target_id}-",
                path.name,
                count=1,
            )
            destination = path.with_name(new_name)
            if destination != path:
                renames.append((path, destination))

    if not renames:
        console.log("[green]No legacy prefixes to migrate")
        return

    for source, destination in renames:
        if destination.exists():
            console.log(f"[red]Would overwrite {destination}")
            raise typer.Exit(1)
        action = "Would rename" if dry_run else "Renaming"
        console.log(f"{action} {source.relative_to(repo_root)} → {destination.name}")
        if not dry_run:
            source.rename(destination)

    console.log(
        f"[green]{'Would rename' if dry_run else 'Renamed'} {len(renames)} file(s)"
    )
