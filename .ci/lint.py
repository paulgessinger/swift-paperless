#!/usr/bin/env python3
# /// script
# dependencies = [
#   "typer",
#   "rich",
# ]
# ///
"""Lint files for whitespace and EOF issues."""

import os
import re
from pathlib import Path
from typing import Annotated, Iterator

import typer
from rich.console import Console

app = typer.Typer(help="Lint files for whitespace and EOF issues")
console = Console()


class GitignoreParser:
    """Parse and match .gitignore patterns with support for recursive .gitignore files."""

    def __init__(self, root: Path):
        self.root = root
        # Cache of directory -> list of patterns from .gitignore in that dir
        self.gitignore_cache: dict[Path, list[tuple[re.Pattern, bool, bool]]] = {}
        self._load_gitignore(root)

    def _load_gitignore(self, directory: Path) -> None:
        """Load .gitignore file from a directory if it exists."""
        gitignore_path = directory / ".gitignore"
        if not gitignore_path.exists():
            return

        patterns = []
        with open(gitignore_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.rstrip("\n\r")

                # Skip empty lines and comments
                if not line or line.startswith("#"):
                    continue

                # Check for negation
                negation = line.startswith("!")
                if negation:
                    line = line[1:]

                # Check if pattern is directory-only
                dir_only = line.endswith("/")
                if dir_only:
                    line = line[:-1]

                # Convert gitignore pattern to regex
                pattern = self._pattern_to_regex(line, directory)
                patterns.append((pattern, negation, dir_only))

        if patterns:
            self.gitignore_cache[directory] = patterns

    def _pattern_to_regex(self, pattern: str, base_dir: Path) -> re.Pattern:
        """Convert gitignore pattern to compiled regex."""
        # Escape special regex characters except *, ?, [, ]
        escaped = re.sub(r"([\.\+\^\$\(\)\{\}\|\\\:])", r"\\\1", pattern)

        # Handle gitignore wildcards
        regex = escaped.replace("**", "\x00")  # Placeholder for **
        regex = regex.replace("*", "[^/]*")  # * matches anything except /
        regex = regex.replace("\x00", ".*")  # ** matches anything including /
        regex = regex.replace("?", "[^/]")  # ? matches single character except /

        # Handle leading slash (match from this directory only)
        if pattern.startswith("/"):
            # Get relative path from root to this directory
            try:
                rel_base = base_dir.relative_to(self.root)
                if str(rel_base) != ".":
                    prefix = str(rel_base).replace(os.sep, "/") + "/"
                else:
                    prefix = ""
            except ValueError:
                prefix = ""
            regex = "^" + prefix + regex[1:]
        else:
            # Match anywhere in path from this directory down
            try:
                rel_base = base_dir.relative_to(self.root)
                if str(rel_base) != ".":
                    prefix = "(" + str(rel_base).replace(os.sep, "/") + "/)"
                else:
                    prefix = "(^|/)"
            except ValueError:
                prefix = "(^|/)"
            regex = prefix + regex

        # Handle trailing to match path components
        regex = regex + "($|/)"

        return re.compile(regex)

    def is_ignored(self, path: Path) -> bool:
        """Check if a path should be ignored based on .gitignore patterns."""
        # Get relative path from root
        try:
            rel_path = path.relative_to(self.root)
        except ValueError:
            return False

        # Convert to string with forward slashes
        path_str = str(rel_path).replace(os.sep, "/")

        # Check if it's a directory
        is_dir = path.is_dir()

        # Collect all applicable .gitignore files from root to this path
        # We need to check from most specific (closest to file) to least specific (root)
        current = path.parent
        applicable_dirs = []
        while True:
            applicable_dirs.append(current)
            if current == self.root:
                break
            try:
                current = current.parent
            except (ValueError, RuntimeError):
                break

        # Check patterns from root to file (so more specific overrides general)
        ignored = False
        for directory in reversed(applicable_dirs):
            if directory in self.gitignore_cache:
                for pattern, negation, dir_only in self.gitignore_cache[directory]:
                    # Skip directory-only patterns for files
                    if dir_only and not is_dir:
                        continue

                    if pattern.search(path_str):
                        ignored = not negation

        return ignored


def is_text_file(file_path: Path) -> bool:
    """Check if a file is likely a text file (similar to how 'less' detects it)."""
    # Known binary extensions to skip
    binary_extensions = {
        # Images
        ".png",
        ".jpg",
        ".jpeg",
        ".gif",
        ".bmp",
        ".ico",
        ".svg",
        ".webp",
        ".tiff",
        # Archives
        ".zip",
        ".tar",
        ".gz",
        ".bz2",
        ".xz",
        ".7z",
        ".rar",
        # Executables/libraries
        ".exe",
        ".dll",
        ".so",
        ".dylib",
        ".a",
        ".o",
        # Documents
        ".pdf",
        ".doc",
        ".docx",
        ".xls",
        ".xlsx",
        ".ppt",
        ".pptx",
        # Media
        ".mp3",
        ".mp4",
        ".avi",
        ".mov",
        ".wav",
        ".flac",
        # Apple specific
        ".app",
        ".framework",
        ".bundle",
        ".xcassets",
        ".ipa",
        ".dSYM",
        # Fonts
        ".ttf",
        ".otf",
        ".woff",
        ".woff2",
        # Other
        ".pyc",
        ".pyo",
        ".class",
        ".jar",
    }

    # Check extension
    if file_path.suffix.lower() in binary_extensions:
        return False

    # Try to detect binary content by reading first chunk
    try:
        with open(file_path, "rb") as f:
            chunk = f.read(8192)
            # If file is empty, consider it text
            if not chunk:
                return True

            # Check for null bytes (definitive binary indicator)
            if b"\x00" in chunk:
                return False

            # Count printable vs non-printable characters
            # Allow common whitespace: \t \n \r \f \v
            non_printable = 0
            for byte in chunk:
                # Control characters except common whitespace
                if byte < 32 and byte not in (9, 10, 13, 12, 11):
                    non_printable += 1
                # DEL and extended ASCII control characters
                elif byte == 127 or (128 <= byte < 160):
                    non_printable += 1

            # If more than 30% non-printable, consider it binary
            # (less uses a similar heuristic)
            if len(chunk) > 0 and (non_printable / len(chunk)) > 0.3:
                return False

            return True
    except (PermissionError, OSError):
        return False


def find_all_files(root: Path, parser: GitignoreParser) -> Iterator[Path]:
    """Recursively find all non-ignored text files in directory."""
    # Common build/system directories to always skip
    always_skip = {
        ".git",
        ".jj",
        ".build",
        ".swiftpm",
        "build",
        "DerivedData",
        "__pycache__",
    }

    for item in root.iterdir():
        # Skip always-ignored directories
        if item.is_dir() and item.name in always_skip:
            continue

        # Check if ignored by .gitignore
        if parser.is_ignored(item):
            continue

        if item.is_file():
            # Only yield text files
            if is_text_file(item):
                yield item
        elif item.is_dir():
            # Load .gitignore from this subdirectory if it exists
            parser._load_gitignore(item)
            yield from find_all_files(item, parser)


def fix_trailing_whitespace(file_path: Path) -> bool:
    """Remove trailing whitespace from file. Returns True if modified."""
    try:
        with open(file_path, "r", encoding="utf-8", newline="") as f:
            lines = f.readlines()
    except (UnicodeDecodeError, PermissionError):
        # Skip binary files or files we can't read
        return False

    # Remove trailing whitespace from each line
    modified = False
    new_lines = []
    for line in lines:
        # Strip all trailing whitespace, then restore the newline
        stripped = line.rstrip()
        # Check if line originally had a newline
        if line and line[-1] in ("\n", "\r"):
            # Find the original newline sequence
            if line.endswith("\r\n"):
                newline_seq = "\r\n"
            elif line.endswith("\n"):
                newline_seq = "\n"
            elif line.endswith("\r"):
                newline_seq = "\r"
            else:
                newline_seq = ""

            # Add newline back if content remains
            if stripped:
                stripped = stripped + newline_seq
            else:
                # Empty line (was only whitespace), keep just the newline
                stripped = newline_seq

        if stripped != line:
            modified = True
        new_lines.append(stripped)

    # Write back if modified
    if modified:
        with open(file_path, "w", encoding="utf-8", newline="") as f:
            f.writelines(new_lines)
        return True

    return False


def fix_eof(file_path: Path) -> bool:
    """Ensure file ends with exactly one newline. Returns True if modified."""
    try:
        with open(file_path, "rb+") as f:
            content = f.read()

            # Empty file - nothing to fix
            if not content:
                return False

            # Find the position where non-newline content ends
            # Work backwards through newlines
            original_len = len(content)
            end_pos = original_len

            while end_pos > 0 and content[end_pos - 1 : end_pos] in (b"\n", b"\r"):
                end_pos -= 1

            # If file was all newlines, truncate to empty
            if end_pos == 0:
                f.seek(0)
                f.truncate(0)
                return True

            # Now we know where actual content ends
            # File should end at: content + single newline
            desired_end = end_pos + 1

            if desired_end != original_len:
                # Need to adjust - either add or remove newlines
                f.seek(end_pos)
                f.write(b"\n")
                f.truncate(end_pos + 1)
                return True

            return False

    except (PermissionError, OSError):
        return False


@app.command()
def whitespace(
    root: Annotated[
        Path,
        typer.Option(help="Root directory to scan"),
    ] = Path.cwd(),
) -> None:
    """Fix trailing whitespace in all non-ignored files."""
    parser = GitignoreParser(root)

    modified_count = 0
    with console.status("[bold green]Scanning files..."):
        for file_path in find_all_files(root, parser):
            if fix_trailing_whitespace(file_path):
                console.print(f"[yellow]Fixed:[/yellow] {file_path.relative_to(root)}")
                modified_count += 1

    if modified_count > 0:
        console.print(
            f"\n[green]✓[/green] Fixed trailing whitespace in {modified_count} file(s)"
        )
    else:
        console.print("[green]✓[/green] No trailing whitespace found")


@app.command()
def eof(
    root: Annotated[
        Path,
        typer.Option(help="Root directory to scan"),
    ] = Path.cwd(),
) -> None:
    """Ensure all non-ignored files end with a newline."""
    parser = GitignoreParser(root)

    modified_count = 0
    with console.status("[bold green]Scanning files..."):
        for file_path in find_all_files(root, parser):
            if fix_eof(file_path):
                console.print(f"[yellow]Fixed:[/yellow] {file_path.relative_to(root)}")
                modified_count += 1

    if modified_count > 0:
        console.print(f"\n[green]✓[/green] Fixed EOF in {modified_count} file(s)")
    else:
        console.print("[green]✓[/green] All files end with newline")


@app.command()
def all(
    root: Annotated[
        Path,
        typer.Option(help="Root directory to scan"),
    ] = Path.cwd(),
) -> None:
    """Run all lint fixes (whitespace + EOF)."""
    console.print("[bold]Running whitespace fix...[/bold]")
    whitespace(root)
    console.print("\n[bold]Running EOF fix...[/bold]")
    eof(root)


if __name__ == "__main__":
    app()
