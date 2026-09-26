"""Offline contract tests: never call GitHub, ASC, Xcode, or the keychain."""

import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import release_dispatch as dispatch

SHA = "a" * 40
CONFIG = "MARKETING_VERSION = 1.10.4\n"


class DispatchTests(unittest.TestCase):
    @patch.object(dispatch.subprocess, "run")
    @patch.object(dispatch, "contents", side_effect=[CONFIG, "- A fix\n"])
    @patch.object(dispatch, "resolve", return_value=SHA)
    def test_maintenance_source_is_pinned_but_workflow_stays_on_main(
        self, resolve, contents, run
    ):
        args = dispatch.parser().parse_args(
            ["--ref", "release/1.10", "--yes", "--dry-run"]
        )
        dispatch.dispatch(args)
        command = run.call_args.args[0]
        self.assertEqual(command[command.index("--ref") + 1], "main")
        inputs = json.loads(run.call_args.kwargs["input"])
        self.assertEqual(inputs["source_ref"], SHA)
        self.assertEqual(inputs["dry_run"], "true")

    @patch.object(dispatch.subprocess, "run")
    @patch.object(dispatch, "contents", side_effect=[CONFIG, "- A fix\n"])
    @patch.object(dispatch, "resolve", return_value=SHA)
    def test_default_release_uploads_main_with_ci_assigned_number(
        self, resolve, contents, run
    ):
        dispatch.dispatch(dispatch.parser().parse_args(["--yes"]))
        resolve.assert_called_once_with(dispatch.REPOSITORY, "main")
        self.assertEqual(run.call_args.args[0][3], "beta.yml")
        self.assertEqual(
            json.loads(run.call_args.kwargs["input"]),
            {
                "dry_run": "false",
                "source_ref": SHA,
                "build_number": "",
            },
        )

    @patch.object(dispatch.subprocess, "run")
    @patch.object(dispatch, "contents", side_effect=[CONFIG, ""])
    @patch.object(dispatch, "resolve", return_value=SHA)
    def test_explicit_build_number_and_tooling_ref(self, resolve, contents, run):
        args = dispatch.parser().parse_args(
            [
                "--ref",
                "develop/v1.10.3",
                "--build-number",
                "222",
                "--workflow-ref",
                "ci/shared-release-tooling",
                "--yes",
            ]
        )
        dispatch.dispatch(args)
        command = run.call_args.args[0]
        self.assertEqual(
            command[command.index("--ref") + 1], "ci/shared-release-tooling"
        )
        self.assertEqual(
            json.loads(run.call_args.kwargs["input"])["build_number"], "222"
        )

    @patch.object(dispatch.subprocess, "run")
    @patch.object(dispatch, "resolve", side_effect=ValueError("Missing remote ref"))
    def test_missing_source_cannot_dispatch(self, resolve, run):
        with self.assertRaisesRegex(ValueError, "Missing remote ref"):
            dispatch.dispatch(dispatch.parser().parse_args(["--yes"]))
        run.assert_not_called()

    def test_rejects_invalid_build_numbers(self):
        for value in ("-1", "0", "1;echo hi", "1.2"):
            with self.assertRaises(argparse.ArgumentTypeError):
                dispatch.build_number(value)


class BuildIsolationTests(unittest.TestCase):
    def test_archive_uses_selected_source_and_central_signing_files(self):
        import shutil

        tooling = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "old source"
            config = source / "Config/Shared/Version.xcconfig"
            config.parent.mkdir(parents=True)
            config.write_text(CONFIG + "CURRENT_PROJECT_VERSION = 222\n")
            tools = root / "bin"
            tools.mkdir()
            # No asc/gh/security on PATH: this test cannot upload or sign anything.
            for command in ("dirname", "grep", "sed", "rm", "find", "head"):
                (tools / command).symlink_to(shutil.which(command))
            fake = (
                f"#!{sys.executable}\n"
                + """
import json, os, sys
from pathlib import Path
with open(os.environ["CALL_LOG"], "a") as log:
    log.write(json.dumps({"cwd": os.getcwd(), "args": sys.argv}) + "\\n")
if "-exportArchive" in sys.argv:
    export = Path(sys.argv[sys.argv.index("-exportPath") + 1])
    export.mkdir(parents=True)
    (export / "app.ipa").touch()
"""
            )
            for command in ("xcodegen", "xcodebuild"):
                path = tools / command
                path.write_text(fake)
                path.chmod(0o755)
            log = root / "calls.jsonl"
            subprocess.run(
                ["/bin/bash", str(tooling / "scripts/beta_ci.sh"), "--no-upload"],
                env={
                    "PATH": str(tools),
                    "SOURCE_ROOT": str(source),
                    "CALL_LOG": str(log),
                },
                capture_output=True,
                text=True,
                check=True,
            )
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            self.assertEqual(len(calls), 3)
            self.assertTrue(
                all(Path(call["cwd"]).resolve() == source.resolve() for call in calls)
            )
            archive = calls[1]["args"]
            self.assertEqual(
                archive[archive.index("-xcconfig") + 1],
                str(tooling / "scripts/CIArchiveSigning.xcconfig"),
            )
            export = calls[2]["args"]
            self.assertEqual(
                export[export.index("-exportOptionsPlist") + 1],
                str(tooling / "scripts/ExportOptions.plist"),
            )
            self.assertEqual(
                config.read_text(), CONFIG + "CURRENT_PROJECT_VERSION = 222\n"
            )


if __name__ == "__main__":
    unittest.main()
