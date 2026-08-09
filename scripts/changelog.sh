#!/usr/bin/env bash
#
# Changelog helpers for the TestFlight beta flow.
#
# `current_changelog.txt` accumulates the user-facing notes for the *current*
# marketing version. Nothing clears it at build time: a build's notes are the
# bullets added to the file since the previous build tag, derived from git rather
# than bookkept in a release commit. The file is emptied only when
# MARKETING_VERSION is bumped for an App Store release — a commit you are making
# anyway.
#
# Subcommands take an optional git ref (default HEAD) and read the notes file as
# it exists *at that ref*, not in the working tree, so a preview always shows
# what a build of that commit would actually publish:
#
#   base [<ref>]     the build tag a delta at <ref> is measured against
#   delta [<ref>]    bullets added since that tag — one build's notes, published
#                    as the GitHub prerelease body
#   current [<ref>]  every note for the current version — the TestFlight
#                    "What to Test" body
#   archive          regenerate changelog.txt from the GitHub prereleases (the
#                    offline record of what each build shipped; needs `gh`)

set -euo pipefail

NOTES_FILE="current_changelog.txt"
ARCHIVE_FILE="changelog.txt"
# Build tags are `builds/<version>/<build>`. The glob deliberately requires both
# components so the pre-1.9 `builds/v90` style tags never match.
TAG_GLOB="builds/*/*"

# Run from the repo root regardless of where we were invoked.
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Strip blank lines at the start and end while keeping the ones in between.
trim_blank_lines() {
  awk '
    /[^[:space:]]/ { for (; held > 0; held--) print ""; print; seen = 1; next }
    seen { held++ }
  '
}

# The notes file as of <ref>; empty when it does not exist there.
notes_at() { git show "$1:$NOTES_FILE" 2>/dev/null || true; }

# Most recent build tag reachable from <ref>. Empty if there is none (the first
# build after this flow was introduced, or a branch with no build history).
base_tag() {
  git describe --tags --match "$TAG_GLOB" --abbrev=0 "$1" 2>/dev/null || true
}

# Lines added to the notes file between the last build tag and <ref>. A reworded
# bullet shows up as a removal plus an addition, so the new wording is published
# again with the next build — edit already-published notes on the GitHub release
# instead (that is the copy the in-app "What's New" screen reads).
delta() {
  local ref="$1" base
  base="$(base_tag "$ref")"
  if [ -z "$base" ]; then
    # No build tag to diff against: everything currently in the file is new.
    notes_at "$ref" | trim_blank_lines
    return
  fi
  git diff --no-color --unified=0 "$base" "$ref" -- "$NOTES_FILE" \
    | awk '/^\+\+\+/ { next } /^\+/ { print substr($0, 2) }' \
    | trim_blank_lines
}

# Rebuild changelog.txt from the build prereleases on GitHub. The releases are
# the source of truth for per-build notes now that nothing appends to the file at
# release time; this regenerates the offline copy on demand. Build numbers are
# unique and increasing across versions, so sorting on them alone is enough.
archive() {
  command -v gh >/dev/null 2>&1 || {
    echo "error: gh not found — needed to read the build prereleases" >&2
    exit 1
  }

  local tmp
  tmp="$(mktemp)"
  # `gh release list` cannot return bodies, so go through the API directly.
  gh api 'repos/{owner}/{repo}/releases' --paginate \
    --jq '.[]
          | select(.prerelease)
          | select(.tag_name | test("^builds/[^/]+/[0-9]+$"))
          | [(.tag_name | split("/")[1]), (.tag_name | split("/")[2]), (.body // "" | @base64)]
          | @tsv' \
    | sort -t"$(printf '\t')" -k2,2nr \
    | while IFS="$(printf '\t')" read -r version build body; do
      # Builds published without notes (a rebuild, say) carry no entry, matching
      # what the in-app "What's New" screen shows.
      decoded="$(printf '%s' "$body" | base64 -d | tr -d '\r' | trim_blank_lines)"
      [ -n "$decoded" ] || continue
      printf '%s (%s)\n\n%s\n\n' "$version" "$build" "$decoded"
    done > "$tmp"

  [ -s "$tmp" ] || {
    rm -f "$tmp"
    echo "error: no build prereleases found — refusing to blank $ARCHIVE_FILE" >&2
    exit 1
  }
  {
    echo "# Offline copy of the per-build TestFlight notes, newest first."
    echo "# Regenerate with \`just changelog-archive\`; the GitHub build"
    echo "# prereleases (tag \`builds/<version>/<build>\`) are the source of truth."
    echo
    # Drop the trailing blank line the loop leaves after the last entry.
    trim_blank_lines < "$tmp"
  } > "$ARCHIVE_FILE"
  rm -f "$tmp"
  echo "Wrote $ARCHIVE_FILE ($(grep -c '^' "$ARCHIVE_FILE") lines)"
}

cmd="${1:-}"
ref="${2:-HEAD}"
case "$cmd" in
  base) base_tag "$ref" ;;
  delta) delta "$ref" ;;
  current) notes_at "$ref" | trim_blank_lines ;;
  archive) archive ;;
  -h | --help) sed -n '2,23p' "$0" ;;
  *)
    echo "usage: $0 {base|delta|current} [<ref>]" >&2
    echo "       $0 archive" >&2
    exit 2
    ;;
esac
