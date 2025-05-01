docs-serve:
    uv run --with-requirements docs/requirements.txt mkdocs serve -o -a localhost:8001

docs:
    uv run --with-requirements docs/requirements.txt mkdocs build

bump version:
  uv run bump.py swift-paperless.xcodeproj/project.pbxproj {{version}}

beta:
  fastlane beta

default_os := '18.3.1'
build os=default_os:
  #!/bin/bash
  xcodebuild -scheme swift-paperless -project ./swift-paperless.xcodeproj -configuration Release -destination platform\=iOS\ Simulator,OS\={{os}},name\=iPhone\ 16\ Pro | xcbeautify
