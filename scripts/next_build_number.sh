#!/usr/bin/env bash
#
# Print the next free TestFlight build number, as App Store Connect assigns it
# (`asc builds next-build-number`, which accounts for processed *and* in-flight
# uploads). Used by scripts/beta_ci.sh and `just next-build`.
#
# Usage:
#   scripts/next_build_number.sh [app]
#     app  optional — numeric App Store Connect app ID or bundle ID
#          (default: com.paulgessinger.swift-paperless)
#
# asc authenticates from its own keychain login or the ASC_* env vars.

set -euo pipefail

app="${1:-com.paulgessinger.swift-paperless}"

command -v asc >/dev/null 2>&1 || { echo "error: asc not found (brew install asc)" >&2; exit 1; }

number="$(asc builds next-build-number --app "$app" --platform IOS --output json \
  | jq -r '.nextBuildNumber')"

case "$number" in
  "" | *[!0-9]*)
    echo "error: App Store Connect returned no usable build number ('$number')" >&2
    exit 1
    ;;
esac

echo "$number"
