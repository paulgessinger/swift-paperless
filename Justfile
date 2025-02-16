docs-serve:
    uv run --with-requirements docs/requirements.txt mkdocs serve -o -a localhost:8001

docs:
    uv run --with-requirements docs/requirements.txt mkdocs build
