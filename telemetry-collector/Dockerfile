# syntax=docker/dockerfile:1
FROM python:3.13-slim AS build
COPY --from=ghcr.io/astral-sh/uv:0.9 /uv /bin/uv
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PYTHON_DOWNLOADS=never
WORKDIR /app
COPY pyproject.toml uv.lock README.md ./
RUN uv sync --frozen --no-dev --no-install-project
COPY src ./src
RUN uv sync --frozen --no-dev --no-editable

FROM python:3.13-slim
RUN useradd --system --uid 10001 --home-dir /nonexistent collector \
 && mkdir /data && chown collector /data
COPY --from=build /app/.venv /app/.venv
COPY telemetry-schema.json /app/telemetry-schema.json
ENV PATH=/app/.venv/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TELEMETRY_SCHEMA_PATH=/app/telemetry-schema.json \
    TELEMETRY_DB_PATH=/data/telemetry.sqlite3 \
    TELEMETRY_HOST=0.0.0.0 \
    PORT=5000
USER collector
VOLUME /data
# Dokku maps http:80 to this port; a PORT set at runtime overrides it.
EXPOSE 5000
# exec form: uvicorn is PID 1 and receives SIGTERM directly, so it shuts down gracefully.
CMD ["telemetry-collector-serve"]
