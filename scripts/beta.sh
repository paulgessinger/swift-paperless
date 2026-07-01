#!/usr/bin/env bash
#
# Prepare a new TestFlight beta and trigger its upload. Reimplements fastlane's
# `beta` lane in bash + git + gh; the next build number comes from the App Store
# Connect CLI (`brew install asc`) instead of the TestFlight API.
#
# Bumps the build number to the next one that is safe on App Store Connect, rolls
# current_changelog.txt into changelog.txt, commits, pushes, and cuts a GitHub
# prerelease. That prerelease triggers .github/workflows/beta.yml, which runs
# `fastlane beta_ci` to build, sign (match), and upload to TestFlight.

set -euo pipefail

ASC_APP='com.paulgessinger.swift-paperless'
VERSION_XCCONFIG='Config/Shared/Version.xcconfig'

# Run from the repo root regardless of where we were invoked.
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Read a setting from Version.xcconfig (the source of truth for version/build).
version_setting() {
  grep -m1 "$1" "$VERSION_XCCONFIG" | sed 's/.*= //'
}

command -v asc >/dev/null 2>&1 || {
  echo "error: 'asc' not found — install with: brew install asc" >&2
  exit 1
}

# asc authenticates from ASC_* env vars; bridge fastlane's names when present so
# the same credentials work locally and in CI.
[ -n "${APP_STORE_CONNECT_API_KEY_ID:-}" ]   && export ASC_KEY_ID="${ASC_KEY_ID:-$APP_STORE_CONNECT_API_KEY_ID}"
[ -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]    && export ASC_ISSUER_ID="${ASC_ISSUER_ID:-$APP_STORE_CONNECT_ISSUER_ID}"
[ -n "${APP_STORE_CONNECT_KEY_FILEPATH:-}" ] && export ASC_PRIVATE_KEY_PATH="${ASC_PRIVATE_KEY_PATH:-$APP_STORE_CONNECT_KEY_FILEPATH}"
[ -n "${APP_STORE_CONNECT_KEY_CONTENT:-}" ]  && export ASC_PRIVATE_KEY="${ASC_PRIVATE_KEY:-$APP_STORE_CONNECT_KEY_CONTENT}"

# Preflight: on main or develop/*, clean tree, up to date (ensure_git_* + git_pull).
branch="$(git rev-parse --abbrev-ref HEAD)"
[[ "$branch" =~ ^(main|develop/.+)$ ]] || {
  echo "error: must be on 'main' or 'develop/*' (on '$branch')" >&2
  exit 1
}
[ -z "$(git status --porcelain)" ] || {
  echo "error: git working tree is not clean" >&2
  exit 1
}
git pull --rebase

version="$(version_setting MARKETING_VERSION)"

# Next build number that is safe to use (considers processed + in-flight uploads).
next="$(asc builds next-build-number --app "$ASC_APP" --platform IOS --output json \
  | python3 -c 'import sys, json; d = json.load(sys.stdin); k = [key for key in d if "next" in key.lower() and "build" in key.lower()]; assert k, "asc: next build number not found in output"; print(d[k[0]])')"

current="$(version_setting CURRENT_PROJECT_VERSION)"
echo "Current build number: $current"
echo "Next build number:    $next"
if [ "$current" = "$next" ]; then
  echo "Build number already at $current — nothing to do"
  exit 0
fi

# Bump the source of truth.
uv run bump.py build "$VERSION_XCCONFIG" "$next"

# Roll the pending notes into the accumulated changelog (beta_ci uploads
# changelog.txt as the TestFlight "what to test"), then clear the pending file.
notes="$(cat current_changelog.txt)"
if [ -n "$notes" ]; then
  {
    printf '%s (%s)\n\n%s\n' "$version" "$next" "$notes"
    if [ -s changelog.txt ]; then
      printf '\n'
      cat changelog.txt
    fi
  } > changelog.txt.tmp
  mv changelog.txt.tmp changelog.txt
  : > current_changelog.txt
fi

# Commit, push, and cut the prerelease that triggers the TestFlight upload.
git commit --no-verify -m "Bump build number to $next" -- \
  "$VERSION_XCCONFIG" changelog.txt current_changelog.txt
git push

notes_file="$(mktemp)"
trap 'rm -f "$notes_file"' EXIT
printf '%s' "$notes" > "$notes_file"
gh release create "builds/$version/$next" \
  --title "v$version ($next)" \
  --notes-file "$notes_file" \
  --prerelease \
  --target main
