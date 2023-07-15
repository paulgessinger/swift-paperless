#!/usr/bin/env python3
import sys
from subprocess import check_output
import re

last_tag = sys.argv[1]

commits = (
    check_output(
        [
            "git",
            "log",
            #  "--no-merges",
            "--pretty=format:%s",
            last_tag + "..HEAD",
        ]
    )
    .decode("utf-8")
    .split("\n")
)

groups = {
    "feat": [],
    "fix": [],
    "refactor": [],
}

group_names = {
    "feat": "Features",
    "fix": "Bug Fixes",
    "refactor": "Refactors",
}

for commit in commits:
    m = re.match(r"^(\w+): ?(.+)$", commit)
    if m is None:
        continue

    category, message = m.groups()

    if category in groups:
        groups[category].append(message)

for category, messages in groups.items():
    if len(messages) > 0:
        print(f"# {group_names[category]}")
        for message in messages:
            print(f"- {message}")
