default_port := '8000'
docs-serve port=default_port:
    uv run --with-requirements docs/requirements.txt mkdocs serve -o -a localhost:{{port}}

docs:
    uv run --with-requirements docs/requirements.txt mkdocs build

alias sv := set_version
set_version version:
  uv run bump.py version swift-paperless.xcodeproj/project.pbxproj {{version}}

alias sb := set_build
set_build number:
  uv run bump.py build swift-paperless.xcodeproj/project.pbxproj {{number}}

beta:
  fastlane beta

default_os := '18.3.1'
build os=default_os:
  #!/bin/bash
  xcodebuild -scheme swift-paperless -project ./swift-paperless.xcodeproj -configuration Release -destination platform\=iOS\ Simulator,OS\={{os}},name\=iPhone\ 16\ Pro | xcbeautify

_test_swift package:
  swift test --package-path {{package}}

test: (_test_swift "Common") (_test_swift "DataModel") (_test_swift "Networking")
  #!/bin/bash
  set -e
  set -o pipefail
  set -x
  xcodebuild -showdestinations -scheme swift-paperlessTests -project ./swift-paperless.xcodeproj
  xcodebuild test \
    -scheme swift-paperlessTests \
    -destination "platform=macOS,name=My Mac"\
    -skipPackagePluginValidation -skipMacroValidation \
    CODE_SIGN_IDENTITY="" \
    | xcbeautify

lint-format:
  swift-format format --in-place --recursive . --parallel

lint-whitespace:
  uv run .ci/lint.py whitespace

lint-eof:
  uv run .ci/lint.py eof

lint: lint-format lint-whitespace lint-eof

resolve-packages:
  xcodebuild -project swift-paperless.xcodeproj \
    -scheme swift-paperless \
    -resolvePackageDependencies | xcbeautify
