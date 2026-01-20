#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "llm",
#     "typer",
#     "rich",
# ]
# ///
"""
Translate fastlane metadata and StoreKit files using the llm library.

Usage:
    uv run translate_metadata.py [OPTIONS]
    uv run translate_metadata.py --help

Setup:
    Configure your model with llm (see: https://llm.datasette.io/)
"""

from __future__ import annotations

import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Annotated, Any

import typer
from rich import print as rprint
from rich.console import Console
from rich.panel import Panel
from rich.progress import Progress, SpinnerColumn, TextColumn
from rich.table import Table

try:
    import llm
except ImportError:
    rprint(
        "[red]Error:[/red] llm library not installed. Run: [cyan]pip install llm[/cyan]"
    )
    sys.exit(1)


# Configuration
METADATA_DIR = Path(__file__).parent.parent / "fastlane" / "metadata"
SOURCE_DIR = METADATA_DIR / "default"
STOREKIT_FILE = Path(__file__).parent.parent / "swift-paperless" / "Testing.storekit"

# Files to translate (these contain localizable content)
TRANSLATABLE_FILES = [
    "description.txt",
    "subtitle.txt",
    "keywords.txt",
    # "release_notes.txt",
]

# Files that should NOT be translated (app name, URLs, categories)
NON_TRANSLATABLE_FILES = [
    "name.txt",
    "marketing_url.txt",
    "privacy_url.txt",
    "support_url.txt",
]

# Default target languages with their locale codes
# Format: locale_code -> language_name
DEFAULT_TARGET_LANGUAGES = {
    "de-DE": "German",
    "fr-FR": "French",
    "it": "Italian",
    "nl-NL": "Dutch",
    "pl": "Polish",
    "da": "Danish",
    "tr": "Turkish",
}

# Mapping from fastlane locale codes to StoreKit locale codes
STOREKIT_LOCALE_MAP = {
    "de-DE": "de",
    "fr-FR": "fr",
    "it": "it",
    "nl-NL": "nl",
    "pl": "pl",
    "da": "da",
    "tr": "tr",
}

# Default model (configured via llm)
DEFAULT_MODEL = "gpt-oss-20b-mlx"

app = typer.Typer(
    help="Translate fastlane metadata using llm",
    rich_markup_mode="rich",
    no_args_is_help=False,
)
console = Console()


@dataclass
class TranslationConfig:
    """Configuration for translation."""

    target_languages: dict[str, str]
    model_name: str
    dry_run: bool
    verbose: bool
    overwrite: bool


def get_translation_prompt(content: str, target_language: str, file_type: str) -> str:
    """Generate a prompt for translation."""
    context = ""
    if file_type == "description.txt":
        context = "This is an App Store description for a document management iOS app."
    elif file_type == "subtitle.txt":
        context = "This is an App Store subtitle (max 30 characters)."
    elif file_type == "keywords.txt":
        context = (
            "These are App Store keywords, comma-separated. Keep them comma-separated."
        )
    elif file_type == "release_notes.txt":
        context = "These are release notes for an app update. Each line starting with '-' is a separate item."

    return f"""Translate the following text to {target_language}. {context}

Important:
- Preserve the exact formatting (line breaks, bullet points, etc.)
- Do not add any explanations or notes
- Only output the translated text
- Keep technical terms like "Paperless-ngx", "SwiftPaperless", "iOS" unchanged
- For keywords, keep them comma-separated

Text to translate:
{content}"""


def get_model(model_name: str) -> llm.Model:
    """Get the configured LLM model."""
    try:
        return llm.get_model(model_name)
    except llm.UnknownModelError:
        rprint(f"[red]Error:[/red] Model '[cyan]{model_name}[/cyan]' not found.")
        rprint()
        rprint("[dim]Available models:[/dim]")
        for m in llm.get_models():
            rprint(f"  [cyan]{m.model_id}[/cyan]")
        raise typer.Exit(1)


def translate_text(
    model: llm.Model, content: str, target_language: str, file_type: str
) -> str:
    """Translate text using the LLM model."""
    prompt = get_translation_prompt(content, target_language, file_type)
    response = model.prompt(prompt)
    return response.text().strip()


def translate_file(
    model: llm.Model,
    source_file: Path,
    target_dir: Path,
    target_language: str,
    config: TranslationConfig,
) -> tuple[bool, str]:
    """Translate a single file. Returns (success, status_message)."""
    target_file = target_dir / source_file.name

    # Check if target already exists
    if target_file.exists() and not config.overwrite:
        return False, "skipped (exists)"

    # Read source content
    content = source_file.read_text().strip()
    if not content:
        return False, "skipped (empty)"

    if config.dry_run:
        return True, "would translate"

    # Translate
    translated = translate_text(model, content, target_language, source_file.name)

    # Write to target
    target_file.write_text(translated + "\n")

    return True, "translated"


def translate_to_language(
    model: llm.Model | None,
    locale_code: str,
    language_name: str,
    config: TranslationConfig,
    progress: Progress | None = None,
) -> int:
    """Translate all files to a specific language."""
    target_dir = METADATA_DIR / locale_code

    if not config.dry_run:
        target_dir.mkdir(parents=True, exist_ok=True)

    translated_count = 0
    for file_name in TRANSLATABLE_FILES:
        source_file = SOURCE_DIR / file_name
        if source_file.exists():
            if progress:
                progress.update(
                    progress.task_ids[0],
                    description=f"[cyan]{language_name}[/cyan]: {file_name}",
                )

            success, status = translate_file(
                model, source_file, target_dir, language_name, config
            )

            if config.verbose or config.dry_run:
                status_color = "green" if success else "dim"
                rprint(f"  [{status_color}]{file_name}: {status}[/{status_color}]")

            if success:
                translated_count += 1

    return translated_count


def get_storekit_prompt(content: str, target_language: str, field_type: str) -> str:
    """Generate a prompt for StoreKit product translation."""
    context = f"This is a {field_type} for an in-app purchase product (tip jar)."

    return f"""Translate the following text to {target_language}. {context}

Important:
- Do not add any explanations or notes
- Only output the translated text
- Keep it concise and natural for an app store product

Text to translate:
{content}"""


def translate_storekit_text(
    model: llm.Model, content: str, target_language: str, field_type: str
) -> str:
    """Translate StoreKit product text using the LLM model."""
    prompt = get_storekit_prompt(content, target_language, field_type)
    response = model.prompt(prompt)
    return response.text().strip()


def translate_storekit(
    model: llm.Model | None,
    target_languages: dict[str, str],
    config: TranslationConfig,
) -> int:
    """Translate StoreKit product localizations."""
    if not STOREKIT_FILE.exists():
        rprint(f"[yellow]Warning:[/yellow] StoreKit file not found: {STOREKIT_FILE}")
        return 0

    # Read the StoreKit file
    with open(STOREKIT_FILE) as f:
        storekit_data: dict[str, Any] = json.load(f)

    products = storekit_data.get("products", [])
    if not products:
        rprint("[yellow]Warning:[/yellow] No products found in StoreKit file")
        return 0

    translated_count = 0

    for product in products:
        product_name = product.get("referenceName", product.get("productID", "unknown"))
        localizations: list[dict[str, str]] = product.get("localizations", [])

        # Find English source
        en_loc = next(
            (loc for loc in localizations if loc.get("locale") == "en_US"), None
        )
        if not en_loc:
            if config.verbose or config.dry_run:
                rprint(f"  [dim]{product_name}: skipped (no English source)[/dim]")
            continue

        source_name = en_loc.get("displayName", "")
        source_desc = en_loc.get("description", "")

        if not source_name:
            if config.verbose or config.dry_run:
                rprint(f"  [dim]{product_name}: skipped (empty displayName)[/dim]")
            continue

        # Get existing locales
        existing_locales = {loc.get("locale") for loc in localizations}

        for fastlane_code, language_name in target_languages.items():
            storekit_locale = STOREKIT_LOCALE_MAP.get(fastlane_code)
            if not storekit_locale:
                continue

            # Check if already exists
            if storekit_locale in existing_locales and not config.overwrite:
                if config.verbose or config.dry_run:
                    rprint(
                        f"  [dim]{product_name} ({storekit_locale}): skipped (exists)[/dim]"
                    )
                continue

            if config.dry_run:
                rprint(
                    f"  [green]{product_name} ({storekit_locale}): would translate[/green]"
                )
                translated_count += 1
                continue

            # Translate
            translated_name = translate_storekit_text(
                model, source_name, language_name, "product display name"
            )
            translated_desc = ""
            if source_desc:
                translated_desc = translate_storekit_text(
                    model, source_desc, language_name, "product description"
                )

            # Update or add localization
            existing_loc = next(
                (loc for loc in localizations if loc.get("locale") == storekit_locale),
                None,
            )
            if existing_loc:
                existing_loc["displayName"] = translated_name
                existing_loc["description"] = translated_desc
            else:
                localizations.append(
                    {
                        "description": translated_desc,
                        "displayName": translated_name,
                        "locale": storekit_locale,
                    }
                )

            if config.verbose or config.dry_run:
                rprint(
                    f"  [green]{product_name} ({storekit_locale}): translated[/green]"
                )
            translated_count += 1

    # Write back the file
    if not config.dry_run and translated_count > 0:
        with open(STOREKIT_FILE, "w") as f:
            json.dump(storekit_data, f, indent=2, ensure_ascii=False)
            f.write("\n")

    return translated_count


def parse_languages(lang_strings: list[str]) -> dict[str, str]:
    """Parse language string into dict of locale_code -> language_name."""
    languages = {}
    for lang in lang_strings:
        lang = lang.strip()
        if not lang:
            continue

        # Check if it's a known locale code
        if lang in DEFAULT_TARGET_LANGUAGES:
            languages[lang] = DEFAULT_TARGET_LANGUAGES[lang]
        else:
            # Assume it's a language name, try to find the locale
            found = False
            for code, name in DEFAULT_TARGET_LANGUAGES.items():
                if name.lower() == lang.lower():
                    languages[code] = name
                    found = True
                    break

            if not found:
                # Use as both code and name
                languages[lang] = lang.title()

    return languages


@app.command("list")
def list_languages() -> None:
    """List available default languages."""
    table = Table(title="Available Languages")
    table.add_column("Locale Code", style="cyan")
    table.add_column("Language", style="green")
    table.add_column("Status", style="dim")

    for code, name in DEFAULT_TARGET_LANGUAGES.items():
        existing = (METADATA_DIR / code).exists()
        status = "exists" if existing else ""
        table.add_row(code, name, status)

    console.print(table)


@app.command("translate")
def translate(
    languages: Annotated[
        list[str],
        typer.Option(
            "--languages",
            "-l",
            help="Target languages (locale codes or names)",
        ),
    ] = ["de-DE", "fr-FR", "it", "nl-NL", "pl", "da", "tr"],
    model: Annotated[
        str,
        typer.Option(
            "--model",
            "-m",
            help="LLM model alias to use",
        ),
    ] = DEFAULT_MODEL,
    dry_run: Annotated[
        bool,
        typer.Option(
            "--dry-run",
            "-n",
            help="Preview translations without writing files",
        ),
    ] = False,
    overwrite: Annotated[
        bool,
        typer.Option(
            "--overwrite",
            "-f",
            help="Overwrite existing translation files",
        ),
    ] = False,
    verbose: Annotated[
        bool,
        typer.Option(
            "--verbose",
            "-v",
            help="Show detailed progress",
        ),
    ] = False,
) -> None:
    """Translate fastlane metadata files to target languages."""
    # Check source directory
    if not SOURCE_DIR.exists():
        rprint(
            f"[red]Error:[/red] Source directory not found: [cyan]{SOURCE_DIR}[/cyan]"
        )
        raise typer.Exit(1)

    # Parse target languages
    if languages:
        target_languages = parse_languages(languages)
    else:
        target_languages = DEFAULT_TARGET_LANGUAGES.copy()

    if not target_languages:
        rprint("[red]Error:[/red] No valid target languages specified")
        raise typer.Exit(1)

    config = TranslationConfig(
        target_languages=target_languages,
        model_name=model,
        dry_run=dry_run,
        verbose=verbose,
        overwrite=overwrite,
    )

    # Display configuration
    lang_list = ", ".join(
        f"[cyan]{n}[/cyan] ({c})" for c, n in target_languages.items()
    )
    panel_content = f"""[bold]Source:[/bold] {SOURCE_DIR}
[bold]Languages:[/bold] {lang_list}
[bold]Model:[/bold] [cyan]{config.model_name}[/cyan]"""

    if config.dry_run:
        panel_content += "\n[yellow](Dry run - no files will be written)[/yellow]"

    console.print(
        Panel(panel_content, title="Translation Configuration", border_style="blue")
    )

    # Set up the model
    llm_model: llm.Model | None = None
    if not config.dry_run:
        with console.status("[bold green]Loading model..."):
            llm_model = get_model(config.model_name)
        rprint(f"[green]Using model:[/green] [cyan]{config.model_name}[/cyan]\n")

    # Translate to each language
    total_translated = 0

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        console=console,
        transient=not (verbose or config.dry_run),
    ) as progress:
        task = progress.add_task("Translating...", total=None)

        for locale_code, language_name in target_languages.items():
            progress.update(
                task, description=f"[bold]{language_name}[/bold] ({locale_code})"
            )

            if verbose or config.dry_run:
                rprint(f"\n[bold blue]{language_name}[/bold blue] ({locale_code}):")

            count = translate_to_language(
                llm_model,
                locale_code,
                language_name,
                config,
                progress if not (verbose or config.dry_run) else None,
            )
            total_translated += count

    # Summary
    rprint()
    if total_translated > 0:
        rprint(
            f"[green]Done![/green] Translated [bold]{total_translated}[/bold] file(s)."
        )
    else:
        rprint(
            "[yellow]No files were translated.[/yellow] Use [cyan]--overwrite[/cyan] to replace existing translations."
        )


@app.command("storekit")
def storekit_cmd(
    languages: Annotated[
        list[str],
        typer.Option(
            "--languages",
            "-l",
            help="Target languages (locale codes or names)",
        ),
    ] = ["de-DE", "fr-FR", "it", "nl-NL", "pl", "da", "tr"],
    model: Annotated[
        str,
        typer.Option(
            "--model",
            "-m",
            help="LLM model alias to use",
        ),
    ] = DEFAULT_MODEL,
    dry_run: Annotated[
        bool,
        typer.Option(
            "--dry-run",
            "-n",
            help="Preview translations without writing files",
        ),
    ] = False,
    overwrite: Annotated[
        bool,
        typer.Option(
            "--overwrite",
            "-f",
            help="Overwrite existing translations",
        ),
    ] = False,
    verbose: Annotated[
        bool,
        typer.Option(
            "--verbose",
            "-v",
            help="Show detailed progress",
        ),
    ] = False,
) -> None:
    """Translate StoreKit product localizations only."""
    # Parse target languages
    if languages:
        target_languages = parse_languages(languages)
    else:
        target_languages = DEFAULT_TARGET_LANGUAGES.copy()

    if not target_languages:
        rprint("[red]Error:[/red] No valid target languages specified")
        raise typer.Exit(1)

    config = TranslationConfig(
        target_languages=target_languages,
        model_name=model,
        dry_run=dry_run,
        verbose=verbose,
        overwrite=overwrite,
    )

    # Display configuration
    lang_list = ", ".join(
        f"[cyan]{n}[/cyan] ({c})" for c, n in target_languages.items()
    )
    panel_content = f"""[bold]StoreKit file:[/bold] {STOREKIT_FILE}
[bold]Languages:[/bold] {lang_list}
[bold]Model:[/bold] [cyan]{config.model_name}[/cyan]"""

    if config.dry_run:
        panel_content += "\n[yellow](Dry run - no files will be written)[/yellow]"

    console.print(
        Panel(panel_content, title="StoreKit Translation", border_style="magenta")
    )

    # Set up the model
    llm_model: llm.Model | None = None
    if not config.dry_run:
        with console.status("[bold green]Loading model..."):
            llm_model = get_model(config.model_name)
        rprint(f"[green]Using model:[/green] [cyan]{config.model_name}[/cyan]\n")

    # Translate StoreKit products
    if verbose or config.dry_run:
        rprint("[bold magenta]StoreKit Products:[/bold magenta]")

    storekit_count = translate_storekit(llm_model, target_languages, config)

    # Summary
    rprint()
    if storekit_count > 0:
        rprint(
            f"[green]Done![/green] Translated [bold]{storekit_count}[/bold] StoreKit product localization(s)."
        )
    else:
        rprint(
            "[yellow]No products were translated.[/yellow] Use [cyan]--overwrite[/cyan] to replace existing translations."
        )


@app.callback(invoke_without_command=True)
def main(
    ctx: typer.Context,
) -> None:
    """Translate fastlane metadata and StoreKit files using llm."""
    if ctx.invoked_subcommand is None:
        # Default to translate command
        ctx.invoke(translate)


if __name__ == "__main__":
    app()
