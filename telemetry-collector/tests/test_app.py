from __future__ import annotations

import json
import sqlite3
import time
from typing import Any

import pytest
from conftest import days_before, feature_payload, health_payload, rows
from prometheus_client import REGISTRY


def test_health_split_into_counters(client, db_path):
    r = client.post("/t/health", json=health_payload())
    assert r.status_code == 204
    assert r.content == b""
    got = {(f, v): n for (_, ch, p, f, v, n) in rows(db_path) if ch == "appstore" and p == "health"}
    assert got == {
        ("_pings", "total"): 1,
        ("app", "1.11.2"): 1,
        ("ios", "18.3"): 1,
        ("device", "iPhone"): 1,
        ("lang", "en"): 1,
        ("backend", "2.14.3"): 1,
        ("api", "10"): 1,
        ("docs", "1k-10k"): 1,
        ("auth", "token"): 1,
        ("client_cert", "true"): 1,
        ("custom_headers", "false"): 1,
        ("servers", "1"): 1,
        ("install_age", "<30d"): 1,
        ("first_month", "true"): 1,
        ("first_week", "false"): 1,
    }


def test_health_optional_fields_omitted(client, db_path):
    r = client.post("/t/health", json=health_payload(backend=None, api=None, docs=None, auth=None))
    assert r.status_code == 204
    fields = {f for (_, _, _, f, _, _) in rows(db_path)}
    assert not fields & {"backend", "api", "docs", "auth"}


def test_auth_none_accepted(client, db_path):
    assert client.post("/t/health", json=health_payload(auth="none")).status_code == 204
    assert ("auth", "none") in {(f, v) for (_, _, _, f, v, _) in rows(db_path)}


def test_removed_feature_name_dropped(client, db_path):
    r = client.post("/t/feature", json=feature_payload(features={"workflows": "1"}, available=["workflows"]))
    assert r.status_code == 204
    assert not any("workflows" in f for (_, _, _, f, _, _) in rows(db_path))


def test_feature_split_into_counters(client, db_path):
    r = client.post("/t/feature", json=feature_payload(errors=["tls", "timeout", "tls"]))
    assert r.status_code == 204
    assert {d for (d, *_rest) in rows(db_path)} == {"2026-11-06"}
    got = {(f, v): n for (_, _, p, f, v, n) in rows(db_path) if p == "feature"}
    assert got == {
        ("_pings", "total"): 1,
        ("feature:saved_view", "2-9"): 1,
        ("feature:scan_started", "1"): 1,
        ("feature:scan_uploaded", "1"): 1,
        ("available:saved_view", "true"): 1,
        ("available:scan_started", "true"): 1,
        ("available:scan_uploaded", "true"): 1,
        ("available:notes", "true"): 1,
        ("errors", "tls"): 1,
        ("errors", "timeout"): 1,
    }


def test_feature_without_errors(client, db_path):
    assert client.post("/t/feature", json=feature_payload(errors=None)).status_code == 204
    assert client.post("/t/feature", json=feature_payload(errors=[])).status_code == 204
    assert "errors" not in {f for (_, _, _, f, _, _) in rows(db_path)}


def test_empty_feature_ping_counts(client, db_path):
    assert client.post("/t/feature", json=feature_payload(features={}, available=[], errors=None)).status_code == 204
    assert rows(db_path) == [("2026-11-06", "appstore", "feature", "_pings", "total", 1)]


def test_counters_accumulate(client, db_path):
    for _ in range(3):
        client.post("/t/health", json=health_payload())
    got = {(f, v): n for (_, _, _, f, v, n) in rows(db_path)}
    assert got[("_pings", "total")] == 3
    assert got[("ios", "18.3")] == 3


def test_unknown_names_dropped_rest_kept(client, db_path):
    r = client.post(
        "/t/feature",
        json=feature_payload(
            features={"saved_view": "1", "time_travel": "10+"},
            available=["saved_view", "time_travel"],
            errors=["tls", "cosmic_ray"],
        ),
    )
    assert r.status_code == 204
    fields = {(f, v) for (_, _, _, f, v, _) in rows(db_path)}
    assert ("feature:saved_view", "1") in fields
    assert ("available:saved_view", "true") in fields
    assert ("errors", "tls") in fields
    assert not any("time_travel" in f or v == "cosmic_ray" for f, v in fields)


@pytest.mark.parametrize(
    ("path", "payload"),
    [
        ("/t/health", health_payload(extra_field="x")),
        ("/t/health", health_payload(device="iPod")),
        ("/t/health", health_payload(docs="5")),
        # Removed before release; a ping still carrying it is an unknown field.
        ("/t/health", health_payload(active_days_30="8-20")),
        ("/t/health", health_payload(install_age="old")),
        ("/t/health", health_payload(servers="3")),
        ("/t/health", health_payload(auth="magic")),
        ("/t/health", health_payload(client_cert="true")),
        ("/t/health", health_payload(first_month="true")),
        ("/t/health", health_payload(first_week=1)),
        ("/t/health", {k: v for k, v in health_payload().items() if k != "first_month"}),
        ("/t/health", health_payload(api="10")),
        ("/t/health", health_payload(ios="18.3.1")),
        ("/t/health", health_payload(lang="en-US")),
        ("/t/health", health_payload(backend="2.14.3-dev+abc")),
        ("/t/health", health_payload(app="1.11.2 (123)")),
        ("/t/health", health_payload(channel="beta")),
        ("/t/health", {k: v for k, v in health_payload().items() if k != "ios"}),
        ("/t/feature", feature_payload(features={"saved_view": "0"})),
        ("/t/feature", feature_payload(features={"time_travel": "lots"})),
        ("/t/feature", feature_payload(timestamp=123)),
        ("/t/feature", feature_payload(available=[f"f{i}" for i in range(65)])),
        ("/t/feature", feature_payload(features={f"f{i}": "1" for i in range(65)})),
        ("/t/health", health_payload(errors=["tls"])),
        ("/t/feature", feature_payload(errors=["x" * 65])),
        ("/t/feature", feature_payload(errors="tls")),
        ("/t/feature", feature_payload(day=None)),
    ],
)
def test_invalid_rejected_without_echo(client, db_path, path, payload):
    r = client.post(path, json=payload)
    assert r.status_code == 400
    assert r.content == b""
    assert rows(db_path) == []


@pytest.mark.parametrize("body", [b"", b"not json", b"[]", b"null", b'{"channel": "appstore"'])
def test_malformed_body(client, body):
    r = client.post("/t/feature", content=body, headers={"content-type": "application/json"})
    assert r.status_code == 400
    assert r.content == b""


def test_body_size_cap(client, db_path):
    big = json.dumps(feature_payload(available=["saved_view"] * 10, padding="x" * 5000)).encode()
    r = client.post("/t/feature", content=big, headers={"content-type": "application/json"})
    assert r.status_code == 413
    assert r.content == b""


def test_dev_channel_accepted(make_client, db_path):
    with make_client() as c:
        assert c.post("/t/feature", json=feature_payload(channel="dev")).status_code == 204
    assert {ch for (_, ch, *_rest) in rows(db_path)} == {"dev"}


def test_channels_keyed_separately(client, db_path):
    client.post("/t/feature", json=feature_payload(channel="appstore"))
    client.post("/t/feature", json=feature_payload(channel="testflight"))
    pings = {ch: n for (_, ch, _, f, _, n) in rows(db_path) if f == "_pings"}
    assert pings == {"appstore": 1, "testflight": 1}


def test_docs_disabled_in_production(client):
    for path in ("/docs", "/redoc", "/openapi.json"):
        assert client.get(path).status_code == 404


def test_docs_enabled_in_dev(make_client):
    with make_client(dev=True) as c:
        assert c.get("/openapi.json").status_code == 200


def test_collector_serves_no_dashboard_routes(client):
    paths = {getattr(r, "path", None) for r in client.app.routes}
    assert paths == {"/t/health", "/t/feature"}
    for path in ("/", "/login", "/auth/callback"):
        assert client.get(path).status_code == 404
    assert client.post("/logout").status_code == 404


def test_ping_visible_in_db_once_accepted(client, db_path):
    assert client.post("/t/health", json=health_payload()).status_code == 204
    assert ("health", "_pings", "total", 1) in {(p, f, v, n) for (_, _, p, f, v, n) in rows(db_path)}
    assert client.post("/t/feature", json=feature_payload()).status_code == 204
    got = {p: n for (_, _, p, f, _, n) in rows(db_path) if f == "_pings"}
    assert got == {"health": 1, "feature": 1}


def test_write_failure_returns_503_and_writes_nothing(client, db_path):
    from telemetry_collector.store import SCHEMA_SQL

    def failed() -> float:
        labels = {"endpoint": "health", "outcome": "write_failed"}
        return REGISTRY.get_sample_value("telemetry_requests_total", labels) or 0.0

    before = failed()
    other = sqlite3.connect(db_path, isolation_level=None)
    other.execute("DROP TABLE counters")
    r = client.post("/t/health", json=health_payload())
    assert r.status_code == 503
    assert failed() == before + 1
    assert r.content == b""
    other.execute(SCHEMA_SQL)
    other.close()
    assert rows(db_path) == []
    assert client.post("/t/health", json=health_payload()).status_code == 204
    assert [n for (*_, f, _, n) in rows(db_path) if f == "_pings"] == [1]


def test_not_found_and_wrong_method_bare(client):
    assert client.get("/t/health").status_code == 405
    assert client.get("/t/health").content == b""
    assert client.post("/nope", json={}).content == b""


def test_wal_mode_and_checkpointed_after_write(client, db_path):
    client.post("/t/health", json=health_payload())
    conn = sqlite3.connect(db_path)
    assert conn.execute("PRAGMA journal_mode").fetchone()[0] == "wal"
    # (busy, frames in the WAL, frames checkpointed): everything is in the database file.
    _, logged, checkpointed = conn.execute("PRAGMA wal_checkpoint(PASSIVE)").fetchone()
    assert logged == checkpointed
    conn.close()


def test_feature_counters_filed_under_ping_day(client, db_path, clock):
    clock.day = "2026-11-08"
    assert client.post("/t/health", json=health_payload()).status_code == 204
    assert client.post("/t/feature", json=feature_payload(day="2026-11-07")).status_code == 204
    assert client.post("/t/feature", json=feature_payload(day="2026-10-20")).status_code == 204
    by_ping = {(p, d): n for (d, _, p, f, _, n) in rows(db_path) if f == "_pings"}
    assert by_ping == {("health", "2026-11-08"): 1, ("feature", "2026-11-07"): 1, ("feature", "2026-10-20"): 1}
    assert ("2026-11-07", "feature", "errors", "tls") in {(d, p, f, v) for (d, _, p, f, v, _) in rows(db_path)}


def _rejected_feature() -> float:
    return (
        REGISTRY.get_sample_value("telemetry_requests_total", {"endpoint": "feature", "outcome": "rejected_400"}) or 0.0
    )


@pytest.mark.parametrize(
    ("day", "status"),
    [
        (days_before("2026-11-07", 1), 204),
        (days_before("2026-11-07", 30), 204),
        ("2026-11-07", 400),  # today
        ("2026-11-08", 400),  # future
        (days_before("2026-11-07", 31), 400),
        ("2026-02-30", 400),
        ("2026-11-6", 400),
        ("20261106", 400),
        ("2026-W45-5", 400),
        ("2026-11-06T00:00:00", 400),
        ("２０２６-11-06", 400),
        ("", 400),
    ],
)
def test_feature_day_bounds(client, db_path, day, status):
    before = _rejected_feature()
    r = client.post("/t/feature", json=feature_payload(day=day))
    assert r.status_code == status
    assert r.content == b""
    if status == 204:
        assert {d for (d, *_rest) in rows(db_path)} == {day}
        assert _rejected_feature() == before
    else:
        assert rows(db_path) == []
        assert _rejected_feature() == before + 1


def test_feature_day_must_be_string(client, db_path):
    assert client.post("/t/feature", json=feature_payload(day=20261106)).status_code == 400
    assert rows(db_path) == []


def test_checkpoint_failure_still_accepts_the_committed_ping(client, db_path):
    class FailingCheckpoint:
        def __init__(self, conn: sqlite3.Connection) -> None:
            self._conn = conn

        def __getattr__(self, name: str) -> object:
            return getattr(self._conn, name)

        def execute(self, sql: str, *args: Any) -> sqlite3.Cursor:
            if "wal_checkpoint" in sql:
                raise sqlite3.OperationalError("checkpoint failed")
            return self._conn.execute(sql, *args)

    conn = client.app.state.conn
    client.app.state.conn = FailingCheckpoint(conn)
    try:
        assert client.post("/t/health", json=health_payload()).status_code == 204
    finally:
        client.app.state.conn = conn
    assert [n for (*_, f, _, n) in rows(db_path) if f == "_pings"] == [1]


def test_open_read_does_not_delay_a_write(client, db_path):
    reader = sqlite3.connect(db_path, isolation_level=None)
    reader.execute("BEGIN")
    reader.execute("SELECT count(*) FROM counters").fetchone()
    started = time.perf_counter()
    assert client.post("/t/health", json=health_payload()).status_code == 204
    assert time.perf_counter() - started < 1
    reader.execute("COMMIT")
    reader.close()


def test_wal_holds_only_the_last_transaction(client, db_path):
    for _ in range(3):
        assert client.post("/t/health", json=health_payload()).status_code == 204
    conn = sqlite3.connect(db_path)
    page_size = conn.execute("PRAGMA page_size").fetchone()[0]
    _, frames, _ = conn.execute("PRAGMA wal_checkpoint(PASSIVE)").fetchone()
    conn.close()
    wal = db_path.with_name(db_path.name + "-wal")
    # WAL header plus one header-and-page per valid frame: no stale frames after them.
    assert wal.stat().st_size == 32 + frames * (24 + page_size)


def test_db_size_includes_the_wal(client, db_path):
    from telemetry_collector.store import db_size

    assert client.post("/t/health", json=health_payload()).status_code == 204
    wal = db_path.with_name(db_path.name + "-wal")
    assert wal.stat().st_size > 0
    assert db_size(db_path) == db_path.stat().st_size + wal.stat().st_size
    assert REGISTRY.get_sample_value("telemetry_db_size_bytes") == db_size(db_path)
