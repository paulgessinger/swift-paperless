#!/usr/bin/env python3

import yaml
import sys
from pathlib import Path
from typing import Dict, Any, List

file = Path(sys.argv[1])

with file.open() as fh:
    struct = yaml.safe_load(fh)

def format_key(key: str, path: List[str]) -> str:
    parts=key.split("_")
    parts[1:] = [part.capitalize() for part in parts[1:]]
    camel_case_key = "".join(parts)
    comment = f"\"{' '.join(path)}\""

    full_key = ".".join([p.lower() for p in path] + [key])

    return f'static let {camel_case_key} = String(localized: "{full_key}", comment: {comment})'

def process(node: Dict[str, Any], path: List[str]):
    for key, value in node.items():
        this_path = path + [key]

        enum = "".join([part.capitalize() for part in key.split("_")])
        print(f"enum {enum} {{")
        if isinstance(value, str):
            print(format_key(value, this_path))
        elif isinstance(value, list):
            for item in value:
                if isinstance(item, str):
                    print(format_key(item, this_path))
                elif isinstance(item, dict):
                    process(item, this_path)
        print("}")

process(struct, [])
