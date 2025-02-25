docs-serve:
    uv run --with-requirements docs/requirements.txt mkdocs serve -o -a localhost:8001

docs:
    uv run --with-requirements docs/requirements.txt mkdocs build

bump version:
  uv run bump.py swift-paperless.xcodeproj/project.pbxproj {{version}}
