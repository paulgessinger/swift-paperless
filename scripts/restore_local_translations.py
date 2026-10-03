#!/usr/bin/env python3
"""Re-add translations that exist in git but are missing after a Crowdin pull.

`crowdin pull` overwrites the String Catalogs with Crowdin's export, which drops
translations that were committed to the repo but never uploaded. This restores
each (key, language) entry from the catalog at REF when the pulled catalog has
no translation for it. Translations present on both sides keep Crowdin's value.

Prints the number of restored entries; with --github-output it also writes
`restored=<n>` to $GITHUB_OUTPUT.
"""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


def load_at_ref(ref: str, path: Path) -> dict | None:
    result = subprocess.run(
        ["git", "show", f"{ref}:{path.as_posix()}"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return None
    return json.loads(result.stdout)


def is_translated(entry: dict) -> bool:
    if "variations" in entry:
        return True
    return entry.get("stringUnit", {}).get("state") == "translated"


def restore(local: dict, pulled: dict, source_language: str) -> int:
    restored = 0
    for key, pulled_string in pulled.get("strings", {}).items():
        local_string = local.get("strings", {}).get(key)
        if local_string is None:
            continue
        pulled_locs = pulled_string.get("localizations", {})
        changed = False
        for lang, entry in local_string.get("localizations", {}).items():
            if lang == source_language or not is_translated(entry):
                continue
            if lang in pulled_locs and is_translated(pulled_locs[lang]):
                continue
            pulled_locs[lang] = entry
            restored += 1
            changed = True
        if changed:
            # Xcode keeps languages sorted; match it to avoid reorder churn.
            pulled_string["localizations"] = dict(sorted(pulled_locs.items()))
    return restored


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("catalogs", nargs="+", type=Path)
    parser.add_argument("--ref", default="HEAD")
    parser.add_argument("--github-output", action="store_true")
    args = parser.parse_args()

    total = 0
    for path in args.catalogs:
        local = load_at_ref(args.ref, path)
        if local is None:
            continue
        pulled = json.loads(path.read_text(encoding="utf-8"))
        count = restore(local, pulled, pulled.get("sourceLanguage", "en"))
        if count:
            path.write_text(
                json.dumps(
                    pulled, indent=2, separators=(",", " : "), ensure_ascii=False
                )
                + "\n",
                encoding="utf-8",
            )
            print(f"{path}: restored {count} translation(s)", file=sys.stderr)
        total += count

    print(total)
    if args.github_output:
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as f:
            f.write(f"restored={total}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
