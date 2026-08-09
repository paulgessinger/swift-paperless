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
#   base [<ref>]        the build tag a delta at <ref> is measured against
#   delta [<ref>]       bullets added since that tag — one build's notes,
#                       published as the GitHub prerelease body
#   current [<ref>]     every note for the current version
#   test-notes [<ref>]  the complete TestFlight "What to Test" text: header, this
#                       build's notes, then earlier ones newest-first, trimmed to
#                       App Store Connect's limit
#   fit                 stdin, made safe for App Store Connect (see `fit` below)
#   archive             regenerate changelog.txt from the GitHub prereleases (the
#                       offline record of what each build shipped; needs `gh`)

set -euo pipefail

NOTES_FILE="current_changelog.txt"
ARCHIVE_FILE="changelog.txt"
VERSION_XCCONFIG="Config/Shared/Version.xcconfig"
TEST_NOTES_HEADER="scripts/testflight_test_notes_header.txt"
# Build tags are `builds/<version>/<build>`. The glob deliberately requires both
# components so the pre-1.9 `builds/v90` style tags never match.
TAG_GLOB="builds/*/*"
# App Store Connect rejects a `whatsNew` longer than this many characters. A
# version's notes routinely run past it over a release cycle — 1.6.0 accumulated
# ~14.6k — so the text is trimmed to fit rather than being cleared by hand.
NOTES_MAX_CHARS=4000
RELEASES_URL="https://github.com/paulgessinger/swift-paperless/releases"

# Run from the repo root regardless of where we were invoked.
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Strip blank lines at the start and end while keeping the ones in between.
trim_blank_lines() {
  awk '
    /[^[:space:]]/ { for (; held > 0; held--) print ""; print; seen = 1; next }
    seen { held++ }
  '
}

# Newest line first.
reverse_lines() { awk '{ l[NR] = $0 } END { for (i = NR; i >= 1; i--) print l[i] }'; }

# The notes file as of <ref>; empty when it does not exist there.
notes_at() { git show "$1:$NOTES_FILE" 2>/dev/null || true; }

# MARKETING_VERSION as of <ref>. Anchored: the comments in Version.xcconfig name
# the setting too.
version_at() {
  git show "$1:$VERSION_XCCONFIG" 2>/dev/null | grep -m1 '^MARKETING_VERSION' | sed 's/.*= //' || true
}

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

# Make stdin safe to send as a `whatsNew`: drop emoji / pictographic characters
# (App Store Connect rejects them) and trim to NOTES_MAX_CHARS. Callers put the
# text they care most about first, because trimming drops whole lines off the
# end; when anything is dropped, a pointer to the full notes takes its place.
fit() {
  perl -CSD -e '
    my ($limit, $pointer) = @ARGV;
    local $/;
    my $text = <STDIN> // "";
    $text =~ s/[\p{Extended_Pictographic}\x{FE0F}\x{200D}\x{20E3}\x{1F1E6}-\x{1F1FF}]//g;
    $text =~ s/\s+\z//;
    if (length($text) <= $limit) { print $text, "\n"; exit 0 }

    my $budget = $limit - length($pointer);
    my $out = "";
    for my $line (split /\n/, $text, -1) {
      last if length($out) + length($line) + 1 > $budget;
      $out .= $line . "\n";
    }
    $out =~ s/\s+\z//;
    print $out, $pointer, "\n";
  ' "$NOTES_MAX_CHARS" "$(printf '\n\nOlder notes for this version: %s' "$RELEASES_URL")"
}

# The complete TestFlight "What to Test" text for a build of <ref>: the fixed
# header, then this build's new bullets, then the rest of the version's notes
# newest-first. Ordered that way so that trimming to App Store Connect's limit
# only ever costs the oldest notes.
test_notes() {
  local ref="$1" base version earlier
  base="$(base_tag "$ref")"
  version="$(version_at "$ref")"

  {
    cat "$TEST_NOTES_HEADER"
    echo

    delta "$ref"

    # Everything already published for this version is exactly the notes file as
    # of the previous build tag — but only when that tag belongs to the same
    # version. Right after a MARKETING_VERSION bump it does not, and the new
    # version starts from an empty slate.
    if [ -n "$base" ] && [ "$(version_at "$base")" = "$version" ]; then
      earlier="$(notes_at "$base" | trim_blank_lines | reverse_lines)"
      if [ -n "$earlier" ]; then
        printf '\nEarlier in %s:\n\n%s\n' "$version" "$earlier"
      fi
    fi
  } | fit
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
      # Release bodies are typed in a browser, so normalise CRLF and trailing
      # spaces — the repo lints for both.
      decoded="$(printf '%s' "$body" | base64 -d | tr -d '\r' \
        | sed 's/[[:space:]]*$//' | trim_blank_lines)"
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
  test-notes) test_notes "$ref" ;;
  fit) fit ;;
  archive) archive ;;
  -h | --help) sed -n '2,28p' "$0" ;;
  *)
    echo "usage: $0 {base|delta|current|test-notes} [<ref>]" >&2
    echo "       $0 fit < text" >&2
    echo "       $0 archive" >&2
    exit 2
    ;;
esac
