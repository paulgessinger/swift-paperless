"""Operational Prometheus metrics, served on a separate private listener.

Rule: no metric or label may be derived from payload content (no field, value,
feature, error, version or channel labels). A ~15 s scrape of a content counter
would be a per-request time series and undo the batched-write decorrelation.
"""

from __future__ import annotations

from prometheus_client import Counter, Gauge, Histogram

REQUESTS = Counter(
    "telemetry_requests",
    "Ingest requests by endpoint and outcome",
    ["endpoint", "outcome"],  # endpoint: health|feature; outcome: accepted|rejected_400|too_large
)
FLUSHES = Counter("telemetry_flushes", "Counter buffer flushes", ["result"])  # ok|error
ROWS_WRITTEN = Counter("telemetry_rows_written", "Counter rows upserted by flushes")
LAST_FLUSH = Gauge("telemetry_last_flush_timestamp_seconds", "Unix time of the last successful flush")
FLUSH_DURATION = Histogram(
    "telemetry_flush_duration_seconds",
    "Duration of a flush transaction plus WAL checkpoint",
    buckets=(0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1.0, 5.0),
)
BUFFERED_PINGS = Gauge("telemetry_buffered_pings", "Pings currently held in the in-memory buffer")
DB_SIZE = Gauge("telemetry_db_size_bytes", "Size of the SQLite database file")

for _endpoint in ("health", "feature"):
    for _outcome in ("accepted", "rejected_400", "too_large"):
        REQUESTS.labels(_endpoint, _outcome)
for _result in ("ok", "error"):
    FLUSHES.labels(_result)
