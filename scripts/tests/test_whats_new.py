"""Tests for publishing What's New decks from release note front matter."""

import json
from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import whats_new

NOTE = """---
whats_new:
  pages:
    - title: What's new in 1.11
      subtitle: Tags
      blocks:
        - type: card
          icon: tag
          tint: teal
          title: Nested tags
          text: Support for hierarchical tags.
          detail: |
            Tags can now have **parents**.
        - type: tip
          icon: heart.fill
          tint: red
          title: Leave a tip
          text: Help keep the app going.
---

# v1.11.0

## Features
"""


def write(directory: Path, name: str, text: str) -> None:
    (directory / name).write_text(text)


def test_builds_deck_named_after_the_file(tmp_path: Path) -> None:
    notes, output = tmp_path / "notes", tmp_path / "site"
    notes.mkdir()
    write(notes, "v1.11.0.md", NOTE)
    write(notes, "v1.10.0.md", "# v1.10.0\n")

    whats_new.build(notes, output)

    assert [p.name for p in output.iterdir()] == ["1.11.0.json"]
    deck = json.loads((output / "1.11.0.json").read_text())
    assert deck["version"] == "1.11.0"
    page = deck["pages"][0]
    assert page["subtitle"] == "Tags"
    assert page["blocks"][0] == {
        "type": "card",
        "icon": "tag",
        "title": "Nested tags",
        "text": "Support for hierarchical tags.",
        "tint": "teal",
        "detail": "Tags can now have **parents**.\n",
    }
    assert page["blocks"][1]["type"] == "tip"


def test_notes_without_front_matter_publish_nothing(tmp_path: Path) -> None:
    write(tmp_path, "v1.10.0.md", "# v1.10.0\n\n---\n\nNot front matter.\n")
    write(tmp_path, "v1.9.0.md", "---\ntitle: Something else\n---\n# v1.9.0\n")
    assert whats_new.decks(tmp_path) == {}


@pytest.mark.parametrize(
    "change, message",
    [
        (("type: card", "type: banner"), "type must be one of"),
        (("          icon: tag\n", ""), "icon must be a non-empty string"),
        (("tint: teal", "tint: green"), "tint must be one of"),
        (("detail: |", "details: |"), "unknown keys ['details']"),
        (
            ("      blocks:", "      blocks: []\n      unused:"),
            "blocks must be a non-empty list",
        ),
    ],
)
def test_rejects_invalid_decks_with_their_location(
    tmp_path: Path, change: tuple[str, str], message: str
) -> None:
    old, new = change
    write(tmp_path, "v1.11.0.md", NOTE.replace(old, new, 1))
    with pytest.raises(whats_new.DeckError) as error:
        whats_new.decks(tmp_path)
    assert "v1.11.0.md" in str(error.value)
    assert message in str(error.value)


def test_unclosed_front_matter_is_an_error(tmp_path: Path) -> None:
    write(tmp_path, "v1.11.0.md", "---\nwhats_new:\n  pages: []\n# v1.11.0\n")
    with pytest.raises(whats_new.DeckError, match="not closed"):
        whats_new.decks(tmp_path)


def with_image(image: str) -> str:
    return NOTE.replace(
        "          tint: teal\n", f"          tint: teal\n          image: {image}\n", 1
    )


def test_relative_image_must_exist_next_to_the_notes(tmp_path: Path) -> None:
    notes = tmp_path / "release_notes"
    notes.mkdir()
    (tmp_path / "assets").mkdir()
    (tmp_path / "assets" / "icon.png").write_bytes(b"png")
    write(notes, "v1.11.0.md", with_image("../assets/icon.png"))

    block = whats_new.decks(notes)["1.11.0"]["pages"][0]["blocks"][0]
    assert block["image"] == "../assets/icon.png"

    write(notes, "v1.11.0.md", with_image("../assets/missing.png"))
    with pytest.raises(
        whats_new.DeckError, match=r"blocks\[0\]\.image .* does not exist"
    ):
        whats_new.decks(notes)


@pytest.mark.parametrize(
    "image, ok",
    [("https://example.com/icon.png", True), ("http://example.com/icon.png", False)],
)
def test_absolute_images_must_be_https(tmp_path: Path, image: str, ok: bool) -> None:
    write(tmp_path, "v1.11.0.md", with_image(image))
    if ok:
        whats_new.decks(tmp_path)
    else:
        with pytest.raises(whats_new.DeckError, match="https URL"):
            whats_new.decks(tmp_path)


def test_invalid_deck_writes_nothing(tmp_path: Path) -> None:
    notes, output = tmp_path / "notes", tmp_path / "site"
    notes.mkdir()
    write(notes, "v1.11.0.md", NOTE.replace("type: card", "type: banner", 1))
    with pytest.raises(whats_new.DeckError):
        whats_new.write_decks(notes, output)
    assert not output.exists()


def test_snapshot_sees_changed_and_new_files(tmp_path: Path) -> None:
    write(tmp_path, "v1.11.0.md", NOTE)
    before = whats_new.snapshot(tmp_path)

    (tmp_path / "assets").mkdir()
    (tmp_path / "assets" / "icon.png").write_bytes(b"png")
    assert whats_new.snapshot(tmp_path) != before
