from __future__ import annotations

import sqlite3
from collections.abc import Callable, Generator
from contextlib import AbstractContextManager, contextmanager
from pathlib import Path
from typing import Any

import pytest
from fastapi.testclient import TestClient

from telemetry_collector.app import create_app
from telemetry_collector.config import DashboardSettings, Settings

ENV_NAMES = {alias for cls in (Settings, DashboardSettings) for f in cls.model_fields.values() if (alias := f.alias)}


@pytest.fixture(autouse=True)
def _clean_settings_env(monkeypatch: pytest.MonkeyPatch) -> None:
    """Keep the developer's shell environment out of settings built in tests."""
    for name in ENV_NAMES:
        monkeypatch.delenv(name, raising=False)


def by_field[T: Settings | DashboardSettings](cls: type[T], **fields: Any) -> T:
    """Build settings from field names (the classes only accept env var names)."""
    return cls(**{cls.model_fields[name].alias or name: value for name, value in fields.items()})


class Clock:
    def __init__(self, day: str = "2026-11-07") -> None:
        self.day = day

    def __call__(self) -> str:
        return self.day


def health_payload(**overrides: object) -> dict[str, object]:
    payload: dict[str, object] = {
        "channel": "appstore",
        "app": "1.11.2",
        "ios": "18.3",
        "device": "iPhone",
        "lang": "en",
        "backend": "2.14.3",
        "api": 10,
        "docs": "1k-10k",
        "auth": "token",
        "client_cert": True,
        "custom_headers": False,
        "servers": "1",
        "active_days_30": "8-20",
        "install_age": "<30d",
        "errors": ["tls"],
    }
    payload.update(overrides)
    return {k: v for k, v in payload.items() if v is not None}


def feature_payload(**overrides: object) -> dict[str, object]:
    payload: dict[str, object] = {
        "channel": "appstore",
        "features": {"saved_view": "2-9", "scan_started": "1", "scan_uploaded": "1"},
        "available": ["saved_view", "scan_started", "scan_uploaded", "notes"],
    }
    payload.update(overrides)
    return payload


def rows(db: Path) -> list[tuple[str, str, str, str, str, int]]:
    if not db.exists():
        return []
    conn = sqlite3.connect(db)
    try:
        return conn.execute(
            "SELECT day, channel, ping, field, value, count FROM counters ORDER BY day, channel, ping, field, value"
        ).fetchall()
    except sqlite3.OperationalError:
        return []
    finally:
        conn.close()


@pytest.fixture
def db_path(tmp_path: Path) -> Path:
    return tmp_path / "telemetry.sqlite3"


@pytest.fixture
def clock() -> Clock:
    return Clock()


@pytest.fixture
def make_client(db_path: Path, clock: Clock) -> Callable[..., AbstractContextManager[TestClient]]:
    @contextmanager
    def factory(**kwargs: Any) -> Generator[TestClient]:
        settings = by_field(Settings, db_path=db_path, **kwargs)
        with TestClient(create_app(settings, today=clock), raise_server_exceptions=True) as client:
            yield client

    return factory


@pytest.fixture
def client(make_client: Callable[..., AbstractContextManager[TestClient]]) -> Generator[TestClient]:
    with make_client(batch_size=1) as c:
        yield c
