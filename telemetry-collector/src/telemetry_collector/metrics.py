"""Operational Prometheus metrics, served on a separate private listener.

Rule: no metric or label may be derived from payload content (no field, value,
feature, error, version or channel labels). A ~15 s scrape of a content counter
would be a per-request time series of payload values.
"""

from __future__ import annotations

from prometheus_client import Counter, Gauge, Histogram

REQUESTS = Counter(
    "telemetry_requests",
    "Ingest requests by endpoint and outcome",
    ["endpoint", "outcome"],  # endpoint: health|feature; outcome: accepted|rejected_400|too_large
)
WRITES = Counter("telemetry_writes", "Counter write transactions, one per accepted ping", ["result"])  # ok|error
ROWS_WRITTEN = Counter("telemetry_rows_written", "Counter rows upserted")
LAST_WRITE = Gauge("telemetry_last_write_timestamp_seconds", "Unix time of the last successful write")
WRITE_DURATION = Histogram(
    "telemetry_write_duration_seconds",
    "Duration of a write transaction plus WAL checkpoint",
    buckets=(0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1.0, 5.0),
)
DB_SIZE = Gauge("telemetry_db_size_bytes", "Size of the SQLite database file")

for _endpoint in ("health", "feature"):
    for _outcome in ("accepted", "rejected_400", "too_large"):
        REQUESTS.labels(_endpoint, _outcome)
for _result in ("ok", "error"):
    WRITES.labels(_result)
