#!/usr/bin/env python3

import typer
import dotenv
from typing_extensions import Annotated
import requests
import time
from rich.console import Console
import contextlib
from collections.abc import Iterator
import zipfile
import tempfile
from pathlib import Path
import string_catalog

console = Console()

dotenv.load_dotenv()

CROWDIN_BASE_URL = "https://api.crowdin.com/api/v2"


def build_translations(session: requests.Session, project_id: str) -> int:
    url = f"{CROWDIN_BASE_URL}/projects/{project_id}/translations/builds"
    with console.status("Building translations"):
        response = session.post(url)
    response.raise_for_status()

    data = response.json()
    print(data)

    console.print(f"Build started with ID: {data['data']['id']}")
    build_id = data["data"]["id"]

    url = f"{CROWDIN_BASE_URL}/projects/{project_id}/translations/builds/{build_id}"

    with console.status("Waiting for build to complete"):
        while True:
            response = session.get(url)
            response.raise_for_status()
            data = response.json()
            if data["data"]["status"] == "finished":
                console.print("Build complete")
                return build_id
            time.sleep(1)


@contextlib.contextmanager
def download_translations(
    session: requests.Session, project_id: str, build_id: int
) -> Iterator[zipfile.ZipFile]:
    url = f"{CROWDIN_BASE_URL}/projects/{project_id}/translations/builds/{build_id}/download"

    with console.status("Downloading translations"):
        response = session.get(url)

    response.raise_for_status()
    data = response.json()
    download_url = data["data"]["url"]

    console.print(f"Download URL: {download_url}")

    with tempfile.TemporaryFile("wb+") as temp_file:
        with requests.get(download_url, stream=True) as response:
            response.raise_for_status()
            for chunk in response.iter_content(chunk_size=8192):
                temp_file.write(chunk)

        temp_file.flush()
        temp_file.seek(0)

        console.print("Translations downloaded")

        with zipfile.ZipFile(temp_file) as zip_file:
            yield zip_file


def extract_metadata(catalog: string_catalog.StringCatalog, output_dir: Path):
    locale_map = {
        "en": "en-US",
        "de": "de-DE",
        "nl": "nl-NL",
        "da": "da-DK",
        "pl": "pl-PL",
        "fr": "fr-FR",
    }
    for key, value in catalog.as_dict().items():
        print(key, value)
        for lang, string in value.items():
            locale_dir = output_dir / locale_map[lang]
            if not locale_dir.exists():
                locale_dir.mkdir(parents=True)
            output = locale_dir / f"{key}.txt"
            output.write_text(string)


root_dir = Path(__file__).parent.parent


def main(
    crowdin_token: Annotated[str, typer.Option(envvar="CROWDIN_TOKEN")],
    project_id: Annotated[str, typer.Option(envvar="CROWDIN_PROJECT_ID")],
    localizations_directory: Annotated[
        Path, typer.Option(exists=True, file_okay=False)
    ] = root_dir
    / "swift-paperless/Localization",
    fastlane_directory: Annotated[
        Path, typer.Option(exists=True, file_okay=False)
    ] = root_dir
    / "fastlane",
):
    session = requests.Session()
    session.headers["Authorization"] = f"Bearer {crowdin_token}"

    build_id = build_translations(session, project_id)

    extracted_files: list[Path] = []
    with download_translations(session, project_id, build_id) as translations:
        for member in translations.infolist():
            console.print(f"Extracting {member.filename}")

            if member.filename == "Metadata.xcstrings":
                with console.status("Handling Metadata.xcstrings"):
                    translations.extract(member, fastlane_directory)
                    target_file = fastlane_directory / member.filename
                    extracted_files.append(target_file)
                    catalog = string_catalog.load(target_file.read_text())
                    extract_metadata(catalog, fastlane_directory / "metadata")
            elif member.filename == "Screenshots.xcstrings":
                console.print("Handling Screenshots.xcstrings")
                translations.extract(member, fastlane_directory / "screenshots")
                extracted_files.append(
                    fastlane_directory / "screenshots" / member.filename
                )
            else:
                translations.extract(member, localizations_directory)
                extracted_files.append(localizations_directory / member.filename)

    for file in extracted_files:
        with file.open("r+") as f:
            content = f.read()
            f.seek(0)
            f.write(content.rstrip() + "\n")
            f.truncate()


if __name__ == "__main__":
    typer.run(main)
