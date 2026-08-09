#!/usr/bin/env bash
#
# Set (create or update) the TestFlight "What to Test" notes for a build that is
# already on App Store Connect — no rebuild/re-upload. Useful when a build was
# uploaded without notes (e.g. the `asc builds upload` whatsNew step failed on an
# invalid character), or to tweak notes after the fact.
#
# By default it sends exactly what scripts/beta_ci.sh would have sent for the
# checked-out commit (`scripts/changelog.sh test-notes`). Give a notes file to
# override the body; either way the text is stripped of emoji and trimmed to App
# Store Connect's limit.
#
# This only fixes the TestFlight side. The notes users see in the app's "What's
# New" screen come from the build's GitHub prerelease, so fix those by editing
# the `builds/<version>/<build>` release body on GitHub.
#
# Usage:
#   scripts/set_test_notes.sh <build-number> [version] [notes-file]
#     build-number  required — the TestFlight build to set notes on
#     version       optional — marketing version (default: Version.xcconfig)
#     notes-file    optional — override the notes body
#
# Credentials: same as scripts/beta.sh — APP_STORE_CONNECT_* env, or an `asc`
# keychain login (asc auth login).

set -euo pipefail

ASC_APP="com.paulgessinger.swift-paperless"
VERSION_XCCONFIG="Config/Shared/Version.xcconfig"
TEST_NOTES_HEADER="scripts/testflight_test_notes_header.txt"
CHANGELOG="scripts/changelog.sh"
LOCALE="en-US"

build="${1:-}"
[ -n "$build" ] || { echo "usage: $0 <build-number> [version] [notes-file]" >&2; exit 2; }
case "$build" in
  *[!0-9]*) echo "error: build number must be numeric, got '$build'" >&2; exit 2 ;;
esac

# Run from the repo root regardless of where we were invoked.
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Anchored so the comments above the settings — which name them — cannot be
# picked up instead.
version_setting() { grep -m1 "^$1" "$VERSION_XCCONFIG" | sed 's/.*= //'; }
version="${2:-$(version_setting MARKETING_VERSION)}"
notes_file="${3:-}"
[ -z "$notes_file" ] || [ -s "$notes_file" ] || {
  echo "error: notes body is empty or missing: $notes_file" >&2
  exit 1
}

# Bridge fastlane's credential names to the ASC_* env vars `asc` reads (mirrors
# scripts/beta.sh), so the same secrets work here. asc also falls back to its
# keychain login when no env is set.
[ -n "${APP_STORE_CONNECT_API_KEY_ID:-}" ]   && export ASC_KEY_ID="${ASC_KEY_ID:-$APP_STORE_CONNECT_API_KEY_ID}"
[ -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]    && export ASC_ISSUER_ID="${ASC_ISSUER_ID:-$APP_STORE_CONNECT_ISSUER_ID}"
[ -n "${APP_STORE_CONNECT_KEY_FILEPATH:-}" ] && export ASC_PRIVATE_KEY_PATH="${ASC_PRIVATE_KEY_PATH:-$APP_STORE_CONNECT_KEY_FILEPATH}"
[ -n "${APP_STORE_CONNECT_KEY_CONTENT:-}" ]  && export ASC_PRIVATE_KEY="${ASC_PRIVATE_KEY:-$APP_STORE_CONNECT_KEY_CONTENT}"

command -v asc >/dev/null 2>&1 || { echo "error: asc not found (brew install asc)" >&2; exit 1; }

if [ -n "$notes_file" ]; then
  # Explicit body: still goes through `fit`, which strips emoji and trims to App
  # Store Connect's limit.
  notes="$(printf '%s\n\n%s' "$(cat "$TEST_NOTES_HEADER")" "$(cat "$notes_file")" \
    | "$CHANGELOG" fit)"
else
  # Default: exactly what scripts/beta_ci.sh would have sent for this commit.
  notes="$("$CHANGELOG" test-notes HEAD)"
fi

app_id="$(asc apps list --bundle-id "$ASC_APP" --output json 2>/dev/null \
  | jq -r '.data[0].id // empty' 2>/dev/null || true)"
[ -n "$app_id" ] || { echo "error: could not resolve app id — is asc logged in? (asc auth login)" >&2; exit 1; }

selector=(--app "$app_id" --build-number "$build" --version "$version" --platform IOS --locale "$LOCALE")

# Create if no note exists for this build+locale yet, otherwise update.
if asc builds test-notes view "${selector[@]}" >/dev/null 2>&1; then
  op=update
else
  op=create
fi

echo "==> ${op^}ing What to Test for build $version ($build) [$LOCALE]"
asc builds test-notes "$op" "${selector[@]}" --whats-new "$notes"
echo "Done."
