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
        if args[:2] == ("localizations", "list"):
            return {"data": [{"id": "LOC-EN", "attributes": {"locale": "en-US"}}]}
        if args[:2] == ("video-previews", "list"):
            return {
                "sets": [
                    {
                        "set": {"attributes": {"previewType": "IPHONE_61"}},
                        "previews": [{"id": "PREVIEW"}],
                    }
                ]
            }
        raise AssertionError(args)

    def commands(self) -> list[tuple[str, str]]:
        return [call[:2] for call in self.calls]


def run(metadata: Path, screenshots: Path, devices: Path, **options) -> None:
    options.setdefault("previews_dir", metadata.parent / "no-previews")
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


@pytest.fixture
def previews(tmp_path: Path) -> Path:
    root = tmp_path / "previews"
    for locale in ("en-US", "xx"):
        (root / locale).mkdir(parents=True)
        (root / locale / "paper_to_pixels.mp4").touch()
    (root / "empty").mkdir()
    return root


def test_previews_replace_per_locale_and_set_the_poster_frame(
    metadata, screenshots, devices, previews, monkeypatch
):
    fake = FakeAsc(monkeypatch, [{"id": "VERSION"}])

    run(metadata, screenshots, devices, previews_dir=previews)

    uploads = [c for c in fake.calls if c[:2] == ("video-previews", "upload")]
    # Only en-US has a localization on App Store Connect; "empty" has no video.
    assert len(uploads) == 1
    upload = uploads[0]
    assert upload[upload.index("--version-localization") + 1] == "LOC-EN"
    assert upload[upload.index("--device-type") + 1] == "IPHONE_61"
    assert "--replace" in upload and "--confirm" in upload
    assert fake.calls[-1][:2] == ("video-previews", "set-poster-frame")
    assert "PREVIEW" in fake.calls[-1]


def test_previews_dry_run(metadata, screenshots, devices, previews, monkeypatch):
    fake = FakeAsc(monkeypatch, [{"id": "VERSION"}])

    run(metadata, screenshots, devices, previews_dir=previews, dry_run=True)

    upload = fake.calls[fake.commands().index(("video-previews", "upload"))]
    assert "--dry-run" in upload and "--confirm" not in upload
    assert ("video-previews", "set-poster-frame") not in fake.commands()


def test_skip_previews(metadata, screenshots, devices, previews, monkeypatch):
    fake = FakeAsc(monkeypatch, [{"id": "VERSION"}])

    run(metadata, screenshots, devices, previews_dir=previews, skip_previews=True)

    assert ("video-previews", "upload") not in fake.commands()


def test_devices_sharing_a_set_upload_once(metadata, tmp_path, monkeypatch):
    devices = tmp_path / "duo.toml"
    devices.write_text(
        """
[[device]]
id = "iPhone_Duo_Inner"
simulator_name = "iPhone Duo"
asc_display_type = "IPHONE_DUO"

[[device]]
id = "iPhone_Duo_Outer"
simulator_name = "iPhone Duo"
asc_display_type = "IPHONE_DUO"
"""
    )
    screenshots = tmp_path / "framed"
    (screenshots / "en-US").mkdir(parents=True)
    for device in ("iPhone_Duo_Inner", "iPhone_Duo_Outer"):
        (screenshots / "en-US" / f"{device}-01_documents-framed.png").touch()
    fake = FakeAsc(monkeypatch, [{"id": "VERSION"}])

    run(metadata, screenshots, devices)

    uploads = [call for call in fake.calls if call[:2] == ("screenshots", "upload")]
    assert len(uploads) == 1
    assert uploads[0][uploads[0].index("--device-type") + 1] == "IPHONE_DUO"
