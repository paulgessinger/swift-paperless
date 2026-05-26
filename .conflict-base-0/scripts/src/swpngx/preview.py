#!/usr/bin/env python3
# /// script
# dependencies = [
#   "rich",
#   "typer",
#   "pydantic>=2",
#   "jinja2",
#   "tomli; python_version < '3.11'",
# ]
# ///

"""
Generate an HTML preview of all metadata and screenshots for each language.
"""

import http.server
import shutil
import socketserver
import tempfile
import threading
import webbrowser
from dataclasses import dataclass
from pathlib import Path
from typing import Annotated

import typer
from jinja2 import Environment, PackageLoader
from rich.console import Console

console = Console()

# Directories to exclude from locale detection
EXCLUDED_DIRS = {"review_information", ".DS_Store"}

# Metadata files to display
METADATA_FILES = [
    ("name.txt", "App Name"),
    ("subtitle.txt", "Subtitle"),
    ("description.txt", "Description"),
    ("keywords.txt", "Keywords"),
    ("release_notes.txt", "Release Notes"),
]


@dataclass
class MetadataItem:
    label: str
    content: str
    is_fallback: bool = False


@dataclass
class Screenshot:
    src: str
    name: str
    device_name: str
    screen_name: str


@dataclass
class LocaleData:
    code: str
    display_name: str
    metadata: list[MetadataItem]
    screenshots: list[Screenshot]


def load_app_title(metadata_dir: Path, default_locale: str = "default") -> str:
    """Load app title from name.txt in the default locale."""
    for locale in [default_locale, "en-US", "en"]:
        name_file = metadata_dir / locale / "name.txt"
        if name_file.exists():
            title = name_file.read_text(encoding="utf-8").strip()
            if title:
                return title
    return "App"


def load_metadata(
    locale_dir: Path, fallback_dir: Path | None = None
) -> list[MetadataItem]:
    """Load all metadata files from a locale directory with fallback support."""
    items = []
    for filename, label in METADATA_FILES:
        filepath = locale_dir / filename
        is_fallback = False

        if filepath.exists():
            content = filepath.read_text(encoding="utf-8").strip()
        elif fallback_dir and (fallback_path := fallback_dir / filename).exists():
            content = fallback_path.read_text(encoding="utf-8").strip()
            is_fallback = True
        else:
            content = ""

        if content:
            items.append(
                MetadataItem(label=label, content=content, is_fallback=is_fallback)
            )
    return items


def is_valid_locale_dir(item: Path) -> bool:
    """Check if a directory is a valid locale directory."""
    if not item.is_dir():
        return False
    if item.name.startswith("."):
        return False
    if item.name in EXCLUDED_DIRS:
        return False
    return True


def get_locales(
    metadata_dir: Path, screenshots_dir: Path, default_locale: str
) -> list[str]:
    """Get all available locales from metadata and screenshots directories."""
    locales = set()

    # From metadata
    if metadata_dir.exists():
        for item in metadata_dir.iterdir():
            if is_valid_locale_dir(item):
                locales.add(item.name)

    # From screenshots
    if screenshots_dir.exists():
        for item in screenshots_dir.iterdir():
            if is_valid_locale_dir(item):
                locales.add(item.name)

    # Remove 'default' if we have en-US - default is the English source template
    # and en-US screenshots represent the actual English locale
    if default_locale in locales and "en-US" in locales:
        locales.discard(default_locale)

    # Sort with 'en-US' first, then alphabetically
    def sort_key(locale: str) -> tuple[int, str]:
        if locale == "en-US":
            return (0, locale)
        if locale.startswith("en"):
            return (1, locale)
        if locale == default_locale:
            return (2, locale)
        return (3, locale)

    return sorted(locales, key=sort_key)


def get_screenshots(
    screenshots_dir: Path, locale: str, embed_images: bool = False
) -> list[Screenshot]:
    """Get all screenshots for a locale."""
    locale_dir = screenshots_dir / locale
    if not locale_dir.exists():
        return []

    screenshots = []
    for path in sorted(locale_dir.glob("*.png")):
        if embed_images:
            import base64

            with open(path, "rb") as f:
                data = base64.b64encode(f.read()).decode("utf-8")
            src = f"data:image/png;base64,{data}"
        else:
            src = f"screenshots/{locale}/{path.name}"

        # Extract device name from filename (e.g., "iPhone_17_Pro_Max-01_documents-framed.png")
        name_parts = path.stem.replace("-framed", "").split("-")
        device_name = name_parts[0].replace("_", " ") if name_parts else ""
        screen_name = name_parts[1] if len(name_parts) > 1 else ""
        screen_name = "_".join(screen_name.split("_")[1:]).replace("_", " ")

        screenshots.append(
            Screenshot(
                src=src,
                name=path.stem,
                device_name=device_name,
                screen_name=screen_name,
            )
        )

    return screenshots


def get_display_name(locale: str) -> str:
    """Get a user-friendly display name for a locale."""
    # Map of locale codes to friendly names
    display_names = {
        "default": "Default (en-US)",
        "en-US": "English (US)",
        "en-GB": "English (UK)",
        "de-DE": "German",
        "fr-FR": "French",
        "it": "Italian",
        "nl-NL": "Dutch",
        "pl": "Polish",
        "da": "Danish",
        "tr": "Turkish",
        "es-ES": "Spanish (Spain)",
        "es-MX": "Spanish (Mexico)",
        "pt-BR": "Portuguese (Brazil)",
        "pt-PT": "Portuguese (Portugal)",
        "ja": "Japanese",
        "ko": "Korean",
        "zh-Hans": "Chinese (Simplified)",
        "zh-Hant": "Chinese (Traditional)",
        "ru": "Russian",
        "ar-SA": "Arabic",
        "he": "Hebrew",
        "th": "Thai",
        "vi": "Vietnamese",
        "id": "Indonesian",
        "ms": "Malay",
        "sv": "Swedish",
        "no": "Norwegian",
        "fi": "Finnish",
        "uk": "Ukrainian",
        "cs": "Czech",
        "sk": "Slovak",
        "hu": "Hungarian",
        "ro": "Romanian",
        "hr": "Croatian",
        "el": "Greek",
        "ca": "Catalan",
        "hi": "Hindi",
    }
    return display_names.get(locale, locale)


def generate_html(
    metadata_dir: Path,
    screenshots_dir: Path,
    output_dir: Path,
    default_locale: str = "default",
    embed_images: bool = False,
) -> Path:
    """Generate the HTML preview file."""
    locales = get_locales(metadata_dir, screenshots_dir, default_locale)

    if not locales:
        console.log("[red]No locales found in metadata or screenshots directories")
        raise typer.Exit(1)

    # Load app title
    app_title = load_app_title(metadata_dir, default_locale)

    # Copy screenshots to output directory if not embedding
    if not embed_images and screenshots_dir.exists():
        output_screenshots = output_dir / "screenshots"
        if output_screenshots.exists():
            shutil.rmtree(output_screenshots)
        shutil.copytree(screenshots_dir, output_screenshots)

    # Build locale data
    fallback_metadata_dir = metadata_dir / default_locale
    locale_data_list: list[LocaleData] = []
    for locale in locales:
        locale_metadata_dir = metadata_dir / locale
        # For en-US without its own metadata dir, use default without marking as fallback
        # (since default is English, it's not "untranslated")
        if locale == "en-US" and not locale_metadata_dir.exists():
            locale_metadata_dir = fallback_metadata_dir
            fallback = None
        elif locale == default_locale:
            fallback = None
        else:
            fallback = fallback_metadata_dir
        metadata = load_metadata(locale_metadata_dir, fallback)
        screenshots = get_screenshots(screenshots_dir, locale, embed_images)

        locale_data_list.append(
            LocaleData(
                code=locale,
                display_name=get_display_name(locale),
                metadata=metadata,
                screenshots=screenshots,
            )
        )

    # Render template
    env = Environment(
        loader=PackageLoader("swpngx", "templates"),
        autoescape=True,
    )
    template = env.get_template("preview.html")
    html_content = template.render(
        app_title=app_title,
        locales=locale_data_list,
    )

    output_file = output_dir / "index.html"
    output_file.write_text(html_content, encoding="utf-8")
    return output_file


class QuietHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    """HTTP request handler that suppresses log output."""

    def log_message(self, format, *args):
        pass  # Suppress logging


def serve_directory(directory: Path, port: int) -> socketserver.TCPServer:
    """Start an HTTP server serving the given directory."""
    handler = lambda *args, **kwargs: QuietHTTPRequestHandler(
        *args, directory=str(directory), **kwargs
    )
    server = socketserver.TCPServer(("", port), handler)
    return server


def main(
    metadata_dir: Annotated[
        Path,
        typer.Option(
            "--metadata-dir",
            "-m",
            help="Path to fastlane metadata directory",
        ),
    ] = Path("fastlane/metadata"),
    screenshots_dir: Annotated[
        Path,
        typer.Option(
            "--screenshots-dir",
            "-s",
            help="Path to framed screenshots directory",
        ),
    ] = Path("fastlane/screenshots/framed"),
    port: Annotated[
        int,
        typer.Option(
            "--port",
            "-p",
            help="Port to serve on",
        ),
    ] = 8080,
    open_browser: Annotated[
        bool,
        typer.Option(
            "--open",
            "-o",
            help="Open in default browser",
        ),
    ] = False,
    output_dir: Annotated[
        Path | None,
        typer.Option(
            "--output",
            help="Output directory (uses temp dir if not specified)",
        ),
    ] = None,
    no_serve: Annotated[
        bool,
        typer.Option(
            "--no-serve",
            help="Generate HTML without starting server",
        ),
    ] = False,
) -> None:
    """Generate and serve an HTML preview of metadata and screenshots."""
    # Resolve paths
    metadata_dir = metadata_dir.resolve()
    screenshots_dir = screenshots_dir.resolve()

    if not metadata_dir.exists() and not screenshots_dir.exists():
        console.log(
            f"[red]Neither metadata dir ({metadata_dir}) nor screenshots dir ({screenshots_dir}) exists"
        )
        raise typer.Exit(1)

    # Create output directory
    if output_dir:
        output_dir = output_dir.resolve()
        output_dir.mkdir(parents=True, exist_ok=True)
        temp_dir = None
    else:
        temp_dir = tempfile.mkdtemp(prefix="swpngx-preview-")
        output_dir = Path(temp_dir)

    console.log("[blue]Generating preview...")
    console.log(f"  Metadata: {metadata_dir}")
    console.log(f"  Screenshots: {screenshots_dir}")
    console.log(f"  Output: {output_dir}")

    # Generate HTML
    html_file = generate_html(metadata_dir, screenshots_dir, output_dir)
    console.log(f"[green]Generated: {html_file}")

    if no_serve:
        console.log(f"[green]Preview generated at: {output_dir}")
        return

    # Start server
    url = f"http://localhost:{port}"
    console.log(f"[green]Starting server at {url}")

    server = serve_directory(output_dir, port)
    server_thread = threading.Thread(target=server.serve_forever)
    server_thread.daemon = True
    server_thread.start()

    if open_browser:
        console.log("[blue]Opening in browser...")
        webbrowser.open(url)

    console.log("[yellow]Press Ctrl+C to stop the server")

    try:
        server_thread.join()
    except KeyboardInterrupt:
        console.log("\n[yellow]Shutting down server...")
        server.shutdown()

    # Clean up temp directory
    if temp_dir:
        shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == "__main__":
    typer.run(main)
