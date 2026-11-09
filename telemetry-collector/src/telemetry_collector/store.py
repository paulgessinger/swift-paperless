"""Counter storage: each accepted ping's increments are upserted in their own transaction."""

from __future__ import annotations

import logging
import sqlite3
import time
from collections.abc import Iterable
from datetime import UTC, datetime
from pathlib import Path

from . import metrics

log = logging.getLogger(__name__)

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS counters (
  day     TEXT NOT NULL,
  channel TEXT NOT NULL,
  ping    TEXT NOT NULL,
  field   TEXT NOT NULL,
  value   TEXT NOT NULL,
  count   INTEGER NOT NULL,
  PRIMARY KEY (day, channel, ping, field, value)
) WITHOUT ROWID;
"""

UPSERT_SQL = """
INSERT INTO counters (day, channel, ping, field, value, count) VALUES (?, ?, ?, ?, ?, 1)
ON CONFLICT (day, channel, ping, field, value) DO UPDATE SET count = count + 1
"""


def utc_today() -> str:
    return datetime.now(UTC).strftime("%Y-%m-%d")


def connect(path: Path) -> sqlite3.Connection:
    """Open the collector's connection. Use it from the thread that opened it only (the event loop)."""
    conn = sqlite3.connect(path, isolation_level=None)
    # Waits instead of failing if another writer (e.g. an overlapping deploy) holds the lock.
    conn.execute("PRAGMA busy_timeout=5000")
    conn.execute("PRAGMA journal_mode=WAL")
    # Overwrite freed content so superseded counter pages don't linger in the file.
    conn.execute("PRAGMA secure_delete=ON")
    conn.execute(SCHEMA_SQL)
    return conn


def write_ping(
    conn: sqlite3.Connection, day: str, channel: str, ping: str, increments: Iterable[tuple[str, str]]
) -> None:
    """Add one to each `(field, value)` counter under `day`, in one transaction.

    On failure the transaction is rolled back, nothing is written, and the
    `sqlite3.Error` is re-raised.
    """
    rows = [(day, channel, ping, field, value) for field, value in increments]
    started = time.perf_counter()
    try:
        conn.execute("BEGIN IMMEDIATE")
        conn.executemany(UPSERT_SQL, rows)
        conn.execute("COMMIT")
    except sqlite3.Error:
        if conn.in_transaction:
            conn.execute("ROLLBACK")
        log.exception("counter write failed")
        metrics.WRITES.labels("error").inc()
        raise
    # Moves the write into the database file and empties the WAL. Best effort:
    # while a dashboard read is open it may not complete, and the next write retries.
    conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    metrics.WRITE_DURATION.observe(time.perf_counter() - started)
    metrics.WRITES.labels("ok").inc()
    metrics.ROWS_WRITTEN.inc(len(rows))
    metrics.LAST_WRITE.set(time.time())
