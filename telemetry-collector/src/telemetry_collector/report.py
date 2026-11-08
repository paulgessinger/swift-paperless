"""Read-only analytics over the counters table, shared by the CLI report and the dashboard."""

from __future__ import annotations

import sqlite3
from collections import defaultdict
from dataclasses import dataclass
from datetime import date, timedelta
from pathlib import Path
from typing import Literal

from .schema import PINGS_FIELD, PINGS_VALUE, Schema

# Feature pings report a day when the install next opens the app, so the
# latest days' feature and error counts keep growing for about this long.
FILLING_DAYS = 7
# Feature pings above this multiple of health pings on a day are flagged.
IMPLAUSIBLE_RATIO = 1.5


def open_readonly(path: Path) -> sqlite3.Connection:
    """Read-only connection. In WAL mode SQLite still needs the -shm file, so the directory must be writable."""
    return sqlite3.connect(f"{path.resolve().as_uri()}?mode=ro", uri=True)


def day_range(end: str, days: int) -> list[str]:
    last = date.fromisoformat(end)
    return [(last - timedelta(days=i)).isoformat() for i in range(days - 1, -1, -1)]


def latest_day(conn: sqlite3.Connection) -> str | None:
    return conn.execute("SELECT MAX(day) FROM counters").fetchone()[0]


def channels_present(conn: sqlite3.Connection) -> list[str]:
    return [r[0] for r in conn.execute("SELECT DISTINCT channel FROM counters ORDER BY channel")]


class Counts:
    """Counters for one channel over a day range, indexed day -> ping -> field -> value -> count."""

    def __init__(self, conn: sqlite3.Connection, channel: str, start: str, end: str) -> None:
        self.channel = channel
        self.start = start
        self.end = end
        self.data: dict[str, dict[str, dict[str, dict[str, int]]]] = defaultdict(
            lambda: defaultdict(lambda: defaultdict(dict))
        )
        rows = conn.execute(
            "SELECT day, ping, field, value, count FROM counters WHERE channel = ? AND day BETWEEN ? AND ?",
            (channel, start, end),
        )
        for day, ping, field, value, count in rows:
            self.data[day][ping][field][value] = count

    def days(self) -> list[str]:
        return sorted(self.data)

    def values(self, ping: str, field: str, start: str | None = None, end: str | None = None) -> dict[str, int]:
        """Value -> count for one field, summed over [start, end] (default: the whole range)."""
        out: dict[str, int] = defaultdict(int)
        for day, pings in self.data.items():
            if (start and day < start) or (end and day > end):
                continue
            for value, n in pings.get(ping, {}).get(field, {}).items():
                out[value] += n
        return dict(out)

    def fields(self, ping: str) -> set[str]:
        return {f for pings in self.data.values() for f in pings.get(ping, {})}

    def pings(self, ping: str, day: str | None = None) -> int:
        if day is not None:
            return self.data.get(day, {}).get(ping, {}).get(PINGS_FIELD, {}).get(PINGS_VALUE, 0)
        return self.values(ping, PINGS_FIELD).get(PINGS_VALUE, 0)

    def pings_in(self, ping: str, start: str, end: str) -> int:
        return self.values(ping, PINGS_FIELD, start, end).get(PINGS_VALUE, 0)

    def daily_pings(self, ping: str, days: list[str]) -> list[int]:
        return [self.pings(ping, d) for d in days]


Period = Literal["month", "week"]


def period_start(period: Period, day: str) -> str:
    """The first day of `day`'s UTC month, or the Monday of its ISO week."""
    d = date.fromisoformat(day)
    return (d.replace(day=1) if period == "month" else d - timedelta(days=d.weekday())).isoformat()


def _next_period_start(period: Period, start: str) -> str:
    d = date.fromisoformat(start)
    if period == "week":
        return (d + timedelta(days=7)).isoformat()
    return (d.replace(year=d.year + 1, month=1) if d.month == 12 else d.replace(month=d.month + 1)).isoformat()


def _period_last(period: Period, start: str, end: str) -> str:
    """The last day of the period starting on `start`, or `end` if that is earlier."""
    following = date.fromisoformat(_next_period_start(period, start))
    return min((following - timedelta(days=1)).isoformat(), end)


def _period_label(period: Period, start: str) -> str:
    if period == "month":
        return start[:7]
    year, week, _ = date.fromisoformat(start).isocalendar()
    return f"{year}-W{week:02d}"


def periods_start(day: str) -> str:
    """The first day Counts must cover for the month and the week containing `day` to be complete."""
    return min(period_start("month", day), period_start("week", day))


@dataclass(frozen=True)
class PeriodCount:
    label: str  # `yyyy-MM` or ISO `YYYY-Www`
    start: str
    count: int
    filling: bool  # the period contains `end`, so it isn't over


def active_installs(counts: Counts, period: Period, start: str, end: str) -> list[PeriodCount]:
    """Active installs per month or ISO week overlapping [start, end]: health pings with
    `first_<period>=true`, each period counted from its first day through its last or `end`.

    Counts must cover the first period's first day (see `periods_start`).
    """
    out = []
    current = period_start(period, start)
    while current <= end:
        following = _next_period_start(period, current)
        last = _period_last(period, current, end)
        n = counts.values("health", f"first_{period}", current, last).get("true", 0)
        out.append(PeriodCount(_period_label(period, current), current, n, following > end))
        current = following
    return out


def average_active_days(counts: Counts, period: Period, active: PeriodCount, end: str) -> float | None:
    """Days an active install of `active` was active on average: its health pings from the
    period's first day through its last or `end`, over its active installs. An install sends
    at most one health ping per UTC day. None without active installs.
    """
    if not active.count:
        return None
    return counts.pings_in("health", active.start, _period_last(period, active.start, end)) / active.count


UNKNOWN = "unknown"


def distribution(
    counts: Counts, schema: Schema, field: str, start: str | None = None, end: str | None = None
) -> dict[str, int]:
    """Value -> health pings for one environment field over [start, end].

    For optional fields, pings that omitted the field are derived as `unknown`
    (health pings minus the field's counted values). Clients never send it.
    """
    values = counts.values("health", field, start, end)
    if field in schema.optional_fields:
        pings = counts.values("health", PINGS_FIELD, start, end).get(PINGS_VALUE, 0)
        missing = pings - sum(values.values())
        if missing > 0:
            values[UNKNOWN] = missing
    return values


@dataclass(frozen=True)
class FeatureStat:
    name: str
    used: int  # install-days with any use
    available: int  # install-days where the feature was available
    buckets: dict[str, int]

    @property
    def ratio(self) -> float | None:
        return self.used / self.available if self.available else None

    @property
    def unused(self) -> bool:
        return self.available > 0 and self.used == 0


def feature_stats(
    counts: Counts, features: list[str], start: str | None = None, end: str | None = None
) -> list[FeatureStat]:
    out = []
    for name in features:
        buckets = counts.values("feature", f"feature:{name}", start, end)
        available = counts.values("feature", f"available:{name}", start, end).get("true", 0)
        out.append(FeatureStat(name, sum(buckets.values()), available, buckets))
    return out


def daily_feature_ratios(counts: Counts, features: list[str], days: list[str]) -> dict[str, list[float | None]]:
    """Per feature, used/available install-days for each day (None where it was not available)."""
    out: dict[str, list[float | None]] = {}
    for name in features:
        series: list[float | None] = []
        for day in days:
            pings = counts.data.get(day, {}).get("feature", {})
            used = sum(pings.get(f"feature:{name}", {}).values())
            available = pings.get(f"available:{name}", {}).get("true", 0)
            series.append(used / available if available else None)
        out[name] = series
    return out


def error_shares(
    counts: Counts, schema: Schema, start: str | None = None, end: str | None = None
) -> list[tuple[str, int, float | None]]:
    """(error, install-days, share of feature pings) over [start, end], most frequent first."""
    errors = counts.values("feature", "errors", start, end)
    pings = counts.values("feature", PINGS_FIELD, start, end).get(PINGS_VALUE, 0)
    return [
        (e, errors.get(e, 0), errors.get(e, 0) / pings if pings else None)
        for e in sorted(schema.errors, key=lambda e: -errors.get(e, 0))
    ]


def completion_pairs(features: list[str]) -> list[tuple[str, str]]:
    """(`x_started`, `x_<done>`) pairs from the schema's feature names."""
    pairs = []
    for name in features:
        if name.endswith("_started"):
            prefix = name.removesuffix("started")
            pairs += [(name, other) for other in features if other.startswith(prefix) and other != name]
    return pairs


def implausible_days(counts: Counts) -> list[tuple[str, int, int]]:
    """(day, feature pings, health pings) for days where feature pings far exceed health pings."""
    out = []
    for day in counts.days():
        health, feature = counts.pings("health", day), counts.pings("feature", day)
        if (health and feature > IMPLAUSIBLE_RATIO * health) or (feature and not health):
            out.append((day, feature, health))
    return out


def render(
    conn: sqlite3.Connection, schema: Schema, days: int = 7, channel: str | None = None, until: str | None = None
) -> str:
    until = until or latest_day(conn)
    if until is None:
        return "no data\n"
    shown = set(day_range(until, days))
    start = min(min(shown), periods_start(until))
    features = list(schema.features)
    lines = [f"(feature and error counts for the last {FILLING_DAYS} days are still filling in)"]
    for ch in [channel] if channel else channels_present(conn):
        counts = Counts(conn, ch, start, until)
        flagged = {d for d, _, _ in implausible_days(counts)}
        for day in counts.days():
            if day not in shown:
                continue
            lines.append(f"== {day}  channel={ch}")
            for ping in ("feature", "health"):
                if not counts.pings(ping, day):
                    continue
                lines.append(f"  [{ping}] pings={counts.pings(ping, day)}")
                for field in sorted(counts.fields(ping) - {PINGS_FIELD}):
                    values = counts.values(ping, field, day, day)
                    if values:
                        lines.append(f"    {field}: " + ", ".join(f"{v}={n}" for v, n in sorted(values.items())))
            stats = [s for s in feature_stats(counts, features, day, day) if s.used or s.available]
            if stats:
                lines.append("  [used/available]")
                for s in stats:
                    ratio = f"{s.ratio:.0%}" if s.ratio is not None else "n/a"
                    lines.append(f"    {s.name}: {s.used}/{s.available} ({ratio})")
            if day in flagged:
                feature_n, health_n = counts.pings("feature", day), counts.pings("health", day)
                lines.append(f"  !! implausible: {feature_n} feature pings vs {health_n} health pings")
        for period in ("month", "week"):
            (p,) = active_installs(counts, period, until, until)
            line = (
                f"== Active installs {ch} this {period} ({p.label}, {p.start} to {until}, still filling in): {p.count}"
            )
            if period == "month":
                avg = average_active_days(counts, period, p, until)
                line += ", average active days per install: " + ("—" if avg is None else f"{avg:.1f}")
            lines.append(line)
    return "\n".join(lines) + "\n"
