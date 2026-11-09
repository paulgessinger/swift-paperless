from __future__ import annotations

import sqlite3

import pytest
from conftest import feature_payload, health_payload

from telemetry_collector.report import (
    UNKNOWN,
    Counts,
    PeriodCount,
    active_installs,
    completion_pairs,
    distribution,
    error_shares,
    open_readonly,
    period_start,
    periods_start,
    render,
)
from telemetry_collector.schema import load_schema

SCHEMA = load_schema()


@pytest.fixture
def seeded(make_client, db_path, clock):
    with make_client() as c:
        clock.day = "2026-11-06"
        c.post("/t/health", json=health_payload(active_days_30="1", first_month=True, first_week=True))
        clock.day = "2026-11-07"
        c.post("/t/health", json=health_payload(active_days_30="2-7", auth=None, backend=None, first_month=False))
        c.post("/t/health", json=health_payload(active_days_30="2-7", auth="none", first_month=True))
        assert c.post("/t/feature", json=feature_payload(day="2026-11-06")).status_code == 204
        assert c.post("/t/feature", json=feature_payload(day="2026-11-06", features={}, errors=None)).status_code == 204
    return db_path


def test_report(seeded):
    conn = open_readonly(seeded)
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
    assert "MAU" not in out
    # 2026-11-07 is a Saturday in 2026-W45, which started on Monday 11-02.
    assert "== Active installs appstore this month (2026-11, 2026-11-01 to 2026-11-07, still filling in): 2" in out
    assert "== Active installs appstore this week (2026-W45, 2026-11-02 to 2026-11-07, still filling in): 1" in out


def test_period_starts():
    assert period_start("month", "2026-11-09") == "2026-11-01"
    # Sunday and Monday.
    assert period_start("week", "2026-11-08") == "2026-11-02"
    assert period_start("week", "2026-11-09") == "2026-11-09"
    # Thursday 2026-10-01's week starts in September.
    assert periods_start("2026-10-01") == "2026-09-28"
    assert periods_start("2026-11-20") == "2026-11-01"


def test_iso_weeks_and_months_across_the_year(make_client, db_path, clock):
    with make_client() as c:
        for day in ("2026-12-31", "2027-01-01", "2027-01-04"):
            clock.day = day
            c.post("/t/health", json=health_payload(first_month=True, first_week=True))
    conn = open_readonly(db_path)
    counts = Counts(conn, "appstore", "2026-12-01", "2027-01-04")
    conn.close()
    # Thursday 2026-12-31 and Friday 2027-01-01 share 2026-W53.
    assert active_installs(counts, "week", "2026-12-31", "2027-01-04") == [
        PeriodCount("2026-W53", "2026-12-28", 2, False),
        PeriodCount("2027-W01", "2027-01-04", 1, True),
    ]
    assert active_installs(counts, "month", "2026-12-31", "2027-01-04") == [
        PeriodCount("2026-12", "2026-12-01", 1, False),
        PeriodCount("2027-01", "2027-01-01", 2, True),
    ]


def test_report_counts_the_whole_month_and_week(make_client, db_path, clock):
    """The CLI loads counts back to the period starts, even for a short --days."""
    with make_client() as c:
        for day in ("2026-09-30", "2026-10-01", "2026-10-02"):
            clock.day = day
            c.post("/t/health", json=health_payload(first_month=True, first_week=True))
    conn = open_readonly(db_path)
    out = render(conn, SCHEMA, days=1, until="2026-10-02")
    conn.close()
    assert "this month (2026-10, 2026-10-01 to 2026-10-02, still filling in): 2" in out
    # 2026-09-28 is the Monday of 2026-W40.
    assert "this week (2026-W40, 2026-09-28 to 2026-10-02, still filling in): 3" in out


def test_active_installs_per_period(make_client, db_path, clock):
    pings = {
        # Sunday 2026-11-01 ends 2026-W44; Monday 2026-11-02 starts 2026-W45.
        "2026-10-31": [(True, True), (False, False)],
        "2026-11-01": [(True, False)],
        "2026-11-02": [(False, True), (False, True)],
        "2026-11-09": [(False, True)],
    }
    with make_client() as c:
        for day, flags in pings.items():
            clock.day = day
            for month, week in flags:
                c.post("/t/health", json=health_payload(first_month=month, first_week=week))
    conn = open_readonly(db_path)
    counts = Counts(conn, "appstore", periods_start("2026-10-29"), "2026-11-09")
    conn.close()
    assert active_installs(counts, "month", "2026-10-29", "2026-11-09") == [
        PeriodCount("2026-10", "2026-10-01", 1, False),
        PeriodCount("2026-11", "2026-11-01", 1, True),
    ]
    assert active_installs(counts, "week", "2026-10-29", "2026-11-09") == [
        PeriodCount("2026-W44", "2026-10-26", 1, False),
        PeriodCount("2026-W45", "2026-11-02", 2, False),
        PeriodCount("2026-W46", "2026-11-09", 1, True),
    ]
    # A period is counted only through `end`.
    assert active_installs(counts, "week", "2026-11-02", "2026-11-02") == [
        PeriodCount("2026-W45", "2026-11-02", 2, True)
    ]


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
    with make_client() as c:
        c.post("/t/feature", json=feature_payload())
    conn = open_readonly(db_path)
    assert "!! implausible: 1 feature pings vs 0 health pings" in render(conn, SCHEMA)
    conn.close()


def test_report_readonly(make_client, db_path):
    with make_client() as c:
        c.post("/t/feature", json=feature_payload())
    conn = open_readonly(db_path)
    with pytest.raises(sqlite3.OperationalError):
        conn.execute("DELETE FROM counters")
    conn.close()


def test_readonly_reader_while_collector_running(make_client, db_path):
    with make_client() as c:
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
