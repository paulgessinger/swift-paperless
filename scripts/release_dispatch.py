#!/usr/bin/env python3
"""Build and upload a source ref through the shared TestFlight CI workflow."""

import argparse
import base64
import json
import os
import re
import subprocess
import sys
from urllib.parse import quote

REPOSITORY = "paulgessinger/swift-paperless"


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def github(repo, path):
    return json.loads(run("gh", "api", f"repos/{repo}/{path}"))


def resolve(repo, ref):
    return github(repo, f"commits/{quote(ref, safe='')}")["sha"]


def contents(repo, sha, path):
    data = github(repo, f"contents/{path}?ref={sha}")
    return base64.b64decode(data["content"]).decode()


def marketing_version(config):
    match = re.search(r"^MARKETING_VERSION\s*=\s*(\S+)\s*$", config, re.MULTILINE)
    if not match:
        raise ValueError("No MARKETING_VERSION in source Version.xcconfig")
    return match[1]


def build_number(value):
    if not re.fullmatch(r"[1-9]\d*", value):
        raise argparse.ArgumentTypeError("Build number must be a positive integer")
    return value


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument(
        "--ref",
        default="main",
        help="Application source branch, tag, or commit on GitHub",
    )
    result.add_argument("--build-number", type=build_number)
    result.add_argument("--repo", default=os.environ.get("GH_REPO", REPOSITORY))
    result.add_argument(
        "--workflow-ref", default="main", help="Release tooling branch (normally main)"
    )
    result.add_argument(
        "--dry-run",
        action="store_true",
        help="Build/export in CI without uploading or tagging",
    )
    result.add_argument("-y", "--yes", action="store_true")
    return result


def dispatch(args):
    fields = {"dry_run": str(args.dry_run).lower()}
    workflow = "beta.yml"
    sha = resolve(args.repo, args.ref)
    config = contents(args.repo, sha, "Config/Shared/Version.xcconfig")
    current_version = marketing_version(config)
    notes = contents(args.repo, sha, "current_changelog.txt")
    fields.update(source_ref=sha, build_number=args.build_number or "")
    print(f"Build {current_version} from {args.ref} ({sha})")
    print(
        "Accumulated source changelog (CI publishes the delta since the previous build):"
    )
    print(notes.strip() or "(empty)")
    print(f"Workflow: {workflow} on {args.workflow_ref}")
    if args.dry_run:
        print("CI dry-run: build and export only; no upload or build tag.")
    if not args.yes:
        if not sys.stdin.isatty():
            raise ValueError("Not a terminal; use --yes to dispatch CI")
        if input("Dispatch this workflow? [y/N] ").lower() not in ("y", "yes"):
            raise ValueError("Aborted")
    # Pass workflow inputs as JSON data without shell interpolation.
    subprocess.run(
        [
            "gh",
            "workflow",
            "run",
            workflow,
            "--repo",
            args.repo,
            "--ref",
            args.workflow_ref,
            "--json",
        ],
        input=json.dumps(fields),
        text=True,
        check=True,
    )
    print(f"Dispatched: https://github.com/{args.repo}/actions/workflows/{workflow}")


def main():
    try:
        dispatch(parser().parse_args())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(f"error: {error}")


if __name__ == "__main__":
    main()
