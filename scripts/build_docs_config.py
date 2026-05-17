#!/usr/bin/env python3
# /// script
# dependencies = [
#   "pyyaml",
#   "packaging",
# ]
# ///
"""Expand directory-style nav entries in mkdocs.yml for zensical.

Zensical does not run mkdocs-literate-nav, so the
`Title: some_dir/` shorthand renders as a single broken link. This script
reads `mkdocs.yml`, walks the `nav` tree, and replaces any entry whose
value is a string ending in `/` (and not `.md`) with an explicit list of
the `.md` files found under `<docs_dir>/<that_dir>/`. Files whose names
look like `vX.Y.Z*` are sorted by version, descending; otherwise files
are sorted alphabetically. The resulting config is written to stdout.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Any

import yaml
from packaging.version import InvalidVersion, Version

VERSION_RE = re.compile(r"^v(\d+(?:\.\d+)*)")


def _version_key(name: str) -> Version | None:
    m = VERSION_RE.match(name)
    if not m:
        return None
    try:
        return Version(m.group(1))
    except InvalidVersion:
        return None


def _expand_dir(rel_dir: str, docs_dir: Path) -> list[str]:
    rel = rel_dir.rstrip("/")
    target = docs_dir / rel
    if not target.is_dir():
        raise SystemExit(f"nav entry refers to missing directory: {target}")
    files = sorted(p.name for p in target.iterdir() if p.suffix == ".md")
    keys = [_version_key(n) for n in files]
    if files and all(k is not None for k in keys):
        files.sort(key=_version_key, reverse=True)
    return [f"{rel}/{name}" for name in files]


def _expand(item: Any, docs_dir: Path) -> Any:
    if isinstance(item, dict):
        out = {}
        for k, v in item.items():
            if isinstance(v, str) and v.endswith("/") and not v.endswith(".md"):
                out[k] = _expand_dir(v, docs_dir)
            else:
                out[k] = _expand(v, docs_dir)
        return out
    if isinstance(item, list):
        return [_expand(x, docs_dir) for x in item]
    return item


def main() -> None:
    src = Path("mkdocs.yml")
    config = yaml.safe_load(src.read_text())
    docs_dir = src.parent / config.get("docs_dir", "docs")
    config["nav"] = _expand(config.get("nav", []), docs_dir)
    yaml.safe_dump(config, sys.stdout, sort_keys=False)


if __name__ == "__main__":
    main()
