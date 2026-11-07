"""Read-only analytics dashboard (separate app/process from the public collector).

Every page requires an OIDC session. Auth can only be disabled in dev mode.
The database is opened read-only per request.

The OIDC flow (state, nonce, PKCE, discovery, JWKS, ID token validation) is
Authlib's; the session cookie is Starlette's SessionMiddleware (itsdangerous).
This module only adds policy: who may sign in, the session lifetime, and
start-up checks.
"""

from __future__ import annotations

import hashlib
import logging
import mimetypes
import time
from collections.abc import Callable
from dataclasses import dataclass
from importlib.resources import files
from pathlib import Path
from typing import Any
from urllib.parse import urlencode

import httpx
from authlib.integrations.starlette_client import OAuth, OAuthError
from fastapi import FastAPI, Request, Response
from fastapi.exceptions import RequestValidationError
from fastapi.responses import HTMLResponse, RedirectResponse
from jinja2 import Environment, PackageLoader, StrictUndefined
from joserfc.errors import JoseError
from starlette.exceptions import HTTPException as StarletteHTTPException
from starlette.middleware.sessions import SessionMiddleware

from .config import DashboardSettings
from .report import (
    MAU_WINDOW_DAYS,
    UNKNOWN,
    Counts,
    completion_pairs,
    daily_feature_ratios,
    day_range,
    distribution,
    feature_stats,
    implausible_days,
    latest_day,
    mau_estimate,
    open_readonly,
)
from .schema import Schema, load_schema

log = logging.getLogger(__name__)

SESSION_COOKIE = "__Host-session"
SESSION_TTL = 2 * 3600
RANGES = (7, 30, 90)
SCOPES = "openid email profile groups"
# Failures of the OIDC exchange or ID token validation; all become a 400.
SIGN_IN_ERRORS = (OAuthError, JoseError, KeyError, ValueError)


def safe_next(target: str | None) -> str:
    """Only same-site absolute paths; anything else (//host, scheme, backslash) becomes /."""
    if not target or not target.startswith("/") or target.startswith("//") or "\\" in target:
        return "/"
    return target


class _LoginRequired(Exception):
    pass


CSP = (
    "default-src 'none'; script-src 'self'; style-src 'self'; "
    "base-uri 'none'; form-action 'self'; frame-ancestors 'none'"
)
SECURITY_HEADERS = {
    "Content-Security-Policy": CSP,
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
}
# Static URLs carry a content hash, so they can be cached until the content changes.
STATIC_CACHE = "private, max-age=31536000, immutable"


@dataclass(frozen=True)
class StaticFile:
    path: Path
    media_type: str
    version: str


def _static_files() -> dict[str, StaticFile]:
    """Every file under the package's static/ directory, keyed by its relative path."""
    root = Path(str(files(__package__ or "telemetry_collector") / "static"))
    out = {}
    for path in sorted(p for p in root.rglob("*") if p.is_file()):
        # Cache-busting fingerprint, not a security measure.
        version = hashlib.sha256(path.read_bytes()).hexdigest()[:12]
        media_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        if path.suffix == ".js":
            media_type = "text/javascript"
        out[path.relative_to(root).as_posix()] = StaticFile(path, media_type, version)
    return out


def _templates(static: dict[str, StaticFile]) -> Environment:
    env = Environment(
        loader=PackageLoader("telemetry_collector", "templates"),
        autoescape=True,
        undefined=StrictUndefined,
        trim_blocks=True,
        lstrip_blocks=True,
    )
    env.globals["static_url"] = lambda name: f"/static/{name}?v={static[name].version}"
    env.filters["pct"] = _pct
    return env


def create_dashboard_app(
    settings: DashboardSettings,
    transport: httpx.AsyncBaseTransport | None = None,
    clock: Callable[[], float] = time.time,
) -> FastAPI:
    """`transport` replaces the HTTP transport to the identity provider (tests)."""
    schema = load_schema(settings.schema_path)
    channels = [c for c in schema.channels if c != "dev" or settings.dev]

    app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
    static = _static_files()
    templates = _templates(static)

    def render(name: str, status: int = 200, **context: Any) -> HTMLResponse:
        return HTMLResponse(templates.get_template(name).render(**context), status)

    oauth = OAuth()
    if settings.auth_enabled:
        client_kwargs: dict[str, Any] = {"scope": SCOPES, "code_challenge_method": "S256"}
        if transport is not None:
            client_kwargs["transport"] = transport
        oauth.register(
            "oidc",
            client_id=settings.client_id,
            client_secret=settings.client_secret.get_secret_value(),
            server_metadata_url=settings.issuer.rstrip("/") + "/.well-known/openid-configuration",
            client_kwargs=client_kwargs,
        )
        # Holds the login transaction (Authlib's state/nonce/PKCE data) and, after sign-in, the user.
        app.add_middleware(
            SessionMiddleware,
            secret_key=settings.session_secret.get_secret_value(),
            session_cookie=SESSION_COOKIE,
            max_age=SESSION_TTL,
            path="/",
            same_site="lax",
            https_only=True,
        )

    @app.middleware("http")
    async def _headers(request: Request, call_next: Callable[..., Any]) -> Response:
        response = await call_next(request)
        response.headers.update(SECURITY_HEADERS)
        response.headers.setdefault("Cache-Control", "no-store")
        return response

    @app.exception_handler(_LoginRequired)
    async def _login(request: Request, _: _LoginRequired) -> Response:
        target = request.url.path + (f"?{request.url.query}" if request.url.query else "")
        return RedirectResponse("/login?" + urlencode({"next": target}), status_code=303)

    @app.exception_handler(RequestValidationError)
    async def _invalid(_: Request, __: RequestValidationError) -> Response:
        return Response(status_code=400)

    @app.exception_handler(StarletteHTTPException)
    async def _http(_: Request, exc: StarletteHTTPException) -> Response:
        return Response(status_code=exc.status_code)

    def user(request: Request) -> dict[str, Any]:
        if not settings.auth_enabled:
            return {"sub": "dev mode (auth off)"}
        session_user = request.session.get("user")
        # The cookie's own max_age is enforced by the browser only; this bounds a replayed cookie too.
        if (
            not isinstance(session_user, dict)
            or not isinstance(session_user.get("exp"), (int, float))
            or session_user["exp"] < clock()
        ):
            request.session.pop("user", None)
            raise _LoginRequired
        return session_user

    def failure(status: int, message: str) -> HTMLResponse:
        return render("message.html", status, title="Sign-in failed", message=message, link_text="Try again")

    async def check_issuer() -> None:
        # Discovery §4.3: the advertised issuer must equal the configured one;
        # Authlib then validates the ID token's iss against it.
        metadata = await oauth.oidc.load_server_metadata()
        if metadata.get("issuer") != settings.issuer:
            raise ValueError("discovery issuer mismatch")

    @app.get("/login")
    async def login(request: Request, next: str = "/") -> Response:
        if not settings.auth_enabled:
            return RedirectResponse("/", status_code=303)
        request.session.clear()
        try:
            await check_issuer()
            response = await oauth.oidc.authorize_redirect(request, settings.redirect_uri)
        except (httpx.HTTPError, ValueError) as exc:
            log.warning("discovery failed: %s", type(exc).__name__)
            return failure(502, "The identity provider is unreachable or misconfigured.")
        request.session["next"] = safe_next(next)
        return response

    @app.get("/auth/callback")
    async def callback(request: Request) -> Response:
        if not settings.auth_enabled:
            return RedirectResponse("/", status_code=303)
        try:
            await check_issuer()
            token = await oauth.oidc.authorize_access_token(request)
            claims = dict(token["userinfo"])
        except httpx.HTTPError as exc:
            log.warning("sign-in failed: %s", type(exc).__name__)
            return failure(502, "The identity provider could not be reached.")
        except SIGN_IN_ERRORS as exc:
            log.warning("sign-in rejected: %s", type(exc).__name__)
            return failure(400, "The sign-in request or identity token was invalid.")
        next_path = safe_next(request.session.get("next"))
        request.session.clear()
        if not settings.authorized(claims):
            log.warning("sign-in rejected: not authorized")
            return failure(403, "This account is not allowed to view the dashboard.")
        groups = claims.get("groups")
        request.session["user"] = {
            "sub": claims["sub"],
            "email": claims.get("email") if isinstance(claims.get("email"), str) else None,
            "groups": groups if isinstance(groups, list) else [],
            "exp": int(clock()) + SESSION_TTL,
        }
        return RedirectResponse(next_path, status_code=303)

    @app.post("/logout")
    async def logout(request: Request) -> Response:
        if settings.auth_enabled:
            request.session.clear()
        return render("message.html", title="Signed out", message="Signed out.", link_text="Sign in again")

    @app.get("/", response_class=HTMLResponse)
    def index(request: Request, channel: str = "appstore", days: str = "30") -> HTMLResponse:
        who = user(request)
        if channel not in channels:
            channel = channels[0]
        n_days = int(days) if days.isdigit() and int(days) in RANGES else 30
        context = dashboard_context(settings.db_path, schema, channel, n_days)
        return render(
            "index.html",
            channels=channels,
            channel=channel,
            days=n_days,
            ranges=RANGES,
            signed_in_as=str(who.get("email") or who.get("sub", "")),
            **context,
        )

    @app.get("/static/{name:path}")
    def static_file(request: Request, name: str) -> Response:
        user(request)
        entry = static.get(name)
        if entry is None:
            return Response(status_code=404)
        return Response(entry.path.read_bytes(), media_type=entry.media_type, headers={"Cache-Control": STATIC_CACHE})

    return app


# ---------------------------------------------------------------- view data


def _pct(n: float | None) -> str:
    return "–" if n is None else f"{n:.0%}"


def _share_rows(values: dict[str, int], total: int) -> list[dict[str, Any]]:
    """Distribution rows sorted by count, with the derived unknown row last."""
    known = sorted(((v, n) for v, n in values.items() if v != UNKNOWN), key=lambda x: (-x[1], x[0]))
    if UNKNOWN in values:
        known.append((UNKNOWN, values[UNKNOWN]))
    return [{"value": v, "count": n, "share": n / total if total else 0.0, "unknown": v == UNKNOWN} for v, n in known]


def dashboard_context(db_path: Path, schema: Schema, channel: str, days: int) -> dict[str, Any]:
    """Plain data for index.html; `end` is None when there is nothing to show yet."""
    if not db_path.exists():
        return {"end": None, "empty_reason": "No database yet."}
    conn = open_readonly(db_path)
    try:
        end = latest_day(conn)
        if end is None:
            return {"end": None, "empty_reason": "No data yet."}
        window = day_range(end, days)
        start = window[0]
        counts = Counts(conn, channel, day_range(end, max(days, MAU_WINDOW_DAYS))[0], end)
    finally:
        conn.close()

    features = list(schema.features)
    daily = counts.daily_pings("health", window)
    health_total = counts.pings_in("health", start, end)
    flagged = {d for d, _, _ in implausible_days(counts) if d >= start}
    age_today = distribution(counts, schema, "install_age", end, end)
    stats = feature_stats(counts, features, start, end)
    by_name = {s.name: s for s in stats}
    errors = counts.values("health", "errors", start, end)

    return {
        "end": end,
        "cards": {
            "daily_active": daily[-1],
            "daily_avg": health_total / days,
            "mau": mau_estimate(counts, end),
            "new_7d": age_today.get("<7d", 0),
            "new_30d": age_today.get("<30d", 0),
            "feature_pings": counts.pings("feature", end),
            "flagged_days": len(flagged),
        },
        "count_buckets": list(schema.count_buckets),
        "features": [
            {
                "name": s.name,
                "used": s.used,
                "available": s.available,
                "ratio": s.ratio,
                "buckets": [s.buckets.get(b, 0) for b in schema.count_buckets],
                "unused": s.unused,
            }
            for s in stats
        ],
        "pairs": [
            {
                "started": a,
                "done": b,
                "started_n": by_name[a].used,
                "done_n": by_name[b].used,
                "rate": by_name[b].used / by_name[a].used if by_name[a].used else None,
            }
            for a, b in completion_pairs(features)
        ],
        "errors": [
            {"name": e, "count": errors.get(e, 0), "share": errors.get(e, 0) / health_total if health_total else None}
            for e in sorted(schema.errors, key=lambda e: -errors.get(e, 0))
        ],
        "environment": [
            {"field": f, "rows": _share_rows(distribution(counts, schema, f, start, end), health_total)}
            for f in schema.environment_fields
        ],
        # Read by static/dashboard.js from a JSON data block.
        "chart": {
            "days": window,
            "active": daily,
            "flagged": [d in flagged for d in window],
            # A list, not a dict: tojson sorts keys, and the legend should follow schema order.
            "ratios": [{"name": n, "values": v} for n, v in daily_feature_ratios(counts, features, window).items()],
        },
    }
