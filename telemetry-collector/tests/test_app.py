from __future__ import annotations

import json

import pytest
from conftest import feature_payload, health_payload, rows


def test_health_split_into_counters(client, db_path):
    r = client.post("/t/health", json=health_payload(errors=["tls", "timeout", "tls"]))
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
        ("active_days_30", "8-20"): 1,
        ("install_age", "<30d"): 1,
        ("errors", "tls"): 1,
        ("errors", "timeout"): 1,
    }


def test_health_optional_fields_omitted(client, db_path):
    r = client.post("/t/health", json=health_payload(backend=None, api=None, docs=None, auth=None, errors=None))
    assert r.status_code == 204
    fields = {f for (_, _, _, f, _, _) in rows(db_path)}
    assert not fields & {"backend", "api", "docs", "auth", "errors"}


def test_auth_none_accepted(client, db_path):
    assert client.post("/t/health", json=health_payload(auth="none")).status_code == 204
    assert ("auth", "none") in {(f, v) for (_, _, _, f, v, _) in rows(db_path)}


def test_removed_feature_name_dropped(client, db_path):
    r = client.post("/t/feature", json=feature_payload(features={"workflows": "1"}, available=["workflows"]))
    assert r.status_code == 204
    assert not any("workflows" in f for (_, _, _, f, _, _) in rows(db_path))


def test_feature_split_into_counters(client, db_path):
    r = client.post("/t/feature", json=feature_payload())
    assert r.status_code == 204
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
    }


def test_empty_feature_ping_counts(client, db_path):
    assert client.post("/t/feature", json=feature_payload(features={}, available=[])).status_code == 204
    assert rows(db_path) == [("2026-11-07", "appstore", "feature", "_pings", "total", 1)]


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
            features={"saved_view": "1", "time_travel": "10+"}, available=["saved_view", "time_travel"]
        ),
    )
    assert r.status_code == 204
    r = client.post("/t/health", json=health_payload(errors=["tls", "cosmic_ray"]))
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
        ("/t/health", health_payload(active_days_30="0")),
        ("/t/health", health_payload(install_age="old")),
        ("/t/health", health_payload(servers="3")),
        ("/t/health", health_payload(auth="magic")),
        ("/t/health", health_payload(client_cert="true")),
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
        ("/t/health", health_payload(errors=["x" * 65])),
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


def test_dev_channel_rejected_in_production(client, db_path):
    r = client.post("/t/health", json=health_payload(channel="dev"))
    assert r.status_code == 400
    assert r.content == b""
    assert rows(db_path) == []


def test_dev_channel_accepted_in_dev_mode(make_client, db_path):
    with make_client(dev=True, channels=frozenset({"appstore", "testflight", "dev"}), batch_size=1) as c:
        assert c.post("/t/feature", json=feature_payload(channel="dev")).status_code == 204
    assert {ch for (_, ch, *_rest) in rows(db_path)} == {"dev"}


def test_dev_channel_requires_dev_mode(db_path):
    from conftest import by_field
    from pydantic import ValidationError

    from telemetry_collector.config import Settings

    with pytest.raises(ValidationError, match="the dev channel is only accepted in dev mode"):
        by_field(Settings, db_path=db_path, channels=frozenset({"appstore", "dev"}))


def test_channels_keyed_separately(client, db_path):
    client.post("/t/feature", json=feature_payload(channel="appstore"))
    client.post("/t/feature", json=feature_payload(channel="testflight"))
    pings = {ch: n for (_, ch, _, f, _, n) in rows(db_path) if f == "_pings"}
    assert pings == {"appstore": 1, "testflight": 1}


def test_docs_disabled_in_production(client):
    for path in ("/docs", "/redoc", "/openapi.json"):
        assert client.get(path).status_code == 404


def test_docs_enabled_in_dev(make_client):
    with make_client(dev=True, channels=frozenset({"dev"})) as c:
        assert c.get("/openapi.json").status_code == 200


def test_collector_serves_no_dashboard_routes(client):
    paths = {getattr(r, "path", None) for r in client.app.routes}
    assert paths == {"/t/health", "/t/feature"}
    for path in ("/", "/login", "/auth/callback"):
        assert client.get(path).status_code == 404
    assert client.post("/logout").status_code == 404


def test_flush_failure_keeps_buffer(db_path, clock):
    from telemetry_collector.store import SCHEMA_SQL, CounterStore, connect

    conn = connect(db_path)
    store = CounterStore(conn, batch_size=10, today=clock)
    store.add("appstore", "health", [("_pings", "total")])
    conn.execute("DROP TABLE counters")
    store.flush()
    assert store.pending_pings == 1
    conn.execute(SCHEMA_SQL)
    store.flush()
    assert store.pending_pings == 0
    assert conn.execute("SELECT count FROM counters").fetchall() == [(1,)]
    conn.close()


def test_not_found_and_wrong_method_bare(client):
    assert client.get("/t/health").status_code == 405
    assert client.get("/t/health").content == b""
    assert client.post("/nope", json={}).content == b""


def test_nothing_written_before_batch_full(make_client, db_path):
    with make_client(batch_size=5) as c:
        for _ in range(4):
            assert c.post("/t/health", json=health_payload()).status_code == 204
        assert rows(db_path) == []
        c.post("/t/feature", json=feature_payload())
        got = {(p, f): n for (_, _, p, f, _, n) in rows(db_path) if f == "_pings"}
        assert got == {("health", "_pings"): 4, ("feature", "_pings"): 1}
        c.post("/t/health", json=health_payload())
        assert sum(n for (*_, f, _, n) in rows(db_path) if f == "_pings") == 5


def test_rejected_pings_do_not_count_towards_batch(make_client, db_path):
    with make_client(batch_size=2) as c:
        c.post("/t/health", json=health_payload())
        c.post("/t/health", json=health_payload(device="Android"))
        assert rows(db_path) == []
        c.post("/t/health", json=health_payload())
        assert rows(db_path) != []


def test_shutdown_flushes_partial_batch(make_client, db_path):
    with make_client(batch_size=20) as c:
        c.post("/t/health", json=health_payload())
        c.post("/t/feature", json=feature_payload())
        assert rows(db_path) == []
    got = {p: n for (_, _, p, f, _, n) in rows(db_path) if f == "_pings"}
    assert got == {"health": 1, "feature": 1}


def test_day_rollover_flushes_previous_day(make_client, db_path, clock):
    with make_client(batch_size=20) as c:
        clock.day = "2026-11-07"
        c.post("/t/health", json=health_payload())
        c.post("/t/health", json=health_payload())
        assert rows(db_path) == []
        clock.day = "2026-11-08"
        c.post("/t/health", json=health_payload())
        # Previous day written; the new day's ping is still buffered.
        assert {d for (d, *_rest) in rows(db_path)} == {"2026-11-07"}
        assert [n for (d, _, _, f, _, n) in rows(db_path) if f == "_pings"] == [2]
    by_day = {d: n for (d, _, _, f, _, n) in rows(db_path) if f == "_pings"}
    assert by_day == {"2026-11-07": 2, "2026-11-08": 1}


def test_wal_mode_and_truncated_after_flush(client, db_path):
    client.post("/t/health", json=health_payload())
    import sqlite3

    conn = sqlite3.connect(db_path)
    assert conn.execute("PRAGMA journal_mode").fetchone()[0] == "wal"
    conn.close()
    wal = db_path.with_name(db_path.name + "-wal")
    assert not wal.exists() or wal.stat().st_size == 0
