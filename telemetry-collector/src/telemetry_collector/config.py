from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


def _env_bool(name: str, default: bool = False) -> bool:
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in ("1", "true", "yes", "on")


@dataclass(frozen=True)
class Settings:
    db_path: Path
    schema_path: Path | None = None
    # Channels the collector accepts. Production must not include "dev".
    channels: frozenset[str] = frozenset({"appstore", "testflight"})
    batch_size: int = 20
    max_body_bytes: int = 4096
    # Dev mode: accepts the "dev" channel and serves /docs.
    dev: bool = False

    @classmethod
    def from_env(cls) -> Settings:
        dev = _env_bool("TELEMETRY_DEV")
        default_channels = "appstore,testflight,dev" if dev else "appstore,testflight"
        channels = frozenset(
            c.strip() for c in os.environ.get("TELEMETRY_CHANNELS", default_channels).split(",") if c.strip()
        )
        schema = os.environ.get("TELEMETRY_SCHEMA_PATH")
        return cls(
            db_path=Path(os.environ.get("TELEMETRY_DB_PATH", "telemetry.sqlite3")),
            schema_path=Path(schema) if schema else None,
            channels=channels,
            batch_size=int(os.environ.get("TELEMETRY_BATCH_SIZE", "20")),
            dev=dev,
        )
