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
    # Waits briefly if another writer (e.g. an overlapping deploy) holds the lock.
    # The write runs on the event loop, so this bounds the stall for every
    # request; past it the ping gets a 503 and the app retries on a later open.
    conn.execute("PRAGMA busy_timeout=250")
    conn.execute("PRAGMA journal_mode=WAL")
    # Overwrite freed content so superseded counter pages don't linger in the file.
    conn.execute("PRAGMA secure_delete=ON")
    # secure_delete does not reach the WAL, and a PASSIVE checkpoint never
    # shrinks it: without a limit, frames past the current transaction keep
    # older images of pages the last ping rewrote.
    conn.execute("PRAGMA journal_size_limit=0")
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
    # The ping is committed: a checkpoint problem must neither fail the request
    # nor block the event loop. PASSIVE never waits on readers; pages it can't
    # copy while a dashboard read is open are copied by a later write.
    try:
        conn.execute("PRAGMA wal_checkpoint(PASSIVE)")
    except sqlite3.Error:
        log.warning("WAL checkpoint failed", exc_info=True)
        metrics.CHECKPOINT_FAILURES.inc()
    metrics.WRITE_DURATION.observe(time.perf_counter() - started)
    metrics.WRITES.labels("ok").inc()
    metrics.ROWS_WRITTEN.inc(len(rows))
    metrics.LAST_WRITE.set(time.time())
