#!/usr/bin/env python

# /// script
# dependencies = [
#   "rich",
#   "typer",
# ]
# ///

import re
from pathlib import Path
from typing import Annotated

import typer

app = typer.Typer()


@app.command()
def version(
    file: Annotated[Path, typer.Argument(help="Path to Version.xcconfig")],
    version: Annotated[str, typer.Argument(help="New marketing version, e.g. 1.10.0")],
):
    raw = file.read_text()

    # validate version
    if m := re.match(r"v?(\d+\.\d+\.\d+)", version):
        version = m.group(1)
    else:
        raise ValueError(f"Invalid version: {version}")

    bumped = re.sub(
        r"MARKETING_VERSION ?= ?\d+\.\d+\.\d+",
        f"MARKETING_VERSION = {version}",
        raw,
    )

    file.write_text(bumped)


@app.command()
def build(
    file: Annotated[Path, typer.Argument(help="Path to Version.xcconfig")],
    number: Annotated[int, typer.Argument(help="New build number")],
):
    raw = file.read_text()

    bumped = re.sub(
        r"CURRENT_PROJECT_VERSION ?= ?\d+",
        f"CURRENT_PROJECT_VERSION = {number}",
        raw,
    )

    file.write_text(bumped)


app()
