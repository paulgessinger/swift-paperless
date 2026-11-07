"""Server entrypoint. TELEMETRY_ROLE selects the public collector (default) or the dashboard."""

from __future__ import annotations

import logging
import os

import uvicorn
from fastapi import FastAPI


def _app() -> FastAPI:
    role = os.environ.get("TELEMETRY_ROLE", "collector")
    if role == "dashboard":
        from .dashboard import DashboardSettings, create_dashboard_app

        return create_dashboard_app(DashboardSettings.from_env())
    if role != "collector":
        raise SystemExit(f"unknown TELEMETRY_ROLE: {role}")

    from .app import create_app
    from .config import Settings

    metrics_port = os.environ.get("METRICS_PORT")
    if metrics_port:
        # Separate private listener (a daemon thread in this process); never behind the public proxy.
        from prometheus_client import start_http_server

        start_http_server(int(metrics_port), addr=os.environ.get("METRICS_HOST", "127.0.0.1"))
    return create_app(Settings.from_env())


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
    uvicorn.run(
        _app(),
        host=os.environ.get("TELEMETRY_HOST", "127.0.0.1"),
        # PORT is the Dokku convention; TELEMETRY_PORT overrides it.
        port=int(os.environ.get("TELEMETRY_PORT") or os.environ.get("PORT") or "8000"),
        workers=1,
        access_log=False,
        # Never derive a client address from forwarded headers.
        proxy_headers=False,
        server_header=False,
        date_header=False,
        # Keep uvicorn's default loggers from being configured; basicConfig above is enough.
        log_config=None,
        # Leaves time for the lifespan shutdown flush; Dokku's stop timeout must exceed it.
        timeout_graceful_shutdown=10,
    )


if __name__ == "__main__":
    main()
