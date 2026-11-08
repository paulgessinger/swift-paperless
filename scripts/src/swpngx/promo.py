"""Render the promo scenes (HTML/SVG with CSS animations) to screenshots and videos.

Each frame is produced by pausing every animation and seeking it to the exact
frame time, so output is deterministic regardless of machine speed. Paths are
relative to the repository root, where `swpngx` runs.
"""

from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Annotated
from urllib.parse import urlencode

import typer
from PIL import Image
from playwright.sync_api import Browser, Page, sync_playwright
from rich.console import Console

from swpngx.capture import load_capture_config
from swpngx.frame import normalize_output_locale

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover
    import tomli as tomllib

app = typer.Typer(no_args_is_help=True, help="Promo-style screenshots and videos")
console = Console()

PROMO_DIR = Path("store/promo")
SCENES_DIR = PROMO_DIR / "scenes"
ASSETS_DIR = PROMO_DIR / "assets"
HEADLINES = PROMO_DIR / "headlines.toml"

# Phone screens cut out of the framed panorama: (slide index, name).
# Each slide is 1360 px wide; the box drops the bezel and keeps the screen.
PANORAMA_SCREENS = [(0, "list"), (1, "filter"), (2, "detail")]
PANORAMA_SCREEN_BOX = (94, 650, 1266, 2868)
# The PDF page inside the detail screen, lifted out as paper in the promo.
DETAIL_PAGE_BOX = (215, 365, 955, 1335)

# Capture prefix (screenshot_devices.toml id) and scene layout per device.
SCREENSHOT_DEVICES = {
    "iPhone_18_Pro_Max": "iphone",
    "iPad_Pro_13_M5": "ipad",
    "iPhone_Duo_Inner": "duo_inner",
    "iPhone_Duo_Outer": "duo_outer",
}

CanvasOption = Annotated[
    str | None,
    typer.Option(help="Canvas WxH for scenes that adapt to their size, e.g. 5244x2950"),
]


def _open(page: Page, scene: Path, query: dict[str, str] | None = None) -> dict:
    url = scene.resolve().as_uri()
    if query:
        url += "?" + urlencode(query)
    page.goto(url)
    page.wait_for_load_state("networkidle")
    page.evaluate("document.fonts.ready")
    return page.evaluate("window.__scene")


def _canvas_query(canvas: str | None) -> dict[str, str]:
    if not canvas:
        return {}
    w, h = canvas.split("x")
    return {"w": w, "h": h}


def _seek(page: Page, seconds: float) -> None:
    page.evaluate(
        """t => { for (const a of document.getAnimations()) { a.pause(); a.currentTime = t; } }""",
        seconds * 1000,
    )


def _cut_screens(screens: dict[str, Image.Image], target: Path) -> None:
    """Write the video's phone screens (and the lifted PDF page) into target."""
    target.mkdir(parents=True, exist_ok=True)
    for name, screen in screens.items():
        screen.save(target / f"screen_{name}.png")
        if name == "detail":
            screen.crop(DETAIL_PAGE_BOX).save(target / "preview_page.png")


@app.command()
def prepare(
    panorama: Annotated[Path, typer.Option(help="Framed screenshot panorama")] = Path(
        "panorama.png"
    ),
) -> None:
    """Cut the phone screens the video scenes use into store/promo/assets/."""
    image = Image.open(panorama).convert("RGB")
    left, top, right, bottom = PANORAMA_SCREEN_BOX
    screens = {
        name: image.crop((index * 1360 + left, top, index * 1360 + right, bottom))
        for index, name in PANORAMA_SCREENS
    }
    _cut_screens(screens, ASSETS_DIR)
    console.log(f"Wrote assets to {ASSETS_DIR}")


def _render_video(
    browser: Browser,
    scene: Path,
    query: dict[str, str],
    output: Path,
    size: str,
    fps: int,
) -> None:
    out_w, out_h = (int(v) for v in size.split("x"))
    probe = browser.new_page()
    meta = _open(probe, scene, query)
    probe.close()

    # Render at a scale where the canvas covers the output; ffmpeg crops the rest.
    scale = max(out_w / meta["width"], out_h / meta["height"])
    page = browser.new_page(
        viewport={"width": meta["width"], "height": meta["height"]},
        device_scale_factor=scale,
    )
    _open(page, scene, query)

    output.parent.mkdir(parents=True, exist_ok=True)
    frames = round(meta["duration"] * fps)
    # fmt: off
    ffmpeg = subprocess.Popen(
        [
            "ffmpeg", "-y", "-loglevel", "error",
            "-f", "image2pipe", "-framerate", str(fps), "-i", "-",
            "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000",
            "-vf", f"crop={out_w}:{out_h},format=yuv420p",
            "-c:v", "libx264", "-profile:v", "high", "-crf", "16", "-r", str(fps),
            "-c:a", "aac", "-b:a", "256k", "-shortest",
            "-movflags", "+faststart",
            str(output),
        ],
        stdin=subprocess.PIPE,
    )
    # fmt: on
    assert ffmpeg.stdin
    for i in range(frames):
        _seek(page, i / fps)
        ffmpeg.stdin.write(page.screenshot(type="png"))
        if i % fps == 0:
            console.print(f"\r{output}: frame {i}/{frames}", end="")
    ffmpeg.stdin.close()
    if ffmpeg.wait() != 0:
        raise RuntimeError(f"ffmpeg failed for {output}")
    page.close()
    console.print()
    console.log(f"Wrote {output}")


@app.command()
def video(
    scene: Annotated[Path, typer.Argument(help="Scene HTML file")],
    output: Annotated[Path, typer.Option("-o", "--output")] = Path("promo.mp4"),
    size: Annotated[
        str, typer.Option(help='Output WxH, e.g. 886x1920 (6.9" App Preview)')
    ] = "886x1920",
    fps: Annotated[int, typer.Option()] = 30,
    canvas: CanvasOption = None,
) -> None:
    """Render a scene's full timeline to an H.264 MP4 with a silent stereo track."""
    with sync_playwright() as p:
        browser = p.chromium.launch()
        _render_video(browser, scene, _canvas_query(canvas), output, size, fps)
        browser.close()


@app.command()
def still(
    scene: Annotated[Path, typer.Argument(help="Scene HTML file")],
    at: Annotated[list[float], typer.Option("--at", help="Time(s) in seconds")],
    output_dir: Annotated[Path, typer.Option("-o", "--output-dir")] = Path("."),
    canvas: CanvasOption = None,
) -> None:
    """Render full-resolution PNG stills of a scene at the given times."""
    output_dir.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page()
        meta = _open(page, scene, _canvas_query(canvas))
        page.set_viewport_size({"width": meta["width"], "height": meta["height"]})
        for t in at:
            _seek(page, t)
            suffix = f"_{canvas}" if canvas else ""
            path = output_dir / f"{scene.stem}{suffix}_{t:05.2f}s.png"
            page.screenshot(path=path)
            # App Store Connect rejects images with an alpha channel.
            with Image.open(path) as image:
                image.convert("RGB").save(path)
            console.log(f"Wrote {path}")
        browser.close()


def load_headlines(path: Path) -> dict[str, dict]:
    return tomllib.loads(path.read_text(encoding="utf-8"))


def _check_locales(selected: list[str], headlines: dict[str, dict]) -> None:
    missing = [locale for locale in selected if locale not in headlines]
    if missing:
        console.log(f"[red]No headlines in {HEADLINES} for: {', '.join(missing)}")
        raise typer.Exit(1)


@app.command()
def screenshots(
    locales: Annotated[
        list[str] | None,
        typer.Option(
            "--locale", help="Capture locale(s); default: all in screenshots.toml"
        ),
    ] = None,
    config: Annotated[
        Path, typer.Option("--config", "-c", help="Screenshot capture config")
    ] = Path("screenshots.toml"),
    output_dir: Annotated[
        Path, typer.Option("-o", "--output-dir", help="Where `swpngx deliver` reads")
    ] = Path("store/screenshots/framed"),
) -> None:
    """Frame `swpngx capture` screenshots in the promo style.

    Reads store/screenshots/<locale>/<device>-NN_<step>.png and writes
    <output-dir>/<App Store locale>/<same name>-framed.png without alpha.
    """
    capture_config = load_capture_config(config)
    headlines = load_headlines(HEADLINES)
    scene = SCENES_DIR / "screenshot.html"
    selected = locales or capture_config.locales
    _check_locales(selected, headlines)

    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page()
        for locale in selected:
            captures = capture_config.output_dir / locale
            target = output_dir / normalize_output_locale(locale)
            target.mkdir(parents=True, exist_ok=True)
            found = 0
            for prefix, layout in SCREENSHOT_DEVICES.items():
                for capture in sorted(captures.glob(f"{prefix}-*.png")):
                    slide = int(capture.stem.split("-")[1][:2])
                    with Image.open(capture) as screen:
                        ratio = screen.height / screen.width
                    meta = _open(
                        page,
                        scene,
                        {
                            "device": layout,
                            "slide": str(slide),
                            "ar": f"{ratio:.5f}",
                            "img": capture.resolve().as_uri(),
                            **headlines[locale]["slides"][slide - 1],
                        },
                    )
                    page.set_viewport_size(
                        {"width": meta["width"], "height": meta["height"]}
                    )
                    path = target / f"{capture.stem}-framed.png"
                    page.screenshot(path=path)
                    # App Store Connect rejects screenshots with an alpha channel.
                    with Image.open(path) as framed:
                        framed.convert("RGB").save(path)
                    found += 1
            console.log(f"{locale}: framed {found} screenshots into {target}")
        browser.close()


# Captures (screenshots.toml steps) the preview video shows, by scene screen.
PREVIEW_DEVICE = "iPhone_18_Pro_Max"
PREVIEW_SCREENS = {"list": "01", "filter": "02", "detail": "03"}
# The scene's phone screen: 1172 px wide, cut off below 2218 px.
PREVIEW_SCREEN_SIZE = (1172, 2218)


@app.command()
def previews(
    locales: Annotated[
        list[str] | None,
        typer.Option(
            "--locale", help="Capture locale(s); default: all in screenshots.toml"
        ),
    ] = None,
    config: Annotated[
        Path, typer.Option("--config", "-c", help="Screenshot capture config")
    ] = Path("screenshots.toml"),
    output_dir: Annotated[
        Path, typer.Option("-o", "--output-dir", help="Where `swpngx deliver` reads")
    ] = Path("store/previews"),
    size: Annotated[str, typer.Option(help="Output WxH")] = "886x1920",
    fps: Annotated[int, typer.Option()] = 30,
) -> None:
    """Render the "Paper to pixels" app preview for each locale.

    Uses that locale's iPhone captures and headlines, and writes
    <output-dir>/<App Store locale>/paper_to_pixels.mp4.
    """
    capture_config = load_capture_config(config)
    headlines = load_headlines(HEADLINES)
    scene = SCENES_DIR / "paper_to_pixels.html"
    selected = locales or capture_config.locales
    _check_locales(selected, headlines)

    with sync_playwright() as p:
        browser = p.chromium.launch()
        for locale in selected:
            captures = capture_config.output_dir / locale
            screens = {}
            for name, step in PREVIEW_SCREENS.items():
                matches = sorted(captures.glob(f"{PREVIEW_DEVICE}-{step}_*.png"))
                if not matches:
                    console.log(f"[red]{locale}: no {PREVIEW_DEVICE}-{step} capture")
                    raise typer.Exit(1)
                with Image.open(matches[0]) as capture:
                    width, height = PREVIEW_SCREEN_SIZE
                    scaled = capture.convert("RGB").resize(
                        (width, round(capture.height * width / capture.width)),
                        Image.Resampling.LANCZOS,
                    )
                    screens[name] = scaled.crop((0, 0, width, height))
            assets = ASSETS_DIR / locale
            _cut_screens(screens, assets)

            query = {"assets": assets.resolve().as_uri()}
            for index, slide in enumerate(headlines[locale]["slides"][:3], start=1):
                query |= {f"s{index}_{key}": value for key, value in slide.items()}
            query["end_sub"] = headlines[locale]["video_end"]

            output = (
                output_dir / normalize_output_locale(locale) / "paper_to_pixels.mp4"
            )
            _render_video(browser, scene, query, output, size, fps)
        browser.close()
