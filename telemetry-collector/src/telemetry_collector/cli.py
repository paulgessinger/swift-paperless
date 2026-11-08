from __future__ import annotations

from pathlib import Path
from typing import Annotated

import typer

from .report import open_readonly, render
from .schema import load_schema


def report(
    db: Annotated[Path, typer.Option(envvar="TELEMETRY_DB_PATH", help="SQLite database")] = Path("telemetry.sqlite3"),
    days: Annotated[int, typer.Option(help="Number of days to print")] = 7,
    channel: Annotated[str | None, typer.Option(help="Only this channel")] = None,
    until: Annotated[str | None, typer.Option(help="Last day (yyyy-MM-dd); default: latest in DB")] = None,
    schema_path: Annotated[Path | None, typer.Option(envvar="TELEMETRY_SCHEMA_PATH", help="Schema file")] = None,
) -> None:
    """Print per-day per-field counts, used/available ratios and the MAU estimate.

    Feature pings (including setup errors) are filed under the day they report,
    so the latest days keep filling in.
    """
    conn = open_readonly(db)
    try:
        typer.echo(render(conn, load_schema(schema_path), days=days, channel=channel, until=until), nl=False)
    finally:
        conn.close()


def main() -> None:
    typer.run(report)
