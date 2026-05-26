"""Download and extract Apple Product Bezel PNGs for screenshot framing."""

from __future__ import annotations

import platform
import re
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path
from typing import Annotated

import typer
from pydantic import BaseModel, Field
from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover
    import tomli as tomllib

from swpngx.devices_config import load_screenshot_devices, resolve_devices_path
from swpngx.frame import DeviceConfig, screenshot_device_to_frame_device

console = Console()

APPLE_BEZEL_LICENSE_ACK = "Y\n"
APPLE_DESIGN_RESOURCES_PAGE = "https://developer.apple.com/design/resources/"
DEFAULT_CACHE_DIR = Path.home() / "Library" / "Caches" / "swpngx" / "bezels"
FALLBACK_CACHE_DIR = Path(".cache") / "swpngx" / "bezels"


class BezelPack(BaseModel):
    url: str
    filename: str


def load_bezel_packs(path: Path) -> dict[str, BezelPack]:
    data = tomllib.loads(path.read_text(encoding="utf-8"))
    return {key: BezelPack(**value) for key, value in data.items()}


def default_cache_dir() -> Path:
    if sys.platform == "darwin":
        return DEFAULT_CACHE_DIR
    return FALLBACK_CACHE_DIR


def parse_devices_with_packs(
    frames_config: Path,
    devices_config: Path | None = None,
) -> list[tuple[DeviceConfig, str]]:
    devices_path = resolve_devices_path(frames_config, devices_config)
    screenshot_devices = load_screenshot_devices(devices_path)
    return [
        (screenshot_device_to_frame_device(device), device.bezel_pack)
        for device in screenshot_devices.devices
    ]


def packs_for_devices(
    devices: list[tuple[DeviceConfig, str]],
) -> dict[str, list[DeviceConfig]]:
    grouped: dict[str, list[DeviceConfig]] = {}
    for device, pack in devices:
        grouped.setdefault(pack, []).append(device)
    return grouped


def mount_dmg(dmg_path: Path) -> Path:
    if sys.platform != "darwin":
        raise typer.Exit("Mounting Apple bezel DMGs requires macOS (hdiutil).")

    result = subprocess.run(
        ["hdiutil", "attach", "-nobrowse", "-readonly", str(dmg_path)],
        input=APPLE_BEZEL_LICENSE_ACK,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        console.log(f"[red]hdiutil attach failed:\n{result.stderr}")
        raise typer.Exit(1)

    for line in reversed(result.stdout.splitlines()):
        if "/Volumes/" in line:
            mount_point = line.split("\t")[-1].strip()
            return Path(mount_point)

    console.log(
        f"[red]Could not parse mount point from hdiutil output:\n{result.stdout}"
    )
    raise typer.Exit(1)


def detach_dmg(mount_point: Path) -> None:
    subprocess.run(
        ["hdiutil", "detach", str(mount_point), "-quiet"],
        check=False,
    )


def index_bezel_pngs(root: Path) -> dict[str, Path]:
    index: dict[str, Path] = {}
    for png in root.rglob("*.png"):
        parts = set(png.parts)
        if ".DropDMGBackground" in parts:
            continue
        index[png.name] = png
    return index


def find_bezel_png(index: dict[str, Path], filename: str) -> Path | None:
    if filename in index:
        return index[filename]
    stem = Path(filename).stem
    matches = [path for name, path in index.items() if stem in name]
    if len(matches) == 1:
        return matches[0]
    return None


def suggest_similar(index: dict[str, Path], filename: str, limit: int = 8) -> list[str]:
    stem_words = set(re.split(r"[\s\-]+", Path(filename).stem.lower()))
    scored: list[tuple[int, str]] = []
    for name in index:
        name_words = set(re.split(r"[\s\-]+", Path(name).stem.lower()))
        score = len(stem_words & name_words)
        if score > 0:
            scored.append((score, name))
    scored.sort(reverse=True)
    return [name for _, name in scored[:limit]]


def download_dmg(url: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_file() and destination.stat().st_size > 0:
        console.log(f"Using cached {destination}")
        return

    console.log(f"Downloading {url}")
    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        console=console,
    ) as progress:
        progress.add_task(description=destination.name, total=None)

        def report(block_num: int, block_size: int, total_size: int) -> None:
            if total_size > 0 and block_num % 50 == 0:
                done = block_num * block_size
                percent = min(100, done * 100 // total_size)
                progress.update(
                    progress.task_ids[0], description=f"{destination.name} ({percent}%)"
                )

        urllib.request.urlretrieve(url, destination, reporthook=report)


def resolve_dmg_path(
    pack: BezelPack,
    pack_id: str,
    cache_dir: Path,
    dmg_path: Path | None,
    dmg_dir: Path | None,
    force_download: bool,
) -> Path:
    cached = cache_dir / pack.filename
    if dmg_path is not None and dmg_path.is_file():
        return dmg_path.resolve()
    if dmg_dir is not None:
        candidate = dmg_dir / pack.filename
        if candidate.is_file():
            return candidate.resolve()
    if cached.is_file() and not force_download:
        return cached
    if force_download and cached.is_file():
        cached.unlink()
    download_dmg(pack.url, cached)
    return cached


def extract_frames_from_mount(
    mount_point: Path,
    devices: list[DeviceConfig],
    repo_root: Path,
) -> None:
    png_root = mount_point / "PNG"
    search_root = png_root if png_root.is_dir() else mount_point
    index = index_bezel_pngs(search_root)

    for device in devices:
        destination = (repo_root / device.frame_path).resolve()
        filename = destination.name
        source = find_bezel_png(index, filename)
        if source is None:
            console.log(f"[red]Frame not found in DMG: {filename}")
            suggestions = suggest_similar(index, filename)
            if suggestions:
                console.log("Similar files in this pack:")
                for name in suggestions:
                    console.log(f"  - {name}")
            raise typer.Exit(1)

        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        console.log(f"[green]Installed {destination.relative_to(repo_root)}")


def download_frames(
    frames_config: Annotated[
        Path, typer.Option("--config", exists=True, dir_okay=False)
    ] = Path("frames.toml"),
    packs_config: Annotated[
        Path, typer.Option("--packs", exists=True, dir_okay=False)
    ] = Path("bezel_packs.toml"),
    cache_dir: Annotated[
        Path | None, typer.Option("--cache-dir", file_okay=False)
    ] = None,
    dmg_path: Annotated[
        Path | None,
        typer.Option(
            "--dmg-path",
            exists=True,
            help="Local bezel .dmg file (applies to a single pack when used with --pack)",
        ),
    ] = None,
    dmg_dir: Annotated[
        Path | None,
        typer.Option(
            "--dmg-dir",
            exists=True,
            file_okay=False,
            help="Directory containing bezel .dmg files (e.g. ~/Downloads)",
        ),
    ] = None,
    pack: Annotated[
        str | None,
        typer.Option(help="Install only this bezel pack id from bezel_packs.toml"),
    ] = None,
    force_download: Annotated[
        bool, typer.Option("--force-download", help="Re-download DMGs from Apple")
    ] = False,
) -> None:
    """Download Apple Product Bezels and copy frames required by frames.toml."""
    if sys.platform != "darwin":
        machine = platform.system()
        console.log(
            f"[red]This command requires macOS (found {machine}). "
            "Mount the DMG manually and copy PNGs into fastlane/screenshots/frames/."
        )
        raise typer.Exit(1)

    repo_root = frames_config.resolve().parent
    packs = load_bezel_packs(packs_config.resolve())
    devices_with_packs = parse_devices_with_packs(frames_config.resolve())
    if not devices_with_packs:
        console.log("[yellow]No devices with bezel_pack configured in frames.toml")
        raise typer.Exit(0)

    grouped = packs_for_devices(devices_with_packs)
    if pack is not None:
        if pack not in grouped:
            available = ", ".join(sorted(grouped))
            console.log(
                f"[red]Pack {pack!r} not required by frames.toml "
                f"(configured packs: {available or 'none'})"
            )
            raise typer.Exit(1)
        grouped = {pack: grouped[pack]}

    resolved_cache = (cache_dir or default_cache_dir()).resolve()
    resolved_cache.mkdir(parents=True, exist_ok=True)
    console.log(f"Bezel cache: {resolved_cache}")
    console.log(f"Source: {APPLE_DESIGN_RESOURCES_PAGE}")

    single_dmg = dmg_path
    if single_dmg is not None and len(grouped) > 1 and pack is None:
        console.log(
            "[yellow]--dmg-path applies to one pack only; use --pack or --dmg-dir"
        )

    for pack_id, pack_devices in grouped.items():
        try:
            bezel_pack = packs[pack_id]
        except KeyError:
            known = ", ".join(sorted(packs))
            console.log(f"[red]Unknown bezel_pack {pack_id!r} (known: {known})")
            raise typer.Exit(1)

        local_dmg = single_dmg if pack is not None or len(grouped) == 1 else None
        dmg_file = resolve_dmg_path(
            bezel_pack,
            pack_id,
            resolved_cache,
            local_dmg,
            dmg_dir,
            force_download,
        )
        console.log(f"Mounting {dmg_file.name} for pack {pack_id}")
        mount_point = mount_dmg(dmg_file)
        try:
            extract_frames_from_mount(mount_point, pack_devices, repo_root)
        finally:
            detach_dmg(mount_point)

    console.log("[green]Done")
