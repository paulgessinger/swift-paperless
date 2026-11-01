"""Offline tests for `swpngx deliver`: asc is faked, nothing reaches App Store Connect."""

from pathlib import Path

import pytest
import typer

from swpngx import deliver


@pytest.fixture
def metadata(tmp_path: Path) -> Path:
    root = tmp_path / "metadata"
    default = root / "default"
    default.mkdir(parents=True)
    (default / "name.txt").write_text("Swift Paperless\n")
    (default / "description.txt").write_text("English\n")
    (default / "release_notes.txt").write_text("Notes\n")
    german = root / "de-DE"
    german.mkdir()
    (german / "description.txt").write_text("Deutsch\n")
    (german / "release_notes.txt").write_text("Stale\n")
    (root / "review_information").mkdir()
    (root / "copyright.txt").write_text("2026 Paul Gessinger\n")
    (root / "primary_category.txt").write_text("PRODUCTIVITY\n")
    (root / "secondary_category.txt").write_text("\n")
    return root


@pytest.fixture
def screenshots(tmp_path: Path) -> Path:
    root = tmp_path / "framed"
    (root / "en-US").mkdir(parents=True)
    (root / "en-US" / "iPhone-01_documents-framed.png").touch()
    return root


@pytest.fixture
def devices(tmp_path: Path) -> Path:
    file = tmp_path / "devices.toml"
    entry = """
[[device]]
id = "{id}"
simulator_name = "{id}"
bezel_pack = "pack"
bezel = "bezel.png"
asc_display_type = "{display_type}"
target_size = [1, 1]
offset = [0, 0]
mask_corner_radius = 0
mask_margin = 0
"""
    file.write_text(
        entry.format(id="iPhone", display_type="IPHONE_67")
        + entry.format(id="iPad", display_type="IPAD_PRO_3GEN_129")
    )
    return file


class FakeAsc:
    def __init__(self, monkeypatch: pytest.MonkeyPatch, versions: list[dict]):
        self.calls: list[tuple[str, ...]] = []
        self.versions = versions
        monkeypatch.setattr(deliver.shutil, "which", lambda _: "/usr/bin/asc")
        monkeypatch.setattr(deliver, "asc", self.record)
        monkeypatch.setattr(deliver, "asc_json", self.record_json)

    def record(self, *args: str) -> None:
        self.calls.append(args)

    def record_json(self, *args: str) -> dict:
        self.calls.append(args)
        if args[:2] == ("apps", "list"):
            return {"data": [{"id": "APP"}]}
        if args[:2] == ("versions", "list"):
            return {"data": self.versions}
        if args[:2] == ("versions", "create"):
            return {"data": {"id": "NEW"}}
        raise AssertionError(args)

    def commands(self) -> list[tuple[str, str]]:
        return [call[:2] for call in self.calls]


def run(metadata: Path, screenshots: Path, devices: Path, **options) -> None:
    deliver.main(
        version="1.11.0",
        metadata_dir=metadata,
        screenshots_dir=screenshots,
        devices_file=devices,
        **options,
    )


def test_stage_expands_default_into_every_locale(metadata: Path, tmp_path: Path):
    stage = tmp_path / "stage"

    assert deliver.stage_metadata(metadata, stage) == ["de-DE", "en-US"]

    english = stage / "metadata" / "en-US"
    assert (english / "description.txt").read_text() == "English\n"
    assert (english / "name.txt").read_text() == "Swift Paperless\n"
    german = stage / "metadata" / "de-DE"
    assert (german / "description.txt").read_text() == "Deutsch\n"
    assert (german / "name.txt").read_text() == "Swift Paperless\n"
    assert (german / "release_notes.txt").read_text() == "Notes\n"
    assert not (stage / "metadata" / "default").exists()
    assert not (stage / "metadata" / "review_information").exists()


def test_stage_keeps_review_information(metadata: Path, tmp_path: Path):
    (metadata / "review_information" / "notes.txt").write_text("Review\n")
    stage = tmp_path / "stage"

    deliver.stage_metadata(metadata, stage)

    assert (stage / "metadata" / "review_information" / "notes.txt").exists()


def test_categories_skip_empty_files(metadata: Path):
    assert deliver.read_categories(metadata) == ["--primary", "PRODUCTIVITY"]


def test_upload_replaces_screenshots_of_captured_devices_only(
    metadata, screenshots, devices, monkeypatch
):
    fake = FakeAsc(monkeypatch, [{"id": "VERSION"}])

    run(metadata, screenshots, devices)

    assert fake.commands() == [
        ("migrate", "validate"),
        ("apps", "list"),
        ("versions", "list"),
        ("migrate", "import"),
        ("versions", "update"),
        ("categories", "set"),
        ("screenshots", "upload"),
    ]
    assert "--confirm" in fake.calls[3]
    assert fake.calls[4][-1] == "2026 Paul Gessinger"
    upload = fake.calls[-1]
    assert upload[upload.index("--device-type") + 1] == "IPHONE_67"
    assert "--replace" in upload and "--confirm" in upload


def test_skip_screenshots_needs_no_framed_files(
    metadata, tmp_path, devices, monkeypatch
):
    fake = FakeAsc(monkeypatch, [{"id": "VERSION"}])

    run(metadata, tmp_path / "missing", devices, skip_screenshots=True)

    assert ("screenshots", "upload") not in fake.commands()


def test_missing_screenshots_fail_before_any_asc_call(
    metadata, tmp_path, devices, monkeypatch
):
    fake = FakeAsc(monkeypatch, [{"id": "VERSION"}])

    with pytest.raises(typer.Exit):
        run(metadata, tmp_path / "missing", devices)

    assert fake.calls == []


def test_missing_version_is_created(metadata, screenshots, devices, monkeypatch):
    fake = FakeAsc(monkeypatch, [])

    run(metadata, screenshots, devices)

    assert ("versions", "create") in fake.commands()
    assert "NEW" in fake.calls[fake.commands().index(("migrate", "import"))]


def test_dry_run_changes_nothing(metadata, screenshots, devices, monkeypatch):
    fake = FakeAsc(monkeypatch, [{"id": "VERSION"}])

    run(metadata, screenshots, devices, dry_run=True)

    assert ("versions", "update") not in fake.commands()
    assert ("categories", "set") not in fake.commands()
    for call in fake.calls:
        assert "--confirm" not in call
    for command in (("migrate", "import"), ("screenshots", "upload")):
        assert "--dry-run" in fake.calls[fake.commands().index(command)]


def test_dry_run_does_not_create_a_missing_version(
    metadata, screenshots, devices, monkeypatch
):
    fake = FakeAsc(monkeypatch, [])

    run(metadata, screenshots, devices, dry_run=True)

    assert ("versions", "create") not in fake.commands()
    assert ("migrate", "import") not in fake.commands()
