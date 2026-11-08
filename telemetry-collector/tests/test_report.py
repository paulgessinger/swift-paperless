from __future__ import annotations

import sqlite3

import pytest
from conftest import feature_payload, health_payload

from telemetry_collector.report import (
    ACTIVE_DAYS_MIDPOINTS,
    UNKNOWN,
    Counts,
    completion_pairs,
    distribution,
    error_shares,
    mau_estimate,
    open_readonly,
    render,
)
from telemetry_collector.schema import load_schema

SCHEMA = load_schema()


def test_midpoints_cover_schema_buckets():
    import json

    from telemetry_collector.schema import DEFAULT_SCHEMA_PATH

    raw = json.loads(DEFAULT_SCHEMA_PATH.read_text())
    assert set(ACTIVE_DAYS_MIDPOINTS) == set(raw["buckets"]["active_days_30"])


@pytest.fixture
def seeded(make_client, db_path, clock):
    with make_client(batch_size=20) as c:
        clock.day = "2026-11-06"
        c.post("/t/health", json=health_payload(active_days_30="1"))
        clock.day = "2026-11-07"
        c.post("/t/health", json=health_payload(active_days_30="2-7", auth=None, backend=None))
        c.post("/t/health", json=health_payload(active_days_30="2-7", auth="none"))
        assert c.post("/t/feature", json=feature_payload(day="2026-11-06")).status_code == 204
        assert c.post("/t/feature", json=feature_payload(day="2026-11-06", features={}, errors=None)).status_code == 204
    return db_path


def test_report(seeded):
    conn = open_readonly(seeded)
    counts = Counts(conn, "appstore", "2026-10-01", "2026-11-07")
    assert mau_estimate(counts, "2026-11-07") == 1 + 2 / 4.5
    out = render(conn, SCHEMA, days=7)
    conn.close()
    assert "still filling in" in out.splitlines()[0]
    assert "== 2026-11-07  channel=appstore" in out
    assert "active_days_30: 2-7=2" in out
    # Feature pings sent on 11-07 are filed under the day they report.
    day_06 = out.split("== 2026-11-06  channel=appstore")[1].split("== 2026-11-07")[0]
    assert "[feature] pings=2" in day_06
    assert "errors: tls=1" in day_06
    assert "saved_view: 1/2 (50%)" in day_06
    assert "notes: 0/2 (0%)" in day_06
    assert "[feature]" not in out.split("== 2026-11-07  channel=appstore")[1]
    assert "MAU estimate appstore (30 days ending 2026-11-07): 1.4" in out


def test_unknown_derived_for_optional_fields(seeded):
    conn = open_readonly(seeded)
    counts = Counts(conn, "appstore", "2026-11-06", "2026-11-07")
    conn.close()
    assert distribution(counts, SCHEMA, "auth", "2026-11-07", "2026-11-07") == {"none": 1, UNKNOWN: 1}
    assert distribution(counts, SCHEMA, "auth") == {"token": 1, "none": 1, UNKNOWN: 1}
    assert distribution(counts, SCHEMA, "backend") == {"2.14.3": 2, UNKNOWN: 1}
    # No unknown row when every ping carried the field, and never for required fields.
    assert UNKNOWN not in distribution(counts, SCHEMA, "docs")
    assert UNKNOWN not in distribution(counts, SCHEMA, "device")
    assert SCHEMA.optional_fields == {"auth", "backend", "api", "docs"}


def test_completion_pairs_from_schema():
    assert completion_pairs(list(SCHEMA.features)) == [
        ("scan_started", "scan_uploaded"),
        ("import_started", "import_uploaded"),
    ]


def test_implausible_flagged(make_client, db_path):
    with make_client(batch_size=1) as c:
        c.post("/t/feature", json=feature_payload())
    conn = open_readonly(db_path)
    assert "!! implausible: 1 feature pings vs 0 health pings" in render(conn, SCHEMA)
    conn.close()


def test_report_readonly(make_client, db_path):
    with make_client(batch_size=1) as c:
        c.post("/t/feature", json=feature_payload())
    conn = open_readonly(db_path)
    with pytest.raises(sqlite3.OperationalError):
        conn.execute("DELETE FROM counters")
    conn.close()


def test_readonly_reader_while_collector_running(make_client, db_path):
    with make_client(batch_size=1) as c:
        c.post("/t/feature", json=feature_payload())
        conn = open_readonly(db_path)
        assert conn.execute("SELECT COUNT(*) FROM counters").fetchone()[0] > 0
        c.post("/t/feature", json=feature_payload())
        assert conn.execute("SELECT SUM(count) FROM counters WHERE field = '_pings'").fetchone()[0] == 2
        conn.close()


def test_error_shares_from_feature_pings(seeded):
    conn = open_readonly(seeded)
    counts = Counts(conn, "appstore", "2026-11-01", "2026-11-07")
    conn.close()
    shares = error_shares(counts, SCHEMA)
    assert shares[0] == ("tls", 1, 0.5)
    assert ("timeout", 0, 0.0) in shares
    assert {e for e, _, _ in shares} == set(SCHEMA.errors)
    assert counts.values("health", "errors") == {}
