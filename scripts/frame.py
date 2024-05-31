#!/usr/bin/env python3
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import argparse
import os
from pathlib import Path
import yaml
import pydantic
from pydantic import SkipValidation
from typing import Optional
from typing_extensions import Annotated
import re
import textwrap
import multiprocessing
from concurrent.futures import ProcessPoolExecutor, as_completed
from rich.progress import track
import gettext
import json
import requests
import typer
from rich.console import Console
import numpy

from string_catalog import load as load_string_catalog

console = Console()


class Point(pydantic.RootModel):
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


class DeviceConfig(pydantic.BaseModel):
    class Config:
        arbitrary_types_allowed = True

    frame_src: Path = pydantic.Field(alias="frame")
    name: str
    frame: Annotated[Image.Image, SkipValidation]
    offset: Point = pydantic.Field(default_factory=lambda: Point((0, 0)))
    post_offset: Point = pydantic.Field(default_factory=lambda: Point((0, 0)))
    post_size: Point | None = None
    target_size: Point
    mask_corner_radius: int
    mask_margin: int

    shadow_blur: int = 30


class ScreenStyle(pydantic.BaseModel):
    background_color_internal: str | None = pydantic.Field(
        default=None, alias="background_color"
    )
    text_color_internal: str | None = pydantic.Field(default=None, alias="text_color")
    text_offset_internal: Point | None = pydantic.Field(
        default=None, alias="text_offset"
    )
    text_size_internal: int | None = pydantic.Field(default=None, alias="text_size")
    text_wrap_internal: int | None = pydantic.Field(default=None, alias="text_wrap")
    font_spacing_internal: int | None = pydantic.Field(
        default=None, alias="font_spacing"
    )
    shadow_color_internal: str | None = pydantic.Field(
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


class ScreenConfig(pydantic.BaseModel):
    device_pattern: str = ".*"
    screen_pattern: str = ".*"

    title_key: str | None = None

    style: ScreenStyle | None = None


class Config(pydantic.BaseModel):
    devices: list[DeviceConfig]
    screens: list[ScreenConfig]

    def __getitem__(self, key: str) -> DeviceConfig:
        for device in self.devices:
            if device.name == key:
                return device
        raise KeyError(key)

    def __hasitem__(self, key: str) -> bool:
        for device in self.devices:
            if device.name == key:
                return True
        return False

    def load_frames(self, base: Path) -> None:
        frame_dir = base / "frames"
        for device in self.devices:
            device.frame = Image.open(frame_dir / device.frame_src)

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


def main(
    inputs: Annotated[Path, typer.Argument(exists=True)] = root_dir
    / "fastlane/screenshots",
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
    with config_file.open() as fh:
        config = Config(**yaml.safe_load(fh))
    config.load_frames(Path(__file__).parent)

    string_catalog_file = config_file.parent / "Screenshots.xcstrings"
    assert string_catalog_file.is_file(), "String catalog not found"
    string_catalog = load_string_catalog(string_catalog_file.read_text())

    if not output_folder.exists():
        output_folder.mkdir(parents=True)

    files = []

    if inputs.is_file():
        files.append(inputs)
    else:
        for root, dirs, file in os.walk(inputs):
            root = Path(root)
            for f in file:
                if f.endswith(".png"):
                    files.append(root / f)

    font_file = config_file.parent / "helvetica-bold.ttf"
    if not font_file.exists():
        font_url = "https://github.com/CartoDB/cartodb/raw/master/app/assets/fonts/helvetica-bold.ttf"
        with requests.get(font_url, stream=True) as r:
            r.raise_for_status()
            with font_file.open("wb") as f:
                for chunk in r.iter_content(chunk_size=8192):
                    f.write(chunk)

    if jobs == 1 or len(files) == 1:
        for f in files:
            frame(f, config, output_folder, string_catalog.as_dict(), font_file)
    else:
        with ProcessPoolExecutor(jobs) as executor:
            futures = []
            for f in files:
                if f.stem.endswith("-framed") or "frames" in str(f):
                    continue
                futures.append(
                    executor.submit(
                        frame,
                        f,
                        config,
                        output_folder,
                        string_catalog.as_dict(),
                        font_file,
                    )
                )

            for f in as_completed(futures):
                f.result()

        console.print("Done")


def get_device_name(name: str):
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
    console.print(file)
    device_name = get_device_name(file.stem)
    lang = get_language(file)
    if "-" in lang:
        lang_code, _ = lang.split("-")
    else:
        lang_code = lang
    console.print(" -", device_name, " ", lang)

    try:
        frame_config = config[device_name]
    except KeyError:
        console.print(" - no frame config found")
        return
    console.print(" -", frame_config)

    screen_config, screen_style = config.load_screen_config(device_name, file)
    console.print("Combined screen style:", screen_style)

    screenshot_raw = Image.open(file)
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

    buffer.paste(screenshot, mask=mask)
    buffer.alpha_composite(frame_config.frame)

    # resize to original device screenshot size to comply with AppStore requirements
    output = Image.new("RGBA", screenshot_raw.size)
    output_draw = ImageDraw.Draw(output)

    output_draw.rectangle([0, 0, *buffer.size], fill=screen_style.background_color)

    font = ImageFont.truetype(str(font_file), screen_style.text_size)

    if title_key := screen_config.title_key:
        text_buffer = Image.new("RGBA", screenshot_raw.size)
        text_buffer_draw = ImageDraw.Draw(text_buffer)
        title = titles[title_key].get(lang_code, title_key.upper())
        console.print("Wrap:", screen_style.text_wrap)
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

    console.print("ratio:", aspect_ratio)
    target_size = (screenshot_raw.size[0], int(screenshot_raw.size[0] / aspect_ratio))
    buffer = buffer.resize(target_size)
    console.print("size:", buffer.size, "->", target_size)

    console.print(output.size)

    if frame_config.post_size:
        buffer = buffer.resize(frame_config.post_size.root)

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
    if not locale_dir.exists():
        locale_dir.mkdir(parents=True)
    output_file = locale_dir / f"{file.stem}-framed.png"
    console.print("Saving to", output_file)
    output.save(output_file)


if __name__ == "__main__":
    typer.run(main)
