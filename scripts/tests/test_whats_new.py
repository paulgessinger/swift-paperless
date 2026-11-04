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
