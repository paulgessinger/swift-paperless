"""Download screenshot framing fonts on demand."""

from __future__ import annotations

import urllib.request
from pathlib import Path
from typing import Annotated

import typer
from pydantic import BaseModel
from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover
    import tomli as tomllib

console = Console()


class FontSpec(BaseModel):
    url: str
    path: Path


class FontsConfig(BaseModel):
    model_config = {"extra": "allow"}

    def fonts(self) -> dict[str, FontSpec]:
        extra = self.model_extra or {}
        return {key: FontSpec(**value) for key, value in extra.items()}


def load_fonts_config(path: Path) -> FontsConfig:
    data = tomllib.loads(path.read_text(encoding="utf-8"))
    return FontsConfig.model_validate(data)


def resolve_font_path(frames_config: Path) -> Path:
    data = tomllib.loads(frames_config.read_text(encoding="utf-8"))
    font_file = data.get("font_file")
    if not isinstance(font_file, str):
        raise ValueError(f"font_file not set in {frames_config}")
    return (frames_config.parent / font_file).resolve()


def download_font(spec: FontSpec, *, force: bool = False) -> Path:
    destination = spec.path
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_file() and not force:
        console.log(f"Using cached {destination}")
        return destination.resolve()

    console.log(f"Downloading {spec.url}")
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

        urllib.request.urlretrieve(spec.url, destination, reporthook=report)

    console.log(f"[green]Installed {destination}")
    return destination.resolve()


def ensure_framing_font(
    frames_config: Path,
    fonts_config: Path | None = None,
    *,
    force: bool = False,
) -> Path:
    """Download the framing font if missing."""
    frames_config = frames_config.resolve()
    repo_root = frames_config.parent
    font_path = resolve_font_path(frames_config)
    if font_path.is_file() and not force:
        return font_path

    config_path = (fonts_config or repo_root / "fonts.toml").resolve()
    fonts = load_fonts_config(config_path)
    available = fonts.fonts()
    if "open_sans" not in available:
        raise FileNotFoundError(
            f"Font missing at {font_path} and no open_sans entry in {config_path}"
        )

    spec = available["open_sans"]
    if spec.path.resolve() != font_path:
        spec = FontSpec(url=spec.url, path=font_path)

    return download_font(spec, force=force)


def download_fonts(
    fonts_config: Annotated[
        Path, typer.Option("--config", exists=True, dir_okay=False)
    ] = Path("fonts.toml"),
    frames_config: Annotated[
        Path, typer.Option("--frames", exists=True, dir_okay=False)
    ] = Path("frames.toml"),
    force: Annotated[bool, typer.Option("--force", help="Re-download fonts")] = False,
) -> None:
    """Download fonts listed in fonts.toml (used by swpngx frame)."""
    fonts = load_fonts_config(fonts_config.resolve())
    target_path = resolve_font_path(frames_config.resolve())
    available = fonts.fonts()

    if "open_sans" not in available:
        console.log(f"[red]No fonts defined in {fonts_config}")
        raise typer.Exit(1)

    spec = available["open_sans"]
    if spec.path.resolve() != target_path:
        spec = FontSpec(url=spec.url, path=target_path)

    download_font(spec, force=force)
    console.log("[green]Done")
