#!/usr/bin/env python3

import sys
import json
import plistlib
from pathlib import Path
import subprocess

path = Path(sys.argv[1])

file = Path(
    subprocess.run(
        [
            "find",
            path,
            "-type",
            "f",
            "-name",
            "group.com.paulgessinger.swift-paperless.plist",
        ],
        capture_output=True,
    )
    .stdout.decode("utf-8")
    .strip()
)

print(file)

with file.open("rb") as f:
    plist = plistlib.load(f)

output = {}

for key, value in plist.items():
    if isinstance(value, bytes):
        value = value.decode("utf-8")
        output[key] = json.loads(value)
    else:
        output[key] = value

print(json.dumps(output, indent=2))
