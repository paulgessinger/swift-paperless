"""Shared screenshot device configuration for capture, framing, and bezels."""

from __future__ import annotations

from pathlib import Path

from pydantic import BaseModel, Field, model_validator

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover
    import tomli as tomllib


class ScreenshotDevice(BaseModel):
    """One logical device across capture, bezel install, and framing."""

    id: str
    simulator_name: str
    bezel_pack: str
    bezel: str
    frames_dir: Path = Path("fastlane/screenshots/frames")
    target_size: tuple[int, int]
    offset: tuple[int, int]
    post_offset: tuple[int, int] = (0, 0)
    post_margin: int = 0
    mask_corner_radius: int
    mask_margin: int
    shadow_blur: int = 30

    @property
    def name(self) -> str:
        """Device key used in screenshot filenames and frames.toml patterns."""
        return self.id

    @property
    def frame_path(self) -> Path:
        return self.frames_dir / self.bezel

    @model_validator(mode="before")
    @classmethod
    def coerce_points(cls, data: object) -> object:
        if not isinstance(data, dict):
            return data
        for key in ("target_size", "offset", "post_offset"):
            value = data.get(key)
            if isinstance(value, list) and len(value) == 2:
                data[key] = tuple(value)
        return data


class ScreenshotDevicesFile(BaseModel):
    frames_dir: Path = Path("fastlane/screenshots/frames")
    devices: list[ScreenshotDevice]


def load_screenshot_devices(path: Path) -> ScreenshotDevicesFile:
    data = tomllib.loads(path.read_text(encoding="utf-8"))
    frames_dir = Path(data.pop("frames_dir", "fastlane/screenshots/frames"))
    raw_devices = data.pop("device", data.pop("devices", []))
    if data:
        unknown = ", ".join(sorted(data))
        raise ValueError(f"Unknown keys in {path.name}: {unknown}")
    devices = [
        ScreenshotDevice(frames_dir=frames_dir, **entry) for entry in raw_devices
    ]
    return ScreenshotDevicesFile(frames_dir=frames_dir, devices=devices)


def device_by_id(devices: ScreenshotDevicesFile, device_id: str) -> ScreenshotDevice:
    for device in devices.devices:
        if device.id == device_id:
            return device
    known = ", ".join(d.id for d in devices.devices)
    raise KeyError(f"Unknown device id {device_id!r} (known: {known})")


def resolve_devices_path(frames_config: Path, explicit: Path | None = None) -> Path:
    if explicit is not None:
        return explicit.resolve()
    data = tomllib.loads(frames_config.read_text(encoding="utf-8"))
    devices_key = data.get("devices")
    if isinstance(devices_key, str):
        return (frames_config.parent / devices_key).resolve()
    return frames_config.parent / "screenshot_devices.toml"
