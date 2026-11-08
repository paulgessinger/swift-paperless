"""Wire models built from `telemetry-schema.json`, and payload splitting.

The schema file is the single source of truth for channels, bucket values,
device/auth values, and feature/error names. Nothing here hardcodes those lists.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Annotated, Any

from pydantic import (
    AfterValidator,
    BaseModel,
    ConfigDict,
    Field,
    StrictBool,
    StrictInt,
    StringConstraints,
    create_model,
)

# Repo layout default; the Docker image sets TELEMETRY_SCHEMA_PATH explicitly.
DEFAULT_SCHEMA_PATH = Path(__file__).resolve().parents[2] / "telemetry-schema.json"

# Upper bounds on list/dict sizes and name lengths. Generous relative to the
# schema so a newer app with a few more names is not rejected wholesale.
MAX_NAMES = 64
MAX_NAME_LENGTH = 64

PINGS_FIELD = "_pings"
PINGS_VALUE = "total"

# Oldest day a feature ping may report, in days before the server's UTC day.
MAX_FEATURE_DAY_AGE = 30

Name = Annotated[str, StringConstraints(max_length=MAX_NAME_LENGTH)]


def _one_of(values: list[str]) -> Any:
    """A strict string restricted to `values` (loaded at runtime, so not expressible as a Literal)."""
    allowed = frozenset(values)

    def check(value: str) -> str:
        if value not in allowed:
            raise ValueError("value not in schema")
        return value

    return Annotated[str, AfterValidator(check)]


def _pattern(regex: str) -> Any:
    return Annotated[str, StringConstraints(pattern=regex)]


def _optional(field_type: Any) -> Any:
    return field_type | None


def _bucket_map(values: list[str]) -> Any:
    return Annotated[dict[Name, _one_of(values)], Field(max_length=MAX_NAMES)]


# Typed Any: create_model takes field types as values, which a type checker cannot follow.
_NAMES: Any = Annotated[list[Name], Field(max_length=MAX_NAMES)]
_API: Any = Annotated[StrictInt, Field(ge=1, le=10_000)]


@dataclass(frozen=True)
class Schema:
    channels: tuple[str, ...]
    count_buckets: tuple[str, ...]
    features: tuple[str, ...]  # schema order
    errors: tuple[str, ...]
    health_model: type[BaseModel]
    feature_model: type[BaseModel]

    @property
    def environment_fields(self) -> list[str]:
        """Scalar health fields, in model order (everything except channel)."""
        return [f for f in self.health_model.model_fields if f != "channel"]

    @property
    def optional_fields(self) -> set[str]:
        """Health fields the client omits when unknown."""
        return {name for name, f in self.health_model.model_fields.items() if not f.is_required()}

    def split_health(self, ping: BaseModel) -> list[tuple[str, str]]:
        """(field, value) increments for one health ping."""
        data = ping.model_dump(exclude_none=True)
        out = [(PINGS_FIELD, PINGS_VALUE)]
        for name, value in data.items():
            if name == "channel":
                continue
            if isinstance(value, bool):
                value = "true" if value else "false"
            out.append((name, str(value)))
        return out

    def split_feature(self, ping: BaseModel) -> list[tuple[str, str]]:
        """(field, value) increments for one feature ping. Unknown feature and error names are dropped."""
        data = ping.model_dump()
        out = [(PINGS_FIELD, PINGS_VALUE)]
        for name, bucket in sorted(data["features"].items()):
            if name in self.features:
                out.append((f"feature:{name}", bucket))
        for name in sorted(set(data["available"])):
            if name in self.features:
                out.append((f"available:{name}", "true"))
        # Deduplicated: a ping counts each error class at most once.
        for error in sorted(set(data["errors"] or ())):
            if error in self.errors:
                out.append(("errors", error))
        return out


def feature_day_valid(day: str, today: str) -> bool:
    """Whether a feature ping's `day` is a real date before `today` and at most MAX_FEATURE_DAY_AGE days back."""
    try:
        age = (date.fromisoformat(today) - date.fromisoformat(day)).days
    except ValueError:
        return False
    return 1 <= age <= MAX_FEATURE_DAY_AGE


def load_schema(path: Path | None = None) -> Schema:
    raw = json.loads((path or DEFAULT_SCHEMA_PATH).read_text())
    config = ConfigDict(extra="forbid", strict=True)
    channel = _one_of(raw["channels"])
    buckets = raw["buckets"]

    # Field types come from the schema file, so the models are built with create_model.
    health_model = create_model(
        "HealthPing",
        __config__=config,
        channel=(channel, ...),
        app=(_pattern(r"^\d{1,4}(\.\d{1,4}){1,2}$"), ...),
        ios=(_pattern(r"^\d{1,3}\.\d{1,3}$"), ...),
        device=(_one_of(raw["device"]), ...),
        lang=(_pattern(r"^[a-z]{2,3}$"), ...),
        backend=(_optional(_pattern(r"^(\d{1,4}\.\d{1,4}\.\d{1,4}|other)$")), None),
        api=(_optional(_API), None),
        docs=(_optional(_one_of(buckets["docs"])), None),
        auth=(_optional(_one_of(raw["auth"])), None),
        client_cert=(StrictBool, ...),
        custom_headers=(StrictBool, ...),
        servers=(_one_of(buckets["servers"]), ...),
        active_days_30=(_one_of(buckets["active_days_30"]), ...),
        install_age=(_one_of(buckets["install_age"]), ...),
    )
    feature_model = create_model(
        "FeaturePing",
        __config__=config,
        channel=(channel, ...),
        # Shape only; app.py checks it is a real, recent past day (needs the server's day).
        day=(_pattern(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"), ...),
        features=(_bucket_map(buckets["count"]), ...),
        available=(_NAMES, ...),
        errors=(_optional(_NAMES), None),
    )

    return Schema(
        channels=tuple(raw["channels"]),
        count_buckets=tuple(raw["buckets"]["count"]),
        features=tuple(raw["features"]),
        errors=tuple(raw["errors"]),
        health_model=health_model,
        feature_model=feature_model,
    )
