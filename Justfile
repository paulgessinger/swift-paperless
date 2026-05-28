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

get-version:
  @grep -m1 'MARKETING_VERSION' {{version_xcconfig}} | sed 's/.*= //'

get-build:
  @grep -m1 'CURRENT_PROJECT_VERSION' {{version_xcconfig}} | sed 's/.*= //'

tag:
  #!/usr/bin/env bash
  version=$(just get-version)
  number=$(just get-build)
  tag="builds/v$version/$number"
  git tag $tag
  echo $tag

# Prepare a new TestFlight beta and trigger its upload (reimplements fastlane's
# `beta` lane). See scripts/beta.sh for the details.
beta:
  scripts/beta.sh

# Build, sign, and upload the beta to TestFlight without fastlane (reimplements
# the `beta_ci` lane; runs in CI on release). Pass through args, e.g.
# `just beta-ci --no-upload` to archive+export locally without uploading, or
# `just beta-ci --bump --dry-run` for a full local test at the next build number.
beta-ci *args:
  scripts/beta_ci.sh {{args}}

# Sends header + current_changelog.txt (emoji stripped) as the whatsNew for the
# given build. Override `version` (default: Version.xcconfig) and/or `notes` file
# (default: current_changelog.txt). Needs asc logged in or APP_STORE_CONNECT_*.
# Attach/fix TestFlight "What to Test" notes on an existing build (no rebuild).
set-test-notes build version='' notes='':
  scripts/set_test_notes.sh {{build}} {{version}} {{notes}}

# Manually (re)trigger the TestFlight upload workflow (.github/workflows/beta.yml)
# on GitHub Actions, without cutting a new release — e.g. to re-run a failed
# upload. Runs against `ref` (default main), whose committed build number is
# used. Pass `mismatch=true` to upload even if that build number isn't the next
# one TestFlight expects. Requires this workflow's workflow_dispatch trigger to
# already be on the default branch.
beta-run ref='main' mismatch='false':
  gh workflow run beta.yml --ref {{ref}} -f allow_build_number_mismatch={{mismatch}}
  @echo "Triggered — watch it with: gh run watch \$(gh run list --workflow beta.yml --limit 1 --json databaseId --jq '.[0].databaseId')"

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
