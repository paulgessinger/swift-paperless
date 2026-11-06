#!/usr/bin/env python3
"""Publish the app's What's New decks from release note front matter.

A release note opts in with a `whats_new` key in its YAML front matter:

    ---
    whats_new:
      pages:
        - title: What's new in 1.11
          blocks:
            - type: card
              icon: tag
              title: Nested tags
              text: Support for hierarchical tags.
    ---

`build` writes one `<version>.json` per opted-in note, which the app fetches
from `https://swift-paperless.app/whats_new/<version>.json`. The version comes
from the file name, so a deck can't be published under the wrong release.
"""

# /// script
# dependencies = [
#   "pyyaml",
#   "typer",
# ]
# ///

import json
import re
import time
from urllib.parse import urlparse
from pathlib import Path
from typing import Annotated, Any

import typer
import yaml

app = typer.Typer(add_completion=False)


@app.callback()
def main() -> None:
    """Publish What's New decks."""


NOTE_NAME = re.compile(r"^v(\d+\.\d+\.\d+)\.md$")
BLOCK_TYPES = {"card", "tip", "telemetry"}
# Must match the tints `IconTile` maps in WhatsNewDeckView.swift.
TINTS = {"blue", "indigo", "orange", "pink", "purple", "red", "teal"}
CARD_REQUIRED = ("icon", "title", "text")
MARKDOWN_IMAGE = re.compile(r"!\[[^\]]*\]\(\s*<?([^)\s>]+)")
CARD_OPTIONAL = ("tint", "detail", "image")
CARD_FLAGS = ("image_shadow",)


class DeckError(Exception):
    pass


def front_matter(text: str) -> dict[str, Any]:
    if not text.startswith("---\n"):
        return {}
    end = text.find("\n---\n", 4)
    if end == -1:
        raise DeckError("front matter is not closed with '---'")
    data = yaml.safe_load(text[4:end]) or {}
    if not isinstance(data, dict):
        raise DeckError("front matter is not a mapping")
    return data


def _string(value: Any, where: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise DeckError(f"{where} must be a non-empty string")
    return value


def _block(raw: Any, where: str, notes: Path) -> dict[str, Any]:
    if not isinstance(raw, dict):
        raise DeckError(f"{where} must be a mapping")
    kind = raw.get("type")
    if kind not in BLOCK_TYPES:
        raise DeckError(f"{where}.type must be one of {sorted(BLOCK_TYPES)}")
    unknown = set(raw) - {"type", *CARD_REQUIRED, *CARD_OPTIONAL, *CARD_FLAGS}
    if unknown:
        raise DeckError(f"{where} has unknown keys {sorted(unknown)}")

    block: dict[str, Any] = {"type": kind}
    for key in CARD_REQUIRED:
        block[key] = _string(raw.get(key), f"{where}.{key}")
    for key in CARD_OPTIONAL:
        if key in raw:
            block[key] = _string(raw[key], f"{where}.{key}")
    if "tint" in block and block["tint"] not in TINTS:
        raise DeckError(f"{where}.tint must be one of {sorted(TINTS)}")
    if "image" in block:
        _check_image(block["image"], f"{where}.image", notes)
    for image in MARKDOWN_IMAGE.findall(block.get("detail", "")):
        _check_image(image, f"{where}.detail image", notes)
    for key in CARD_FLAGS:
        if key in raw:
            if not isinstance(raw[key], bool):
                raise DeckError(f"{where}.{key} must be true or false")
            block[key] = raw[key]
    if "image_shadow" in block and "image" not in block:
        raise DeckError(f"{where}.image_shadow needs an image")
    return block


def _check_image(image: str, where: str, notes: Path) -> None:
    """A relative image resolves against the release notes directory, as on the site."""
    url = urlparse(image)
    if url.scheme:
        if url.scheme != "https":
            raise DeckError(f"{where} must be a relative path or an https URL")
        return
    path = (notes / url.path).resolve()
    if not path.is_file():
        raise DeckError(f"{where} {image!r} does not exist at {path}")


def deck(raw: Any, version: str, notes: Path) -> dict[str, Any]:
    if not isinstance(raw, dict) or not isinstance(raw.get("pages"), list):
        raise DeckError("whats_new.pages must be a list")
    if not raw["pages"]:
        raise DeckError("whats_new.pages must not be empty")

    pages = []
    for index, page in enumerate(raw["pages"]):
        where = f"whats_new.pages[{index}]"
        if not isinstance(page, dict):
            raise DeckError(f"{where} must be a mapping")
        blocks = page.get("blocks")
        if not isinstance(blocks, list) or not blocks:
            raise DeckError(f"{where}.blocks must be a non-empty list")
        out: dict[str, Any] = {"title": _string(page.get("title"), f"{where}.title")}
        if "subtitle" in page:
            out["subtitle"] = _string(page["subtitle"], f"{where}.subtitle")
        out["blocks"] = [
            _block(block, f"{where}.blocks[{i}]", notes)
            for i, block in enumerate(blocks)
        ]
        pages.append(out)

    return {"version": version, "pages": pages}


def decks(notes: Path) -> dict[str, dict[str, Any]]:
    """Every published deck by version; raises on the first invalid one."""
    found = {}
    for path in sorted(notes.glob("v*.md")):
        match = NOTE_NAME.match(path.name)
        if not match:
            continue
        try:
            raw = front_matter(path.read_text()).get("whats_new")
            if raw is not None:
                found[match[1]] = deck(raw, match[1], notes)
        except (DeckError, yaml.YAMLError) as error:
            raise DeckError(f"{path}: {error}") from error
    return found


def write_decks(notes: Path, output: Path) -> int:
    """Writes every deck, or raises before writing any if one is invalid."""
    found = decks(notes)
    output.mkdir(parents=True, exist_ok=True)
    for version, content in found.items():
        file = output / f"{version}.json"
        text = json.dumps(content, ensure_ascii=False, indent=2) + "\n"
        # Leaves unchanged decks alone, so a docs server doesn't rebuild.
        if not file.is_file() or file.read_text() != text:
            file.write_text(text)
    return len(found)


def snapshot(root: Path, exclude: Path | None = None) -> dict[Path, float]:
    """Modification times of every file under `root`, outside `exclude`."""
    return {
        path: path.stat().st_mtime
        for path in root.rglob("*")
        if path.is_file() and not (exclude and path.is_relative_to(exclude))
    }


@app.command()
def build(
    notes: Annotated[Path, typer.Argument(help="Directory of vX.Y.Z.md release notes")],
    output: Annotated[
        Path, typer.Argument(help="Directory to write <version>.json into")
    ],
) -> None:
    """Write a deck JSON file for each release note that has one."""
    try:
        count = write_decks(notes, output)
    except DeckError as error:
        typer.echo(f"error: {error}", err=True)
        raise typer.Exit(1)
    typer.echo(f"Wrote {count} What's New deck(s) to {output}")


@app.command()
def watch(
    notes: Annotated[Path, typer.Argument(help="Directory of vX.Y.Z.md release notes")],
    output: Annotated[
        Path, typer.Argument(help="Directory to write <version>.json into")
    ],
    interval: Annotated[
        float, typer.Option(help="Seconds between checks for changes")
    ] = 0.5,
) -> None:
    """Rebuild the decks whenever anything next to the release notes changes.

    Watches the notes' parent directory too, so a changed image counts. An
    invalid deck is reported and the previous JSON stays in place.
    """
    root = notes.resolve().parent
    seen: dict[Path, float] | None = None
    typer.echo(f"Watching {root} (Ctrl-C to stop)")
    try:
        while True:
            current = snapshot(root, exclude=output.resolve())
            if current != seen:
                seen = current
                stamp = time.strftime("%H:%M:%S")
                try:
                    count = write_decks(notes, output)
                    typer.echo(f"{stamp} wrote {count} deck(s) to {output}")
                except DeckError as error:
                    typer.echo(f"{stamp} error: {error}", err=True)
            time.sleep(interval)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    app()
