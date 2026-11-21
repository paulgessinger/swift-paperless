#!/usr/bin/env python3
# /// script
# dependencies = [
#   "typer",
#   "rich",
# ]
# ///
"""Find localization keys that no Swift code references."""

import json
import re
import subprocess
from pathlib import Path
from typing import Annotated

import typer
from rich.console import Console

app = typer.Typer(help=__doc__)
console = Console()

# Catalogs whose keys Swift code references through generated symbols
# (`.app(.someKey)`). The App Intents catalogs in swift-paperless/Localization
# are looked up by the system and have no such references.
DEFAULT_CATALOGS = "AppShared/Sources/AppShared/Resources/Localization/*.xcstrings"

IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
MEMBER_REFERENCE = re.compile(r"\.([A-Za-z_][A-Za-z0-9_]*)")


def tracked_files(root: Path, pattern: str) -> list[Path]:
    out = subprocess.run(
        ["git", "ls-files", "-z", "--", pattern],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return [root / p for p in out.split("\0") if p]


def dump_catalog(data: dict) -> str:
    # Matches Xcode's catalog formatting byte for byte.
    return (
        json.dumps(data, indent=2, separators=(",", " : "), ensure_ascii=False) + "\n"
    )


@app.command()
def main(
    catalogs: Annotated[
        str, typer.Option(help="Git pathspec of the catalogs to check")
    ] = DEFAULT_CATALOGS,
    remove: Annotated[
        bool, typer.Option("--remove", help="Delete unused keys from the catalogs")
    ] = False,
) -> None:
    """List keys that no tracked Swift file references; exit 1 if any are found.

    A key counts as used when `.<key>` appears in any tracked Swift file, so a
    key that shares its name with an unrelated member is reported as used.
    """
    root = Path(
        subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
    )

    references: set[str] = set()
    for path in tracked_files(root, "*.swift"):
        references.update(
            MEMBER_REFERENCE.findall(path.read_text(encoding="utf-8", errors="replace"))
        )

    total_unused = 0
    for catalog in sorted(tracked_files(root, catalogs)):
        raw = catalog.read_text(encoding="utf-8")
        data = json.loads(raw)
        keys = list(data["strings"])
        unchecked = [k for k in keys if not IDENTIFIER.fullmatch(k)]
        unused = [k for k in keys if IDENTIFIER.fullmatch(k) and k not in references]
        rel = catalog.relative_to(root)

        if unchecked:
            console.print(
                f"[yellow]{rel}: skipped {len(unchecked)} key(s) that are not Swift identifiers[/yellow]"
            )
        if not unused:
            continue

        total_unused += len(unused)
        console.print(f"[bold]{rel}[/bold] ({len(unused)} unused)")
        for key in unused:
            console.print(f"  {key}")

        if remove:
            if dump_catalog(data) != raw:
                console.print(
                    f"[red]{rel}: not in Xcode's formatting, refusing to rewrite[/red]"
                )
                raise typer.Exit(2)
            for key in unused:
                del data["strings"][key]
            catalog.write_text(dump_catalog(data), encoding="utf-8")

    if total_unused == 0:
        console.print("[green]✓ No unused localization keys[/green]")
        return
    if remove:
        console.print(f"[green]Removed {total_unused} unused key(s)[/green]")
        return
    raise typer.Exit(1)


if __name__ == "__main__":
    app()
