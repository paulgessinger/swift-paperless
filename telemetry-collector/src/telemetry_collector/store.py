"""Counter storage with batched writes.

Writing each ping in its own transaction would leave the combined payload
recoverable from the WAL or from two snapshots one ping apart. Counters are
therefore buffered in memory and written in one transaction per `batch_size`
pings, and before the first ping of a new UTC day. There is no time-based flush.
"""

from __future__ import annotations

import logging
import sqlite3
import threading
import time
from collections import Counter
from collections.abc import Callable, Iterable
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
INSERT INTO counters (day, channel, ping, field, value, count) VALUES (?, ?, ?, ?, ?, ?)
ON CONFLICT (day, channel, ping, field, value) DO UPDATE SET count = count + excluded.count
"""

Key = tuple[str, str, str, str, str]  # day, channel, ping, field, value


def utc_today() -> str:
    return datetime.now(UTC).strftime("%Y-%m-%d")


def connect(path: Path) -> sqlite3.Connection:
    # check_same_thread=False: the lock in CounterStore serialises all use.
    conn = sqlite3.connect(path, check_same_thread=False, isolation_level=None)
    # Waits instead of failing if another writer (e.g. an overlapping deploy) holds the lock.
    conn.execute("PRAGMA busy_timeout=5000")
    conn.execute("PRAGMA journal_mode=WAL")
    # Overwrite freed content so superseded counter pages don't linger in the file.
    conn.execute("PRAGMA secure_delete=ON")
    conn.execute(SCHEMA_SQL)
    return conn


class CounterStore:
    """In-memory counter buffer in front of the SQLite `counters` table.

    Every buffer key carries its own day, so a flush never misattributes counts.
    A threading lock guards the buffer and the connection. The endpoints are
    async and run on the single event-loop thread, so the lock is uncontended
    there; it keeps the class correct if it is ever called from a thread pool
    (sync endpoints, tests). A flush holds the lock across a short blocking
    SQLite write, which is acceptable at a few hundred pings per day.
    """

    def __init__(
        self,
        conn: sqlite3.Connection,
        batch_size: int = 20,
        today: Callable[[], str] = utc_today,
    ) -> None:
        if batch_size < 1:
            raise ValueError("batch_size must be >= 1")
        self._conn = conn
        self._batch_size = batch_size
        self._today = today
        self._lock = threading.Lock()
        self._buffer: Counter[Key] = Counter()
        self._pings = 0
        self._day: str | None = None

    @property
    def pending_pings(self) -> int:
        return self._pings

    def add(self, channel: str, ping: str, increments: Iterable[tuple[str, str]]) -> None:
        """Buffer one ping's increments; flushes per the batching rules."""
        with self._lock:
            day = self._today()
            if self._day is not None and day != self._day and self._pings:
                self._flush_locked()
            self._day = day
            for field, value in increments:
                self._buffer[(day, channel, ping, field, value)] += 1
            self._pings += 1
            if self._pings >= self._batch_size:
                self._flush_locked()

    def flush(self) -> None:
        with self._lock:
            self._flush_locked()

    def _flush_locked(self) -> None:
        if not self._buffer:
            self._pings = 0
            return
        rows = [(*key, n) for key, n in sorted(self._buffer.items())]
        started = time.perf_counter()
        try:
            self._conn.execute("BEGIN IMMEDIATE")
            self._conn.executemany(UPSERT_SQL, rows)
            self._conn.execute("COMMIT")
        except sqlite3.Error:
            if self._conn.in_transaction:
                self._conn.execute("ROLLBACK")
            # Buffer is kept and retried with the next flush.
            log.exception("counter flush failed")
            metrics.FLUSHES.labels("error").inc()
            return
        self._buffer.clear()
        self._pings = 0
        self._conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        metrics.FLUSH_DURATION.observe(time.perf_counter() - started)
        metrics.FLUSHES.labels("ok").inc()
        metrics.ROWS_WRITTEN.inc(len(rows))
        metrics.LAST_FLUSH.set(time.time())
