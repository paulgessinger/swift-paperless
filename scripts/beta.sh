#!/usr/bin/env bash
#
# Trigger a TestFlight beta on GitHub Actions.
#
# Nothing is built, committed, or pushed here: this only kicks off
# .github/workflows/beta.yml against a ref that is already on GitHub. CI assigns
# the build number from App Store Connect, builds, uploads, and then records what
# shipped as the `builds/<version>/<build>` tag and its prerelease. So a beta can
# also be cut straight from the GitHub UI — this script just adds a preview of
# the notes the build will publish, and a confirmation prompt.
#
# Usage:
#   scripts/beta.sh                     # beta from origin/main
#   scripts/beta.sh --ref develop/v1.12 # beta from another branch
#   scripts/beta.sh --build-number 210  # re-run at a known number
#   scripts/beta.sh --dry-run           # build + export in CI, no upload, no tag
#   scripts/beta.sh --yes               # skip the confirmation prompt
#
# Requires `gh` authenticated against the repo.

set -euo pipefail

WORKFLOW="beta.yml"
CHANGELOG="scripts/changelog.py"
VERSION_XCCONFIG="Config/Shared/Version.xcconfig"

ref="main"
build_number=""
dry_run="false"
assume_yes=0
while [ $# -gt 0 ]; do
  case "$1" in
    --ref) ref="${2:?--ref needs a branch}"; shift ;;
    --build-number)
      build_number="${2:-}"
      case "$build_number" in
        "" | *[!0-9]*) echo "error: --build-number needs a number" >&2; exit 2 ;;
      esac
      shift
      ;;
    --dry-run) dry_run="true" ;;
    -y | --yes) assume_yes=1 ;;
    -h | --help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "error: unknown argument '$1'" >&2; exit 2 ;;
  esac
  shift
done

# Run from the repo root regardless of where we were invoked.
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v gh >/dev/null 2>&1 || {
  echo "error: 'gh' not found — install with: brew install gh" >&2
  exit 1
}

# CI builds what is on GitHub, so preview from the remote ref, not the working
# tree. Build tags are needed to work out which notes are new.
echo "==> Fetching origin/$ref"
git fetch --quiet origin "$ref" --tags

remote="$(git rev-parse "origin/$ref")"
version="$(git show "origin/$ref:$VERSION_XCCONFIG" | grep -m1 '^MARKETING_VERSION' | sed 's/.*= //')"
base="$("$CHANGELOG" base "$remote")"
notes="$("$CHANGELOG" delta "$remote")"

echo
echo "  ref     origin/$ref at ${remote:0:9} — $(git log -1 --format=%s "$remote")"
echo "  version $version (build number assigned by App Store Connect)"
echo "  notes   new since ${base:-the start of history}"
echo
if [ -n "$notes" ]; then
  printf '%s\n' "$notes" | sed 's/^/    /'
else
  echo "    (none — this build will be published without release notes)"
fi
echo

if [ "$dry_run" = "true" ]; then
  echo "  --dry-run: CI will build and export only; nothing is uploaded or tagged"
  echo
fi

if [ "$assume_yes" -eq 0 ]; then
  [ -t 0 ] || {
    echo "error: not a terminal — pass --yes to trigger without confirming" >&2
    exit 1
  }
  reply=""
  read -r -p "Trigger a TestFlight beta from this? [y/N] " reply || true
  case "$reply" in
    [yY] | [yY][eE][sS]) ;;
    *) echo "Aborted."; exit 1 ;;
  esac
fi

args=(--ref "$ref" -f "dry_run=$dry_run")
[ -n "$build_number" ] && args+=(-f "build_number=$build_number")
gh workflow run "$WORKFLOW" "${args[@]}"

echo "Triggered — watch it with:"
echo "  gh run watch \$(gh run list --workflow $WORKFLOW --limit 1 --json databaseId --jq '.[0].databaseId')"
