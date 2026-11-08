from __future__ import annotations

import json
import re
from pathlib import Path

from conftest import feature_payload, health_payload
from prometheus_client import REGISTRY, generate_latest

from telemetry_collector.schema import DEFAULT_SCHEMA_PATH


def test_metrics_carry_no_payload_content(make_client):
    schema = json.loads(Path(DEFAULT_SCHEMA_PATH).read_text())
    with make_client(batch_size=2) as c:
        c.post("/t/health", json=health_payload(channel="testflight", errors=list(schema["errors"])))
        c.post(
            "/t/feature",
            json=feature_payload(features={n: "1" for n in schema["features"]}, available=schema["features"]),
        )
        c.post("/t/health", json=health_payload(device="Android"))
        c.post("/t/feature", json=feature_payload())
        # The public app does not serve metrics.
        assert c.get("/metrics").status_code == 404
        text = generate_latest(REGISTRY).decode()

    assert "telemetry_requests_total" in text
    assert "telemetry_flushes_total" in text
    assert "channel" not in text
    for name in [*schema["features"], *schema["errors"], *schema["channels"], *schema["auth"], *schema["device"]]:
        assert f'"{name}"' not in text, name
    for version in ("1.11.2", "18.3", "2.14.3"):
        assert version not in text
    # Every label value is one of the allowed operational values.
    allowed = {"health", "feature", "accepted", "rejected_400", "too_large", "ok", "error"}
    for value in re.findall(r'(?:endpoint|outcome|result)="([^"]*)"', text):
        assert value in allowed
