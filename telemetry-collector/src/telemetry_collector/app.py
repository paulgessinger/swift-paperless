"""HTTP service: POST /t/health and POST /t/feature.

Privacy rules enforced here: request bodies are never logged or echoed (error
responses have empty bodies), the client address is never read, and the
combined payload is never stored; only per-field counters.
"""

from __future__ import annotations

from collections.abc import AsyncGenerator, Callable
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, Response
from fastapi.exceptions import RequestValidationError
from pydantic import BaseModel, ValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException

from . import metrics
from .config import MAX_BODY_BYTES, Settings
from .schema import Schema, feature_day_valid, load_schema
from .store import CounterStore, connect, utc_today


class _BodyTooLarge(Exception):
    pass


async def _read_capped(request: Request, limit: int) -> bytes:
    declared = request.headers.get("content-length")
    if declared is not None and (not declared.isdigit() or int(declared) > limit):
        raise _BodyTooLarge
    chunks: list[bytes] = []
    size = 0
    async for chunk in request.stream():
        size += len(chunk)
        if size > limit:
            raise _BodyTooLarge
        chunks.append(chunk)
    return b"".join(chunks)


def create_app(settings: Settings, today: Callable[[], str] = utc_today) -> FastAPI:
    schema: Schema = load_schema(settings.schema_path)

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncGenerator[None]:
        conn = connect(settings.db_path)
        store = CounterStore(conn, batch_size=settings.batch_size, today=today)
        app.state.store = store
        metrics.BUFFERED_PINGS.set_function(lambda: store.pending_pings)
        db_path = settings.db_path
        metrics.DB_SIZE.set_function(lambda: db_path.stat().st_size if db_path.exists() else 0)
        try:
            yield
        finally:
            # SIGTERM -> uvicorn graceful shutdown -> here. Writes the partial batch.
            store.flush()
            conn.close()

    docs = settings.dev
    app = FastAPI(
        lifespan=lifespan,
        docs_url="/docs" if docs else None,
        redoc_url=None,
        openapi_url="/openapi.json" if docs else None,
    )

    @app.exception_handler(RequestValidationError)
    async def _validation(_: Request, __: RequestValidationError) -> Response:
        return Response(status_code=400)

    @app.exception_handler(StarletteHTTPException)
    async def _http(_: Request, exc: StarletteHTTPException) -> Response:
        return Response(status_code=exc.status_code)

    async def ingest(request: Request, ping: str, model: type[BaseModel]) -> Response:
        try:
            body = await _read_capped(request, MAX_BODY_BYTES)
        except _BodyTooLarge:
            metrics.REQUESTS.labels(ping, "too_large").inc()
            return Response(status_code=413)
        try:
            payload = model.model_validate_json(body)
        except ValidationError:
            metrics.REQUESTS.labels(ping, "rejected_400").inc()
            return Response(status_code=400)
        fields = payload.model_dump(include={"channel", "day"})
        if ping == "health":
            day, split = today(), schema.split_health
        else:
            day, split = fields["day"], schema.split_feature
            if not feature_day_valid(day, today()):
                metrics.REQUESTS.labels(ping, "rejected_400").inc()
                return Response(status_code=400)
        request.app.state.store.add(day, fields["channel"], ping, split(payload))
        metrics.REQUESTS.labels(ping, "accepted").inc()
        return Response(status_code=204)

    @app.post("/t/health", status_code=204)
    async def health(request: Request) -> Response:
        return await ingest(request, "health", schema.health_model)

    @app.post("/t/feature", status_code=204)
    async def feature(request: Request) -> Response:
        return await ingest(request, "feature", schema.feature_model)

    return app
