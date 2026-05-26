#!/usr/bin/env python3

# /// script
# dependencies = [
#   "requests",
#   "types-requests",
#   "rich",
#   "typer",
# ]
# ///

import re
import sys
import requests
from typing import List
from pathlib import Path
from typer import Typer

app = Typer()


def extract_links(file_path: str, base_url: str | None) -> List[str]:
    with open(file_path, "r") as f:
        content = f.read()

    # Find all URLs in the format: URL(string: "...")
    pattern = r'URL\(string:\s*"([^"]+)"\)'
    base_urls = re.findall(pattern, content)

    # Find all .appending(path: "...") calls
    pattern = r'\.appending\(path:\s*"([^"]+)"\)'
    paths = re.findall(pattern, content)

    # Combine base URL with paths
    if not base_urls:
        print("Error: No base URL found")
        sys.exit(1)

    if base_url is None:
        base_url = base_urls[0]

    urls = [base_url]
    urls.extend(f"{base_url}/{path}" for path in paths)

    return urls


def validate_urls(urls: List[str]) -> None:
    failed = False
    for url in urls:
        try:
            response = requests.get(url)
            if response.status_code != 200:
                print(f"❌ {url} returned status code {response.status_code}")
                failed = True
            else:
                print(f"✅ {url}")
        except requests.RequestException as e:
            print(f"❌ {url} failed with error: {str(e)}")
            failed = True

    if failed:
        sys.exit(1)


script_dir = Path(__file__).parent.parent


@app.command()
def main(
    base_url: str | None = None,
    links_file: Path = script_dir
    / "swift-paperless"
    / "Utilities"
    / "DocumentationLinks.swift",
):
    if not links_file.exists():
        print(f"Error: Could not find {links_file}")
        sys.exit(1)

    urls = extract_links(str(links_file), base_url)
    validate_urls(urls)


if __name__ == "__main__":
    app()
