#!/usr/bin/env bash
#
# Build, sign, and upload a TestFlight beta — a fastlane-free replacement for the
# Fastfile `beta_ci` lane. It uses plain xcodebuild for archive/export (automatic
# signing via `-allowProvisioningUpdates` + an App Store Connect API key, so no
# `match`) and `asc` (App Store Connect CLI, `brew install asc`) for the upload.
#
# Runs the same locally and in CI:
#   scripts/beta_ci.sh                # archive -> export -> upload + What to Test
#   scripts/beta_ci.sh --no-upload    # archive -> export only (safe local test)
#   scripts/beta_ci.sh --dry-run      # export + `asc builds upload --dry-run`
#   scripts/beta_ci.sh --bump ...     # override build number to the next free one
#                                     # (local testing only; restored on exit, never
#                                     # committed — the real bump is scripts/beta.sh)
#
# Signing: locally the "Apple Distribution" certificate already in your login
# keychain is used. In CI, set DIST_CERTIFICATE_P12_BASE64 (+ optional
# DIST_CERTIFICATE_PASSWORD) and it is imported into a throwaway keychain.
#
# Credentials (same names as scripts/beta.sh / the fastlane lane):
#   APP_STORE_CONNECT_API_KEY_ID, APP_STORE_CONNECT_ISSUER_ID, and one of
#   APP_STORE_CONNECT_KEY_FILEPATH or APP_STORE_CONNECT_KEY_CONTENT.

set -euo pipefail

SCHEME="swift-paperless"
ASC_APP="com.paulgessinger.swift-paperless"
VERSION_XCCONFIG="Config/Shared/Version.xcconfig"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/$SCHEME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTIONS="scripts/ExportOptions.plist"
TEST_NOTES_HEADER="scripts/testflight_test_notes_header.txt"

upload=1
asc_dry_run=0
bump=0
for arg in "$@"; do
  case "$arg" in
    --no-upload) upload=0 ;;
    --dry-run)   asc_dry_run=1 ;;
    --bump)      bump=1 ;;
    -h|--help)   sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "error: unknown argument '$arg'" >&2; exit 2 ;;
  esac
done

# Remember where we were invoked (to resolve relative paths given on the CLI/env),
# then run from the repo root regardless of where we were invoked.
invocation_dir="$PWD"
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Read a setting from Version.xcconfig (the source of truth for version/build).
version_setting() { grep -m1 "$1" "$VERSION_XCCONFIG" | sed 's/.*= //'; }

# Pipe xcodebuild through xcbeautify when available; keep raw output otherwise.
run_xcodebuild() {
  if command -v xcbeautify >/dev/null 2>&1; then
    xcodebuild "$@" | xcbeautify
  else
    xcodebuild "$@"
  fi
}

_tmp_key=""
_tmp_keychain=""
_version_backup=""
cleanup() {
  [ -n "$_tmp_key" ] && rm -f "$_tmp_key"
  [ -n "$_tmp_keychain" ] && security delete-keychain "$_tmp_keychain" 2>/dev/null
  # Restore Version.xcconfig if --bump temporarily rewrote it.
  [ -n "$_version_backup" ] && [ -f "$_version_backup" ] && mv -f "$_version_backup" "$VERSION_XCCONFIG"
  return 0
}
trap cleanup EXIT

# --- credentials -----------------------------------------------------------
# asc reads ASC_* env vars; bridge fastlane's names so one set of secrets works
# both locally and in CI (mirrors scripts/beta.sh).
[ -n "${APP_STORE_CONNECT_API_KEY_ID:-}" ]   && export ASC_KEY_ID="${ASC_KEY_ID:-$APP_STORE_CONNECT_API_KEY_ID}"
[ -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]    && export ASC_ISSUER_ID="${ASC_ISSUER_ID:-$APP_STORE_CONNECT_ISSUER_ID}"
[ -n "${APP_STORE_CONNECT_KEY_FILEPATH:-}" ] && export ASC_PRIVATE_KEY_PATH="${ASC_PRIVATE_KEY_PATH:-$APP_STORE_CONNECT_KEY_FILEPATH}"
[ -n "${APP_STORE_CONNECT_KEY_CONTENT:-}" ]  && export ASC_PRIVATE_KEY="${ASC_PRIVATE_KEY:-$APP_STORE_CONNECT_KEY_CONTENT}"

# xcodebuild's -allowProvisioningUpdates needs the key as a file on disk plus the
# key/issuer IDs. Materialise a .p8 from KEY_CONTENT when only that is provided.
KEY_ID="${APP_STORE_CONNECT_API_KEY_ID:-${ASC_KEY_ID:-}}"
ISSUER_ID="${APP_STORE_CONNECT_ISSUER_ID:-${ASC_ISSUER_ID:-}}"
KEY_PATH="${APP_STORE_CONNECT_KEY_FILEPATH:-${ASC_PRIVATE_KEY_PATH:-}}"
if [ -n "$KEY_PATH" ]; then
  # xcodebuild -authenticationKeyPath requires an absolute path to an existing
  # file, but we've cd'd to the repo root — expand ~ and resolve relatives
  # against the invocation dir.
  case "$KEY_PATH" in
    "~")   KEY_PATH="$HOME" ;;
    "~/"*) KEY_PATH="$HOME/${KEY_PATH#\~/}" ;;
  esac
  case "$KEY_PATH" in
    /*) ;;
    *)  KEY_PATH="$invocation_dir/$KEY_PATH" ;;
  esac
  [ -f "$KEY_PATH" ] || {
    echo "error: API key file not found: $KEY_PATH" >&2
    echo "       (set APP_STORE_CONNECT_KEY_FILEPATH to the AuthKey.p8 path)" >&2
    exit 1
  }
  export ASC_PRIVATE_KEY_PATH="$KEY_PATH"
elif [ -n "${APP_STORE_CONNECT_KEY_CONTENT:-}" ]; then
  # Materialise a .p8 from KEY_CONTENT when only that is provided.
  _tmp_key="$(mktemp -t asc_key.XXXXXX).p8"
  printf '%s' "$APP_STORE_CONNECT_KEY_CONTENT" > "$_tmp_key"
  KEY_PATH="$_tmp_key"
fi

auth_args=(-allowProvisioningUpdates)
if [ -n "$KEY_ID" ] && [ -n "$ISSUER_ID" ] && [ -n "$KEY_PATH" ]; then
  auth_args+=(-authenticationKeyID "$KEY_ID"
              -authenticationKeyIssuerID "$ISSUER_ID"
              -authenticationKeyPath "$KEY_PATH")
else
  echo "note: no ASC API key in env — relying on locally cached signing assets" >&2
fi

# --- CI signing certificate ------------------------------------------------
# A fresh CI runner has no "Apple Distribution" cert. Import one from a base64
# secret into a throwaway keychain. Locally this block is skipped — the login
# keychain already holds the cert.
if [ -n "${DIST_CERTIFICATE_P12_BASE64:-}" ]; then
  echo "==> Importing distribution certificate into a temporary keychain"
  _tmp_keychain="$(mktemp -d)/build.keychain-db"
  keychain_pw="$(uuidgen)"
  cert_p12="$(mktemp -t dist_cert.XXXXXX).p12"
  # `-d` (not GNU-only `--decode`) so it works on both macOS/BSD and GNU base64.
  printf '%s' "$DIST_CERTIFICATE_P12_BASE64" | base64 -d > "$cert_p12"

  security create-keychain -p "$keychain_pw" "$_tmp_keychain"
  security set-keychain-settings -lut 21600 "$_tmp_keychain"
  security unlock-keychain -p "$keychain_pw" "$_tmp_keychain"
  security import "$cert_p12" -P "${DIST_CERTIFICATE_PASSWORD:-}" \
    -A -t cert -f pkcs12 -k "$_tmp_keychain"
  security set-key-partition-list -S apple-tool:,apple: -k "$keychain_pw" "$_tmp_keychain" >/dev/null
  # Prepend our keychain to the user search list so xcodebuild finds the cert.
  security list-keychains -d user -s "$_tmp_keychain" \
    $(security list-keychains -d user | sed 's/["]//g')
  rm -f "$cert_p12"
fi

version="$(version_setting MARKETING_VERSION)"
current="$(version_setting CURRENT_PROJECT_VERSION)"

# Resolve the numeric App Store Connect app ID from the bundle ID. `asc builds
# upload` requires the numeric ID (unlike next-build-number, which accepts the
# bundle ID). asc authenticates from its own keychain login or the ASC_* env
# vars, so this works whenever asc is logged in — not only when env keys are set.
# Left empty (and asc-dependent steps skipped) if asc is missing or not logged in.
app_id=""
if command -v asc >/dev/null 2>&1; then
  app_id="$(asc apps list --bundle-id "$ASC_APP" --output json 2>/dev/null \
    | jq -r '.data[0].id // empty' 2>/dev/null || true)"
fi

if [ "$bump" -eq 1 ]; then
  # --bump (local testing): rewrite the build number to the next free one and
  # restore Version.xcconfig on exit. Never committed — the real bump lives in
  # scripts/beta.sh. Replaces the guard below, since we're setting it directly.
  [ -n "$app_id" ] || {
    echo "error: --bump needs asc logged in (asc auth login) or APP_STORE_CONNECT_* env to read the next build number" >&2
    exit 1
  }
  next="$(asc builds next-build-number --app "$app_id" --platform IOS --output json \
    | jq -r '.nextBuildNumber')"
  echo "==> --bump: setting build number $current -> $next (restored on exit)"
  _version_backup="$(mktemp)"
  cp "$VERSION_XCCONFIG" "$_version_backup"
  uv run bump.py build "$VERSION_XCCONFIG" "$next"
  current="$next"
# --- build-number guard ----------------------------------------------------
# Same invariant the fastlane lane enforced: the checked-out build number must
# be exactly the next one TestFlight expects. scripts/beta.sh sets this before
# cutting the release that triggers CI. Override with ALLOW_BUILD_NUMBER_MISMATCH=1
# (e.g. to re-run a failed upload). Skipped when we have no ASC credentials.
elif [ -n "$app_id" ]; then
  next="$(asc builds next-build-number --app "$app_id" --platform IOS --output json \
    | jq -r '.nextBuildNumber')"
  echo "Current build number: $current"
  echo "Next build number:    $next"
  if [ "$current" != "$next" ] && [ "${ALLOW_BUILD_NUMBER_MISMATCH:-0}" != "1" ]; then
    echo "error: build number is $current, expected $next" >&2
    echo "       set ALLOW_BUILD_NUMBER_MISMATCH=1 to override" >&2
    exit 1
  fi
fi

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Archiving ($SCHEME $version ($current))"
run_xcodebuild \
  -project "$SCHEME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -skipPackagePluginValidation -skipMacroValidation \
  "${auth_args[@]}" \
  clean archive

echo "==> Exporting IPA"
rm -rf "$EXPORT_DIR"
run_xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  "${auth_args[@]}"

ipa="$(find "$EXPORT_DIR" -maxdepth 1 -name '*.ipa' | head -1)"
[ -n "$ipa" ] || { echo "error: no .ipa produced in $EXPORT_DIR" >&2; exit 1; }
echo "Exported: $ipa"

if [ "$upload" -eq 0 ]; then
  echo "==> --no-upload: stopping after export"
  exit 0
fi

[ -n "$app_id" ] || {
  echo "error: cannot upload — asc is not logged in (asc auth login) and no APP_STORE_CONNECT_* env" >&2
  exit 1
}

if [ "$asc_dry_run" -eq 1 ]; then
  echo "==> Reserving upload (dry-run, nothing is committed to TestFlight)"
  asc builds upload --app "$app_id" --ipa "$ipa" --dry-run
  exit 0
fi

# TestFlight "What to Test" text: a fixed header (scripts/testflight_test_notes_header.txt)
# followed by changelog.txt.
test_notes="$(printf '%s\n\n%s' "$(cat "$TEST_NOTES_HEADER")" "$(cat changelog.txt)")"

echo "==> Uploading to TestFlight (+ What to Test notes)"
asc builds upload \
  --app "$app_id" \
  --ipa "$ipa" \
  --test-notes "$test_notes" \
  --locale en-US \
  --wait
