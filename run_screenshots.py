#!/usr/bin/env python3
# /// script
# dependencies = [
#   "rich",
#   "typer",
# ]
# ///

from dataclasses import dataclass
from pathlib import Path
import subprocess
import time

import typer
from rich.console import Console
from rich.table import Table

app = typer.Typer(no_args_is_help=True)
console = Console()


@dataclass(frozen=True)
class ScreenshotStep:
    name: str
    url: str | None = None
    post_url: str | None = None
    wait: float | None = None


DEFAULT_STEPS = [
    ScreenshotStep("documents"),
    ScreenshotStep(
        "filter_tags",
        "x-paperless://v1/open_filter/tags",
        "x-paperless://v1/close_filter",
    ),
    ScreenshotStep("document_view", "x-paperless://v1/document/3?edit=0"),
    ScreenshotStep("document_edit", "x-paperless://v1/document/3?edit=1", wait=4),
]


def sanitize_filename(value: str) -> str:
    return "".join(
        character if character.isalnum() or character in "-_" else "_"
        for character in value
    )


def run_command(args: list[str], *, check: bool = True, dry_run: bool = False) -> None:
    display = " ".join(args)
    console.log(f"[bold blue]$ {display}[/bold blue]")
    if dry_run:
        return
    subprocess.run(args, check=check)


def simctl(args: list[str], *, check: bool = True, dry_run: bool = False) -> None:
    run_command(["xcrun", "simctl", *args], check=check, dry_run=dry_run)


def parse_steps(raw_steps: list[str]) -> list[ScreenshotStep]:
    if not raw_steps:
        return DEFAULT_STEPS
    steps: list[ScreenshotStep] = []
    for raw_step in raw_steps:
        wait: float | None = None
        base_step = raw_step
        name_and_url, wait_separator, wait_value = raw_step.rpartition("@")
        if wait_separator:
            try:
                wait = float(wait_value)
                base_step = name_and_url
            except ValueError:
                base_step = raw_step
        name, separator, url = base_step.partition("=")
        name = name.strip()
        url = url.strip() if separator else None
        if not name:
            raise typer.BadParameter("Step name cannot be empty.")
        steps.append(ScreenshotStep(name=name, url=url or None, wait=wait))
    return steps


def display_plan(languages: list[str], steps: list[ScreenshotStep]) -> None:
    table = Table(title="Screenshot plan", header_style="bold magenta")
    table.add_column("Language")
    table.add_column("Screens")
    step_names = ", ".join(
        f"{step.name}@{step.wait:g}s" if step.wait is not None else step.name
        for step in steps
    )
    for language in languages:
        table.add_row(language, step_names)
    console.print(table)


def configure_simulator(
    *,
    status_bar_time: str,
    status_bar_cellular_bars: int,
    appearance: str,
    dry_run: bool,
) -> None:
    simctl(["ui", "booted", "appearance", appearance], dry_run=dry_run)
    simctl(
        [
            "status_bar",
            "booted",
            "override",
            "--time",
            status_bar_time,
            "--cellularBars",
            str(status_bar_cellular_bars),
        ],
        dry_run=dry_run,
    )


@app.command()
def main(
    languages: list[str] = typer.Option(
        ["en-US"],
        "--language",
        "-l",
        help="Language tags to capture. Repeat for multiple.",
    ),
    output_dir: Path = typer.Option(
        Path("screenshots"),
        "--output-dir",
        "-o",
        help="Directory to write screenshots.",
    ),
    bundle_id: str = typer.Option(
        "com.paulgessinger.swift-paperless",
        "--bundle-id",
        help="App bundle identifier.",
    ),
    launch_wait: float = typer.Option(
        2.0,
        "--launch-wait",
        help="Seconds to wait after launching the app.",
    ),
    url_wait: float = typer.Option(
        2.0,
        "--url-wait",
        help="Seconds to wait after opening a URL.",
    ),
    status_bar_time: str = typer.Option(
        "2007-01-09T09:41:00.000+01:00",
        "--status-bar-time",
        help="Status bar clock time in ISO 8601 format.",
    ),
    status_bar_cellular_bars: int = typer.Option(
        4,
        "--status-bar-cellular-bars",
        min=0,
        max=4,
        help="Status bar cellular signal strength (0-4).",
    ),
    appearance: str = typer.Option(
        "light",
        "--appearance",
        help="Simulator appearance mode (light or dark).",
    ),
    steps: list[str] = typer.Option(
        [],
        "--step",
        help="Screenshot step (name or name=url[@wait]). Repeat for multiple.",
    ),
    dry_run: bool = typer.Option(
        False,
        "--dry-run",
        help="Print commands without running simctl.",
    ),
) -> None:
    screenshot_steps = parse_steps(steps)
    output_dir.mkdir(parents=True, exist_ok=True)
    display_plan(languages, screenshot_steps)
    configure_simulator(
        status_bar_time=status_bar_time,
        status_bar_cellular_bars=status_bar_cellular_bars,
        appearance=appearance,
        dry_run=dry_run,
    )

    for language in languages:
        language_slug = sanitize_filename(language)
        language_dir = output_dir / language_slug
        language_dir.mkdir(parents=True, exist_ok=True)
        console.rule(f"[bold green]Language: {language}")
        simctl(["terminate", "booted", bundle_id], check=False, dry_run=dry_run)
        simctl(
            [
                "launch",
                "booted",
                bundle_id,
                "-AppleLanguages",
                f"({language})",
                "-AppleLocale",
                language,
            ],
            dry_run=dry_run,
        )
        if launch_wait > 0:
            time.sleep(launch_wait)

        for index, step in enumerate(screenshot_steps, start=1):
            wait_time = step.wait if step.wait is not None else url_wait
            if step.url:
                simctl(["openurl", "booted", step.url], dry_run=dry_run)
                if wait_time > 0:
                    time.sleep(wait_time)
            elif step.wait is not None and wait_time > 0:
                time.sleep(wait_time)
            screenshot_name = f"{index:02d}_{sanitize_filename(step.name)}.png"
            output_path = language_dir / screenshot_name
            simctl(
                ["io", "booted", "screenshot", "--type", "png", str(output_path)],
                dry_run=dry_run,
            )
            console.log(f"Saved {output_path}")
            if step.post_url:
                simctl(["openurl", "booted", step.post_url], dry_run=dry_run)
                if wait_time > 0:
                    time.sleep(wait_time)


if __name__ == "__main__":
    app()
