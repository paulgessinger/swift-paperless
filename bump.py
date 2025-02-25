#!/usr/bin/env python

# /// script
# dependencies = [
#   "rich",
#   "typer",
# ]
# ///

import typer
from pathlib import Path
import re

app = typer.Typer()


@app.command()
def bump(file: Path, version: str):
    raw = file.read_text()

    # validate version
    if m := re.match(r"v?(\d+\.\d+\.\d+)", version):
        version = m.group(1)
    else:
        raise ValueError(f"Invalid version: {version}")

    bumped = re.sub(
        r"MARKETING_VERSION ?= ?\d+\.\d+\.\d+;", f"MARKETING_VERSION = {version};", raw
    )

    file.write_text(bumped)


app()
