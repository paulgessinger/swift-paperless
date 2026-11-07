# /// script
# requires-python = ">=3.12"
# dependencies = ["playwright>=1.55", "typer>=0.15", "pillow>=11"]
# ///
"""Render an animated promo scene (HTML/SVG with CSS animations) to video or stills.

Each frame is produced by pausing every animation and seeking it to the exact
frame time, so output is deterministic regardless of machine speed.
"""

import subprocess
from pathlib import Path
from typing import Annotated

import typer
from PIL import Image
from playwright.sync_api import Page, sync_playwright

app = typer.Typer(add_completion=False)

PROMO_DIR = Path(__file__).parent
REPO_ROOT = PROMO_DIR.parents[1]
ASSETS_DIR = PROMO_DIR / "assets"

# Phone screens cut out of the framed panorama: (slide index, name).
# Each slide is 1360 px wide; the box drops the bezel and keeps the screen.
PANORAMA_SCREENS = [(0, "list"), (1, "filter"), (2, "detail")]
PANORAMA_SCREEN_BOX = (94, 650, 1266, 2868)
# The PDF page inside the detail screen, lifted out as paper in the promo.
DETAIL_PAGE_BOX = (215, 365, 955, 1335)


CanvasOption = Annotated[
    str | None,
    typer.Option(help="Canvas WxH for scenes that adapt to their size, e.g. 5244x2950"),
]


def _open(page: Page, scene: Path, canvas: str | None = None) -> dict:
    url = scene.resolve().as_uri()
    if canvas:
        w, h = canvas.split("x")
        url += f"?w={w}&h={h}"
    page.goto(url)
    page.wait_for_load_state("networkidle")
    page.evaluate("document.fonts.ready")
    return page.evaluate("window.__scene")


def _seek(page: Page, seconds: float) -> None:
    page.evaluate(
        """t => { for (const a of document.getAnimations()) { a.pause(); a.currentTime = t; } }""",
        seconds * 1000,
    )


@app.command()
def prepare(
    panorama: Annotated[
        Path, typer.Option(help="Framed screenshot panorama")
    ] = REPO_ROOT
    / "panorama.png",
) -> None:
    """Cut the phone screens the scenes use into assets/ (gitignored)."""
    ASSETS_DIR.mkdir(exist_ok=True)
    image = Image.open(panorama).convert("RGB")
    left, top, right, bottom = PANORAMA_SCREEN_BOX
    for index, name in PANORAMA_SCREENS:
        offset = index * 1360
        screen = image.crop((offset + left, top, offset + right, bottom))
        screen.save(ASSETS_DIR / f"screen_{name}.png")
        if name == "detail":
            screen.crop(DETAIL_PAGE_BOX).save(ASSETS_DIR / "preview_page.png")
    typer.echo(f"wrote assets to {ASSETS_DIR}")


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
    """Render the full timeline to an H.264 MP4 with a silent stereo track."""
    out_w, out_h = (int(v) for v in size.split("x"))
    with sync_playwright() as p:
        browser = p.chromium.launch()
        probe = browser.new_page()
        meta = _open(probe, scene, canvas)
        probe.close()

        # Render at a scale where the canvas covers the output; ffmpeg crops the rest.
        scale = max(out_w / meta["width"], out_h / meta["height"])
        page = browser.new_page(
            viewport={"width": meta["width"], "height": meta["height"]},
            device_scale_factor=scale,
        )
        _open(page, scene, canvas)

        frames = round(meta["duration"] * fps)
        ffmpeg = subprocess.Popen(
            [
                "ffmpeg",
                "-y",
                "-loglevel",
                "error",
                "-f",
                "image2pipe",
                "-framerate",
                str(fps),
                "-i",
                "-",
                "-f",
                "lavfi",
                "-i",
                "anullsrc=channel_layout=stereo:sample_rate=48000",
                "-vf",
                f"crop={out_w}:{out_h},format=yuv420p",
                "-c:v",
                "libx264",
                "-profile:v",
                "high",
                "-crf",
                "16",
                "-r",
                str(fps),
                "-c:a",
                "aac",
                "-b:a",
                "256k",
                "-shortest",
                "-movflags",
                "+faststart",
                str(output),
            ],
            stdin=subprocess.PIPE,
        )
        assert ffmpeg.stdin
        for i in range(frames):
            _seek(page, i / fps)
            ffmpeg.stdin.write(page.screenshot(type="png"))
            if i % fps == 0:
                typer.echo(f"\rframe {i}/{frames}", nl=False)
        ffmpeg.stdin.close()
        ffmpeg.wait()
        browser.close()
    typer.echo(f"\nwrote {output}")


@app.command()
def still(
    scene: Annotated[Path, typer.Argument(help="Scene HTML file")],
    at: Annotated[list[float], typer.Option("--at", help="Time(s) in seconds")],
    output_dir: Annotated[Path, typer.Option("-o", "--output-dir")] = Path("."),
    canvas: CanvasOption = None,
) -> None:
    """Render full-resolution PNG stills at the given times (e.g. App Store screenshots)."""
    output_dir.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page()
        meta = _open(page, scene, canvas)
        page.set_viewport_size({"width": meta["width"], "height": meta["height"]})
        for t in at:
            _seek(page, t)
            suffix = f"_{canvas}" if canvas else ""
            path = output_dir / f"{scene.stem}{suffix}_{t:05.2f}s.png"
            page.screenshot(path=path)
            typer.echo(f"wrote {path}")
        browser.close()


# Capture prefix (swpngx device id) and scene layout for each framed device.
SCREENSHOT_DEVICES = {"iPhone_18_Pro_Max": "iphone", "iPad_Pro_13_M5": "ipad"}


@app.command()
def screenshots(
    captures: Annotated[
        Path, typer.Option(help="Folder of `swpngx capture` PNGs for one locale")
    ] = ASSETS_DIR
    / "captures"
    / "en-US",
    output_dir: Annotated[Path, typer.Option("-o", "--output-dir")] = PROMO_DIR
    / "out"
    / "screenshots",
) -> None:
    """Frame captured screens in the promo style at App Store screenshot sizes."""
    output_dir.mkdir(parents=True, exist_ok=True)
    scene = PROMO_DIR / "scenes" / "screenshot.html"
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page()
        for prefix, layout in SCREENSHOT_DEVICES.items():
            for capture in sorted(captures.glob(f"{prefix}-*.png")):
                slide = int(capture.stem.split("-")[1][:2])
                with Image.open(capture) as screen:
                    ratio = screen.height / screen.width
                page.goto(
                    f"{scene.resolve().as_uri()}?device={layout}&slide={slide}"
                    f"&ar={ratio:.5f}&img={capture.resolve().as_uri()}"
                )
                page.wait_for_load_state("networkidle")
                meta = page.evaluate("window.__scene")
                page.set_viewport_size(
                    {"width": meta["width"], "height": meta["height"]}
                )
                path = output_dir / capture.name
                page.screenshot(path=path)
                # App Store Connect rejects screenshots with an alpha channel.
                with Image.open(path) as framed:
                    framed.convert("RGB").save(path)
                typer.echo(f"wrote {path}")
        browser.close()


if __name__ == "__main__":
    app()
