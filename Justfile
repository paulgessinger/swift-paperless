# Homebrew's Ruby is keg-only (not on PATH by default). fastlane's gems are
# installed under it, so put it first for every recipe — otherwise `bundle`
# resolves to the EOL system Ruby 2.6 and fails to find the gems.
export PATH := '/opt/homebrew/opt/ruby/bin:' + env_var('PATH')

default_port := '8000'

zensical := "uv run --with-requirements docs/requirements.txt zensical"

docs-serve port=default_port:
  {{zensical}} serve -o -a localhost:{{port}}

docs:
  {{zensical}} build
  rm -f site/requirements.in site/requirements.txt
  mkdir -p site/release_notes/md
  cp docs/release_notes/*.md site/release_notes/md

version_xcconfig := 'Config/Shared/Version.xcconfig'

# Generate swift-paperless.xcodeproj from project.yml (it is gitignored).
alias g := generate
generate:
  xcodegen generate

alias o := open
open: generate
  open swift-paperless.xcodeproj


alias sv := set_version
set_version version:
  uv run bump.py version {{version_xcconfig}} {{version}}

alias sb := set_build
set_build number:
  uv run bump.py build {{version_xcconfig}} {{number}}

# Anchored at the line start so the comments naming these settings are skipped.
get-version:
  @grep -m1 '^MARKETING_VERSION' {{version_xcconfig}} | sed 's/.*= //'

get-build:
  @grep -m1 '^CURRENT_PROJECT_VERSION' {{version_xcconfig}} | sed 's/.*= //'

# Cut a TestFlight beta: previews the notes it will publish, then dispatches
# .github/workflows/beta.yml. Nothing is committed, pushed, or built locally —
# CI takes the build number from App Store Connect and tags the result. Args are
# passed to scripts/beta.sh, e.g. `just beta --ref develop/v1.12 --dry-run`.
beta *args:
  scripts/beta.sh {{args}}

# The build+sign+upload half of `just beta`, as run by CI. Locally useful for
# `just beta-ci --no-upload` (archive+export only) or `just beta-ci --dry-run`
# (adds `asc builds upload --dry-run`). Neither uploads or tags anything.
beta-ci *args:
  scripts/beta_ci.sh {{args}}

# The notes the next beta from `ref` would publish (bullets added to
# current_changelog.txt since the last build tag).
beta-notes ref='HEAD':
  scripts/changelog.py delta {{ref}}

# Regenerate changelog.txt — the offline copy of the per-build TestFlight notes —
# from the build prereleases on GitHub.
changelog-archive:
  scripts/changelog.py archive

# Attach/fix TestFlight "What to Test" notes on an existing build (no rebuild).
# Sends header + current_changelog.txt (emoji stripped) as the whatsNew for the
# given build. Override `version` (default: Version.xcconfig) and/or `notes` file
# (default: current_changelog.txt). Needs asc logged in or APP_STORE_CONNECT_*.
set-test-notes build version='' notes='':
  scripts/set_test_notes.sh {{build}} {{version}} {{notes}}

# Upload metadata + framed screenshots (no IPA). Replaces all screenshots on ASC.
deliver:
  #!/usr/bin/env bash
  set -euo pipefail
  bundle exec fastlane deliver \
    --metadata_path fastlane/metadata \
    --overwrite_screenshots \
    --app_version "$(just get-version)" \
    --force

# Metadata only (release notes, description, …) — no screenshots.
deliver-metadata:
  #!/usr/bin/env bash
  set -euo pipefail
  bundle exec fastlane deliver \
    --metadata_path fastlane/metadata \
    --skip_screenshots \
    --app_version "$(just get-version)" \
    --force

# Dry run for `just deliver`.
deliver-preview:
  #!/usr/bin/env bash
  set -euo pipefail
  bundle exec fastlane deliver \
    --metadata_path fastlane/metadata \
    --preview \
    --overwrite_screenshots \
    --app_version "$(just get-version)" \
    --force

default_os := '26.2'
default_device := 'iPhone 17 Pro'
build os=default_os device=default_device: generate
  #!/usr/bin/env bash
  xcodebuild -scheme swift-paperless -project ./swift-paperless.xcodeproj -configuration Release -destination "platform=iOS Simulator,OS={{os}},name={{device}}" | xcbeautify

_test_swift package:
  swift test --package-path {{package}}

# Host-runnable package tests (Common, DataModel, Networking, Persistence) run
# natively on macOS via `swift test`. AppShared is iOS-only and has no test
# target of its own.
test: (_test_swift "Common") (_test_swift "DataModel") (_test_swift "Networking") (_test_swift "Persistence")

lint-format:
  find . -name '*.swift' \
    -not -path '*/.git/*' -not -path '*/.build/*' -not -path '*/vendor/*' \
    | parallel swift-format format --in-place {}

lint-whitespace:
  uv run .ci/lint.py whitespace

lint-eof:
  uv run .ci/lint.py eof

lint: lint-format lint-whitespace lint-eof

resolve-packages: generate
  xcodebuild -project swift-paperless.xcodeproj \
    -scheme swift-paperless \
    -resolvePackageDependencies | xcbeautify

demo-up:
  uv run --project scripts swpngx capture setup

demo-down:
  uv run --project scripts swpngx capture teardown
