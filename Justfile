docs-serve:
    uv run --with-requirements docs/requirements.txt mkdocs serve -o -a localhost:8001

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
