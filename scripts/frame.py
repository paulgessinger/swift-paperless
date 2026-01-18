#!/usr/bin/env python3
# /// script
# dependencies = [
# "Pillow",
# "pyyaml",
# "pydantic",
# "rich",
# "typer",
# "numpy",
# ]
# ///

import multiprocessing
import os
import re
import textwrap
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path
from typing import Annotated, Optional

import numpy
import typer
import yaml
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from pydantic import BaseModel, ConfigDict, Field, RootModel, SkipValidation
from rich.console import Console

from string_catalog import load as load_string_catalog

console = Console()


class Point(RootModel):
    root: tuple[int, int]

    @property
    def x(self) -> int:
        return self.root[0]

    @property
    def y(self) -> int:
        return self.root[1]

    def __iter__(self):
        return iter(self.root)

    def __getitem__(self, key):
        return self.root[key]

    def __len__(self):
        return 2

    def __add__(self, other: "Point") -> "Point":
        return Point((self.x + other.x, self.y + other.y))


class DeviceConfig(BaseModel):
    model_config = ConfigDict(arbitrary_types_allowed=True)

    frame_path: Path = Field(alias="frame")
    name: str
    frame: Annotated[Image.Image | None, SkipValidation] = None
    offset: Point = Field(default_factory=lambda: Point((0, 0)))
    post_offset: Point = Field(default_factory=lambda: Point((0, 0)))
    post_margin: int = 0
    target_size: Point
    mask_corner_radius: int
    mask_margin: int

    shadow_blur: int = 30


class ScreenStyle(BaseModel):
    background_color_internal: str | None = Field(
        default=None, alias="background_color"
    )
    text_color_internal: str | None = Field(default=None, alias="text_color")
    text_offset_internal: Point | None = Field(
        default=None, alias="text_offset"
    )
    text_size_internal: int | None = Field(default=None, alias="text_size")
    text_wrap_internal: int | None = Field(default=None, alias="text_wrap")
    font_spacing_internal: int | None = Field(
        default=None, alias="font_spacing"
    )
    shadow_color_internal: str | None = Field(
        default=None, alias="shadow_color"
    )

    @property
    def background_color(self) -> str:
        return self.background_color_internal or "#FFFFFF"

    @property
    def text_color(self) -> str:
        return self.text_color_internal or "#000000"

    @property
    def text_offset(self) -> Point:
        return self.text_offset_internal or Point((0, 0))

    @property
    def text_size(self) -> int:
        return self.text_size_internal or 100

    @property
    def text_wrap(self) -> int | None:
        return self.text_wrap_internal

    @property
    def font_spacing(self) -> int:
        return self.font_spacing_internal or 10

    @property
    def shadow_color(self) -> str:
        return self.shadow_color_internal or "#000000"

    def merged(self, other: Optional["ScreenStyle"]) -> "ScreenStyle":
        if other is None:
            return self

        return ScreenStyle(
            background_color=other.background_color_internal
            or self.background_color_internal,
            text_color=other.text_color_internal or self.text_color_internal,
            text_offset=other.text_offset_internal or self.text_offset_internal,
            text_size=other.text_size_internal or self.text_size_internal,
            text_wrap=other.text_wrap_internal or self.text_wrap_internal,
            font_spacing=other.font_spacing_internal or self.font_spacing_internal,
            shadow_color=other.shadow_color_internal or self.shadow_color_internal,
        )


class ScreenConfig(BaseModel):
    device_pattern: str = ".*"
    screen_pattern: str = ".*"

    title_key: str | None = None

    style: ScreenStyle | None = None


class Config(BaseModel):
    devices: list[DeviceConfig]
    screens: list[ScreenConfig]

    def __getitem__(self, key: str) -> DeviceConfig:
        for device in self.devices:
            if device.name == key:
                return device
        raise KeyError(key)

    def load_frames(self, base: Path) -> None:
        frame_dir = base / "frames"
        for device in self.devices:
            device.frame = Image.open(frame_dir / device.frame_path).convert("RGBA")

    def load_screen_config(
        self, device: str, file: Path
    ) -> tuple[ScreenConfig, ScreenStyle]:
        stem = file.stem
        config = ScreenConfig()
        style = ScreenStyle()

        for screen in self.screens:
            matches_screen = re.search(screen.screen_pattern, stem)
            matches_device = re.search(screen.device_pattern, device)
            if matches_screen and matches_device:
                config = screen
                style = style.merged(screen.style)

        return config, style


root_dir = Path(__file__).parent.parent

LANGUAGE_OVERRIDES = {
    "da-DA": "da",
    "pl-PL": "pl",
}

_FRAME_CONFIG: Config | None = None
_STRING_TITLES: dict[str, dict[str, str]] | None = None
_FONT_FILE: Path | None = None
_OUTPUT_DIR: Path | None = None


def should_process_file(file: Path) -> bool:
    return (
        file.suffix.lower() == ".png"
        and not file.stem.endswith("-framed")
        and "frames" not in file.parts
    )


def collect_input_files(inputs: list[Path]) -> list[Path]:
    files: list[Path] = []
    for input_path in inputs:
        if input_path.is_file():
            if should_process_file(input_path):
                files.append(input_path)
            continue
        for root, _dirs, filenames in os.walk(input_path):
            root_path = Path(root)
            for filename in filenames:
                candidate = root_path / filename
                if should_process_file(candidate):
                    files.append(candidate)
    return sorted(files)


def init_worker(
    config_file: Path,
    string_catalog_file: Path,
    output_dir: Path,
    font_file: Path,
) -> None:
    global _FRAME_CONFIG, _STRING_TITLES, _FONT_FILE, _OUTPUT_DIR
    with config_file.open() as file_handle:
        config = Config(**yaml.safe_load(file_handle))
    config.load_frames(Path(__file__).parent)
    _FRAME_CONFIG = config
    _STRING_TITLES = load_string_catalog(string_catalog_file.read_text()).as_dict()
    _FONT_FILE = font_file
    _OUTPUT_DIR = output_dir


def frame_worker(file: Path) -> None:
    if _FRAME_CONFIG is None or _STRING_TITLES is None:
        raise RuntimeError("Worker config not initialized")
    if _FONT_FILE is None or _OUTPUT_DIR is None:
        raise RuntimeError("Worker paths not initialized")
    frame(file, _FRAME_CONFIG, _OUTPUT_DIR, _STRING_TITLES, _FONT_FILE)


def main(
    inputs: Annotated[
        list[Path], typer.Argument(exists=True, help="Input directories or files")
    ] = [root_dir / "fastlane/screenshots"],
    output_folder: Annotated[
        Path, typer.Option("--output", file_okay=False, writable=True)
    ] = root_dir
    / "fastlane/screenshots/framed",
    config_file: Annotated[
        Path, typer.Option("--config", exists=True, dir_okay=False)
    ] = root_dir
    / "fastlane/screenshots/frames.yml",
    jobs: Annotated[int, typer.Option("--jobs", "-j")] = multiprocessing.cpu_count(),
):
    jobs = max(1, jobs)
    with config_file.open() as file_handle:
        config = Config(**yaml.safe_load(file_handle))
    config.load_frames(Path(__file__).parent)

    string_catalog_file = config_file.parent / "Screenshots.xcstrings"
    if not string_catalog_file.is_file():
        console.log("[red]String catalog not found")
        raise typer.Exit(1)
    string_titles = load_string_catalog(string_catalog_file.read_text()).as_dict()

    output_folder.mkdir(parents=True, exist_ok=True)

    files = collect_input_files(inputs)
    if not files:
        console.log("[yellow]No screenshots found to frame")
        return

    # font_file = config_file.parent / "DejaVuSans-Bold.ttf"
    font_file = config_file.parent / "OpenSans-VariableFont_wdth,wght.ttf"
    #  font_file = config_file.parent / "helvetica-bold.ttf"

    if jobs == 1 or len(files) == 1:
        for file in files:
            frame(file, config, output_folder, string_titles, font_file)
    else:
        with ProcessPoolExecutor(
            max_workers=jobs,
            initializer=init_worker,
            initargs=(config_file, string_catalog_file, output_folder, font_file),
        ) as executor:
            futures = [executor.submit(frame_worker, file) for file in files]
            for future in as_completed(futures):
                future.result()

    console.log("[green]Done")


def get_device_name(name: str):
    # Expected format: {device_name}-{index:02d}_{step_name}
    # Example: iPhone_16_Pro-01_documents
    # We need to extract everything before the last hyphen followed by digits
    match = re.match(r"^(.+)-\d+_", name)
    if match:
        return match.group(1)
    # Fallback to old behavior
    return "-".join(name.split("-")[:-1])


def get_language(file: Path) -> str:
    return file.parent.name


def round_rect(x, y, w, h, r, draw, **kwargs):
    d = r * 2

    for b in [
        [(x, y), (x + d, y + d)],
        [(x + w - d, y), (x + w, y + d)],
        [(x + w - d, y + h - d), (x + w, y + h)],
        [(x, y + h - d), (x + d, y + h)],
    ]:
        draw.ellipse(b, **kwargs)

    for b in [
        [(x + r, y), (x + w - r, y + h)],
        [(x, y + r), (x + w, y + h - r)],
    ]:
        draw.rectangle(b, **kwargs)


def color_as_rgb(color: str) -> tuple[int, int, int]:
    if color.startswith("#"):
        color = color[1:]
    return tuple(int(color[i : i + 2], 16) for i in (0, 2, 4))


def make_shadow(image: Image.Image, blur: int, color: str) -> Image.Image:
    shadow = image.copy()
    data = numpy.asarray(shadow).copy()
    r, g, b = color_as_rgb(color)
    data[:, :, 0] = r
    data[:, :, 1] = g
    data[:, :, 2] = b

    image = Image.fromarray(data, "RGBA")
    image = image.filter(ImageFilter.GaussianBlur(blur))
    return image


def drop_shadow(image: Image.Image, blur: int, color: str, debug: bool) -> Image.Image:
    shadow = make_shadow(image, blur, color)
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))

    result = Image.new("RGBA", image.size)
    result.alpha_composite(shadow)
    result.alpha_composite(image)

    if debug:
        debug_shadow = make_shadow(image, 0, "#ff0000")
        result.alpha_composite(debug_shadow)

    return result


def frame(
    file: Path,
    config: Config,
    output_dir: Path,
    titles: dict[str, dict[str, str]],
    font_file: Path,
):
    console.log(f"Framing {file}")
    device_name = get_device_name(file.stem)
    lang = get_language(file)
    lang = LANGUAGE_OVERRIDES.get(lang, lang)
    lang_code = lang.split("-")[0]

    console.log(f" - Device: {device_name} | Locale: {lang}")

    try:
        frame_config = config[device_name]
    except KeyError:
        console.log(" - No frame config found")
        return
    if frame_config.frame is None:
        raise ValueError(f"Frame image not loaded for {device_name}")

    screen_config, screen_style = config.load_screen_config(device_name, file)

    screenshot_raw = Image.open(file).convert("RGBA")
    screenshot_raw = screenshot_raw.resize([*frame_config.target_size])

    screenshot = Image.new("RGBA", frame_config.frame.size)
    screenshot.paste(screenshot_raw, box=[*frame_config.offset])

    buffer = Image.new("RGBA", frame_config.frame.size)

    mask = Image.new("RGBA", frame_config.frame.size)
    x, y = frame_config.offset
    x -= frame_config.mask_margin
    y -= frame_config.mask_margin
    w, h = frame_config.target_size
    w += frame_config.mask_margin * 2
    h += frame_config.mask_margin * 2
    r = frame_config.mask_corner_radius
    round_rect(x, y, w, h, r, ImageDraw.Draw(mask), fill="red")

    buffer.paste(screenshot, mask=mask)
    buffer.alpha_composite(frame_config.frame)

    # resize to original device screenshot size to comply with AppStore requirements
    output = Image.new("RGBA", screenshot_raw.size)
    output_draw = ImageDraw.Draw(output)
    output_draw.rectangle([0, 0, *output.size], fill=screen_style.background_color)

    font = ImageFont.truetype(str(font_file), screen_style.text_size)
    try:
        font.set_variation_by_name("Bold")
    except (AttributeError, OSError, ValueError):
        pass

    if title_key := screen_config.title_key:
        text_buffer = Image.new("RGBA", screenshot_raw.size)
        text_buffer_draw = ImageDraw.Draw(text_buffer)
        title = titles.get(title_key, {}).get(lang_code, title_key.upper())
        if wrap_size := screen_style.text_wrap:
            title = "\n".join(textwrap.wrap(title, wrap_size))
        text_buffer_draw.multiline_text(
            [*screen_style.text_offset],
            title,
            fill=screen_style.text_color,
            font=font,
            spacing=screen_style.font_spacing,
        )
        output.alpha_composite(text_buffer)

    aspect_ratio = buffer.size[0] / buffer.size[1]
    target_size = (screenshot_raw.size[0], int(screenshot_raw.size[0] / aspect_ratio))
    buffer = buffer.resize(target_size)

    if frame_config.post_margin:
        aspect_ratio = buffer.size[0] / buffer.size[1]
        new_w = buffer.size[0] - frame_config.post_margin * 2
        new_h = int(new_w / aspect_ratio)
        buffer = buffer.resize((new_w, new_h))

    delta_x = (output.size[0] - buffer.size[0]) // 2
    delta_y = (output.size[1] - buffer.size[1]) // 2

    offset_buffer = Image.new("RGBA", output.size)
    offset_buffer.paste(
        buffer,
        box=[
            delta_x + frame_config.post_offset[0],
            delta_y + frame_config.post_offset[1],
        ],
    )

    offset_buffer = drop_shadow(
        offset_buffer,
        frame_config.shadow_blur,
        color=screen_style.shadow_color,
        debug=False,
    )
    output.alpha_composite(offset_buffer)

    locale_dir = output_dir / lang
    locale_dir.mkdir(parents=True, exist_ok=True)
    output_file = locale_dir / f"{file.stem}-framed.png"
    console.log(f"Saving to {output_file}")
    output.save(output_file)


if __name__ == "__main__":
    typer.run(main)
