#!/usr/bin/env -S uv run --script

# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "regex",
#   "typer",
# ]
# ///

"""Changelog helpers for the TestFlight beta flow.

`current_changelog.txt` accumulates the user-facing notes for the *current*
marketing version. Nothing clears it at build time: a build's notes are the
bullets added to the file since the previous build tag, derived from git rather
than bookkept in a release commit. The file is emptied only when
MARKETING_VERSION is bumped for an App Store release — a commit you are making
anyway.

Commands that take a git ref read the notes file as it exists *at that ref*, not
in the working tree, so a preview always shows what a build of that commit would
actually publish.
"""

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Annotated

import regex
import typer

REPO_ROOT = Path(__file__).resolve().parent.parent
NOTES_FILE = "current_changelog.txt"
ARCHIVE_FILE = "changelog.txt"
VERSION_XCCONFIG = "Config/Shared/Version.xcconfig"
TEST_NOTES_HEADER = "scripts/testflight_test_notes_header.txt"

# Build tags are `builds/<version>/<build>`. The glob deliberately requires both
# components so the pre-1.9 `builds/v90` style tags never match.
TAG_GLOB = "builds/*/*"
BUILD_TAG_RE = re.compile(r"^builds/(?P<version>[^/]+)/(?P<build>\d+)$")

# App Store Connect rejects a `whatsNew` longer than this many characters. A
# version's notes routinely run past it over a release cycle — 1.6.0 accumulated
# ~14.6k — so the text is trimmed to fit rather than being cleared by hand.
NOTES_MAX_CHARS = 4000
RELEASES_URL = "https://github.com/paulgessinger/swift-paperless/releases"
TRUNCATION_POINTER = f"\n\nOlder notes for this version: {RELEASES_URL}"

# Emoji and other pictographic characters, which App Store Connect's whatsNew
# field rejects: pictographs themselves, the variation selector, zero-width
# joiner and keycap that compose them, and the regional indicators that make up
# flags. `re` has no Unicode property support, hence `regex`.
PICTOGRAPHIC_RE = regex.compile(
    r"[\p{Extended_Pictographic}\uFE0F\u200D\u20E3\U0001F1E6-\U0001F1FF]"
)

app = typer.Typer(
    help=__doc__,
    add_completion=False,
    no_args_is_help=True,
    pretty_exceptions_show_locals=False,
)

RefArgument = Annotated[str, typer.Argument(help="Git ref to read the notes at.")]


def git(*args: str) -> str:
    """Run git and return its stdout, or an empty string if it fails.

    Every caller here is asking a question that legitimately has no answer on
    some refs — no build tag yet, no notes file in that commit — so a failure is
    reported as "nothing", not as an error.
    """
    result = subprocess.run(
        ["git", *args], capture_output=True, text=True, cwd=REPO_ROOT
    )
    return result.stdout if result.returncode == 0 else ""


def trim_blank_lines(text: str) -> str:
    """Drop blank lines at the start and end, keeping the ones in between."""
    lines = text.splitlines()
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    return "\n".join(lines)


def emit(text: str) -> None:
    """Print `text`, or nothing at all when it is empty.

    Callers capture this in `$(…)` and test for emptiness, so an empty result
    must not come back as a blank line.
    """
    if text:
        print(text)


def notes_at(ref: str) -> str:
    """The notes file as of `ref`; empty when it does not exist there."""
    return git("show", f"{ref}:{NOTES_FILE}")


def version_at(ref: str) -> str:
    """MARKETING_VERSION as of `ref`.

    Anchored: the comments in Version.xcconfig name the setting too.
    """
    match = re.search(
        r"^MARKETING_VERSION\s*=\s*(?P<version>.+)$",
        git("show", f"{ref}:{VERSION_XCCONFIG}"),
        re.MULTILINE,
    )
    return match.group("version").strip() if match else ""


def base_tag(ref: str) -> str:
    """Most recent build tag reachable from `ref`.

    Empty if there is none — the first build after this flow was introduced, or
    a branch with no build history.
    """
    return git("describe", "--tags", "--match", TAG_GLOB, "--abbrev=0", ref).strip()


def delta(ref: str) -> str:
    """Lines added to the notes file between the last build tag and `ref`.

    A reworded bullet shows up as a removal plus an addition, so the new wording
    is published again with the next build — edit already-published notes on the
    GitHub release instead (that is the copy the in-app "What's New" screen
    reads).
    """
    base = base_tag(ref)
    if not base:
        # No build tag to diff against: everything currently in the file is new.
        return trim_blank_lines(notes_at(ref))

    diff = git("diff", "--no-color", "--unified=0", base, ref, "--", NOTES_FILE)
    added = [
        line[1:]
        for line in diff.splitlines()
        if line.startswith("+") and not line.startswith("+++")
    ]
    return trim_blank_lines("\n".join(added))


def fit_text(text: str) -> str:
    """Make `text` safe to send as a `whatsNew`.

    Drops pictographic characters and trims to NOTES_MAX_CHARS. Callers put the
    text they care most about first, because trimming drops whole lines off the
    end; when anything is dropped, a pointer to the full notes takes its place.
    """
    text = PICTOGRAPHIC_RE.sub("", text).rstrip()
    if len(text) <= NOTES_MAX_CHARS:
        return text

    budget = NOTES_MAX_CHARS - len(TRUNCATION_POINTER)
    kept: list[str] = []
    length = 0
    for line in text.split("\n"):
        if length + len(line) + 1 > budget:
            break
        kept.append(line)
        length += len(line) + 1
    return "\n".join(kept).rstrip() + TRUNCATION_POINTER


@app.command()
def base(ref: RefArgument = "HEAD") -> None:
    """Print the build tag a delta at REF is measured against."""
    emit(base_tag(ref))


@app.command("delta")
def delta_command(ref: RefArgument = "HEAD") -> None:
    """Print one build's notes — the GitHub prerelease body."""
    emit(delta(ref))


@app.command()
def current(ref: RefArgument = "HEAD") -> None:
    """Print every note accumulated for the current marketing version."""
    emit(trim_blank_lines(notes_at(ref)))


@app.command("test-notes")
def test_notes(ref: RefArgument = "HEAD") -> None:
    """Print the complete TestFlight "What to Test" text for a build of REF.

    The fixed header, then this build's new bullets, then the rest of the
    version's notes newest-first. Ordered that way so that trimming to App Store
    Connect's limit only ever costs the oldest notes.
    """
    sections = [(REPO_ROOT / TEST_NOTES_HEADER).read_text().strip()]

    new_notes = delta(ref)
    if new_notes:
        sections.append(new_notes)

    # Everything already published for this version is exactly the notes file as
    # of the previous build tag — but only when that tag belongs to the same
    # version. Right after a MARKETING_VERSION bump it does not, and the new
    # version starts from an empty slate.
    version = version_at(ref)
    tag = base_tag(ref)
    if tag and version and version_at(tag) == version:
        earlier = trim_blank_lines(notes_at(tag))
        if earlier:
            newest_first = "\n".join(reversed(earlier.splitlines()))
            sections.append(f"Earlier in {version}:\n\n{newest_first}")

    print(fit_text("\n\n".join(sections)))


@app.command("fit")
def fit_command() -> None:
    """Read stdin and print it made safe for App Store Connect."""
    print(fit_text(sys.stdin.read()))


@app.command()
def archive() -> None:
    """Rebuild changelog.txt from the build prereleases on GitHub.

    The releases are the source of truth for per-build notes now that nothing
    appends to the file at release time; this regenerates the offline copy on
    demand.
    """
    if shutil.which("gh") is None:
        typer.echo(
            "error: gh not found — needed to read the build prereleases", err=True
        )
        raise typer.Exit(1)

    # `gh release list` cannot return bodies, so go through the API directly.
    # `.[] | @json` gives one compact release per line.
    result = subprocess.run(
        [
            "gh",
            "api",
            "repos/{owner}/{repo}/releases",
            "--paginate",
            "--jq",
            ".[] | @json",
        ],
        capture_output=True,
        text=True,
        cwd=REPO_ROOT,
    )
    if result.returncode != 0:
        typer.echo(f"error: gh api failed: {result.stderr.strip()}", err=True)
        raise typer.Exit(1)

    entries: list[tuple[int, str]] = []
    for line in result.stdout.splitlines():
        if not line.strip():
            continue
        release = json.loads(line)
        if not release.get("prerelease"):
            continue
        match = BUILD_TAG_RE.match(release.get("tag_name", ""))
        if not match:
            continue
        # Release bodies are typed in a browser, so normalise CRLF and trailing
        # spaces — the repo lints for both.
        body = release.get("body") or ""
        body = "\n".join(line.rstrip() for line in body.replace("\r", "").splitlines())
        body = trim_blank_lines(body)
        # Builds published without notes (a rebuild, say) carry no entry,
        # matching what the in-app "What's New" screen shows.
        if not body:
            continue
        build = int(match.group("build"))
        # A few 1.9/1.10-era tags were cut as `builds/v1.10.0/196` by a since
        # removed `just tag` recipe. Normalise so the archive reads consistently.
        version = match.group("version").removeprefix("v")
        entries.append((build, f"{version} ({build})\n\n{body}"))

    if not entries:
        typer.echo(
            f"error: no build prereleases found — refusing to blank {ARCHIVE_FILE}",
            err=True,
        )
        raise typer.Exit(1)

    # Build numbers are unique and increasing across versions, so sorting on them
    # alone is enough.
    entries.sort(key=lambda entry: entry[0], reverse=True)
    header = (
        "# Offline copy of the per-build TestFlight notes, newest first.\n"
        "# Regenerate with `just changelog-archive`; the GitHub build\n"
        "# prereleases (tag `builds/<version>/<build>`) are the source of truth.\n"
    )
    text = header + "\n" + "\n\n".join(entry for _, entry in entries) + "\n"
    (REPO_ROOT / ARCHIVE_FILE).write_text(text)
    line_count = text.count("\n")
    typer.echo(f"Wrote {ARCHIVE_FILE} ({line_count} lines)")


if __name__ == "__main__":
    os.chdir(REPO_ROOT)
    app()
