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
CARD_OPTIONAL = ("tint", "detail")


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


def _block(raw: Any, where: str) -> dict[str, str]:
    if not isinstance(raw, dict):
        raise DeckError(f"{where} must be a mapping")
    kind = raw.get("type")
    if kind not in BLOCK_TYPES:
        raise DeckError(f"{where}.type must be one of {sorted(BLOCK_TYPES)}")
    unknown = set(raw) - {"type", *CARD_REQUIRED, *CARD_OPTIONAL}
    if unknown:
        raise DeckError(f"{where} has unknown keys {sorted(unknown)}")

    block = {"type": kind}
    for key in CARD_REQUIRED:
        block[key] = _string(raw.get(key), f"{where}.{key}")
    for key in CARD_OPTIONAL:
        if key in raw:
            block[key] = _string(raw[key], f"{where}.{key}")
    if "tint" in block and block["tint"] not in TINTS:
        raise DeckError(f"{where}.tint must be one of {sorted(TINTS)}")
    return block


def deck(raw: Any, version: str) -> dict[str, Any]:
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
            _block(block, f"{where}.blocks[{i}]") for i, block in enumerate(blocks)
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
                found[match[1]] = deck(raw, match[1])
        except (DeckError, yaml.YAMLError) as error:
            raise DeckError(f"{path}: {error}") from error
    return found


@app.command()
def build(
    notes: Annotated[Path, typer.Argument(help="Directory of vX.Y.Z.md release notes")],
    output: Annotated[
        Path, typer.Argument(help="Directory to write <version>.json into")
    ],
) -> None:
    """Write a deck JSON file for each release note that has one."""
    try:
        found = decks(notes)
    except DeckError as error:
        typer.echo(f"error: {error}", err=True)
        raise typer.Exit(1)

    output.mkdir(parents=True, exist_ok=True)
    for version, content in found.items():
        (output / f"{version}.json").write_text(
            json.dumps(content, ensure_ascii=False, indent=2) + "\n"
        )
    typer.echo(f"Wrote {len(found)} What's New deck(s) to {output}")


if __name__ == "__main__":
    app()
