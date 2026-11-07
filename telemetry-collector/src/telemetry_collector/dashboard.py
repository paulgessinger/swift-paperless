"""Read-only analytics dashboard (separate app/process from the public collector).

Every page requires an OIDC session. Auth can only be disabled in dev mode.
The database is opened read-only per request.

The OIDC flow (state, nonce, PKCE, discovery, JWKS, ID token validation) is
Authlib's; the session cookie is Starlette's SessionMiddleware (itsdangerous).
This module only adds policy: who may sign in, the session lifetime, and
start-up checks.
"""

from __future__ import annotations

import logging
import os
import time
from collections.abc import Callable
from dataclasses import dataclass, field
from html import escape
from pathlib import Path
from typing import Any
from urllib.parse import urlencode

import httpx
from authlib.integrations.starlette_client import OAuth, OAuthError
from fastapi import FastAPI, Request, Response
from fastapi.exceptions import RequestValidationError
from fastapi.responses import HTMLResponse, RedirectResponse
from joserfc.errors import JoseError
from starlette.exceptions import HTTPException as StarletteHTTPException
from starlette.middleware.sessions import SessionMiddleware

from .report import (
    MAU_WINDOW_DAYS,
    UNKNOWN,
    Counts,
    completion_pairs,
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


def _split(value: str | None) -> frozenset[str]:
    return frozenset(v.strip() for v in (value or "").split(",") if v.strip())


def safe_next(target: str | None) -> str:
    """Only same-site absolute paths; anything else (//host, scheme, backslash) becomes /."""
    if not target or not target.startswith("/") or target.startswith("//") or "\\" in target:
        return "/"
    return target


@dataclass(frozen=True)
class DashboardSettings:
    db_path: Path
    schema_path: Path | None = None
    dev: bool = False
    auth: bool = True
    issuer: str = ""
    client_id: str = ""
    client_secret: str = ""
    redirect_uri: str = ""
    session_secret: str = ""
    allowed_subjects: frozenset[str] = field(default_factory=frozenset)
    allowed_emails: frozenset[str] = field(default_factory=frozenset)
    required_group: str = ""

    @classmethod
    def from_env(cls) -> DashboardSettings:
        schema = os.environ.get("TELEMETRY_SCHEMA_PATH")
        return cls(
            db_path=Path(os.environ.get("TELEMETRY_DB_PATH", "telemetry.sqlite3")),
            schema_path=Path(schema) if schema else None,
            dev=os.environ.get("TELEMETRY_DEV", "").lower() in ("1", "true", "yes", "on"),
            auth=os.environ.get("DASHBOARD_AUTH", "oidc") != "off",
            issuer=os.environ.get("OIDC_ISSUER", ""),
            client_id=os.environ.get("OIDC_CLIENT_ID", ""),
            client_secret=os.environ.get("OIDC_CLIENT_SECRET", ""),
            redirect_uri=os.environ.get("OIDC_REDIRECT_URI", ""),
            session_secret=os.environ.get("DASHBOARD_SESSION_SECRET", ""),
            allowed_subjects=_split(os.environ.get("OIDC_ALLOWED_SUBJECTS")),
            allowed_emails=_split(os.environ.get("OIDC_ALLOWED_EMAILS")),
            required_group=os.environ.get("OIDC_REQUIRED_GROUP", "").strip(),
        )

    def validate(self) -> None:
        if not self.auth:
            if not self.dev:
                raise ValueError("DASHBOARD_AUTH=off is only allowed with TELEMETRY_DEV=1")
            return
        missing = [
            name
            for name, value in (
                ("OIDC_ISSUER", self.issuer),
                ("OIDC_CLIENT_ID", self.client_id),
                ("OIDC_CLIENT_SECRET", self.client_secret),
                ("OIDC_REDIRECT_URI", self.redirect_uri),
            )
            if not value
        ]
        if missing:
            raise ValueError(f"missing settings: {', '.join(missing)}")
        if len(self.session_secret) < 32:
            raise ValueError("DASHBOARD_SESSION_SECRET must be at least 32 characters")
        if not (self.allowed_subjects or self.allowed_emails or self.required_group):
            raise ValueError("set OIDC_ALLOWED_SUBJECTS, OIDC_ALLOWED_EMAILS and/or OIDC_REQUIRED_GROUP")
        if not self.redirect_uri.startswith("https://") and not self.dev:
            raise ValueError("OIDC_REDIRECT_URI must be https")

    def authorized(self, claims: dict[str, Any]) -> bool:
        """Every configured constraint must hold: group membership, and the subject or verified-email allow-list."""
        if self.required_group:
            groups = claims.get("groups")
            if not isinstance(groups, list) or self.required_group not in groups:
                return False
        if self.allowed_subjects or self.allowed_emails:
            email = claims.get("email")
            email_ok = (
                isinstance(email, str)
                and claims.get("email_verified") is True
                and email.lower() in {e.lower() for e in self.allowed_emails}
            )
            if claims.get("sub") not in self.allowed_subjects and not email_ok:
                return False
        return True


class _LoginRequired(Exception):
    pass


SECURITY_HEADERS = {
    "Content-Security-Policy": (
        "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'"
    ),
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    "Cache-Control": "no-store",
}


def create_dashboard_app(
    settings: DashboardSettings,
    transport: httpx.AsyncBaseTransport | None = None,
    clock: Callable[[], float] = time.time,
) -> FastAPI:
    """`transport` replaces the HTTP transport to the identity provider (tests)."""
    settings.validate()
    schema = load_schema(settings.schema_path)
    channels = [c for c in schema.channels if c != "dev" or settings.dev]

    app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)

    oauth = OAuth()
    if settings.auth:
        client_kwargs: dict[str, Any] = {"scope": SCOPES, "code_challenge_method": "S256"}
        if transport is not None:
            client_kwargs["transport"] = transport
        oauth.register(
            "oidc",
            client_id=settings.client_id,
            client_secret=settings.client_secret,
            server_metadata_url=settings.issuer.rstrip("/") + "/.well-known/openid-configuration",
            client_kwargs=client_kwargs,
        )
        # Holds the login transaction (Authlib's state/nonce/PKCE data) and, after sign-in, the user.
        app.add_middleware(
            SessionMiddleware,
            secret_key=settings.session_secret,
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
        if not settings.auth:
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
        return HTMLResponse(
            _page("Sign-in failed", f"<p>{escape(message)}</p><p><a href='/login'>Try again</a></p>"), status
        )

    async def check_issuer() -> None:
        # Discovery §4.3: the advertised issuer must equal the configured one;
        # Authlib then validates the ID token's iss against it.
        metadata = await oauth.oidc.load_server_metadata()
        if metadata.get("issuer") != settings.issuer:
            raise ValueError("discovery issuer mismatch")

    @app.get("/login")
    async def login(request: Request, next: str = "/") -> Response:
        if not settings.auth:
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
        if not settings.auth:
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
        if settings.auth:
            request.session.clear()
        return HTMLResponse(_page("Signed out", "<p>Signed out.</p><p><a href='/login'>Sign in again</a></p>"))

    @app.get("/", response_class=HTMLResponse)
    def index(request: Request, channel: str = "appstore", days: str = "30") -> HTMLResponse:
        who = user(request)
        if channel not in channels:
            channel = channels[0]
        n_days = int(days) if days.isdigit() and int(days) in RANGES else 30
        return HTMLResponse(_dashboard(settings.db_path, schema, channels, channel, n_days, who))

    return app


# ---------------------------------------------------------------- rendering

CSS = """
:root{--bg:#f7f7f5;--card:#fff;--fg:#1d1d1f;--muted:#6e6e73;--line:#e3e3e0;--accent:#2f6fde;--warn:#b25000;--bar:#2f6fde}
@media (prefers-color-scheme:dark){:root{--bg:#141416;--card:#1e1e21;--fg:#ececee;--muted:#9a9aa1;--line:#2e2e33;
  --accent:#6f9cf0;--warn:#f0a050;--bar:#6f9cf0}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);
  font:14px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
main{max-width:1100px;margin:0 auto;padding:16px}
header{display:flex;flex-wrap:wrap;gap:12px;align-items:center;justify-content:space-between;margin-bottom:16px}
h1{font-size:20px;margin:0}h2{font-size:15px;margin:0 0 10px}
.seg{display:inline-flex;border:1px solid var(--line);border-radius:8px;overflow:hidden}
.seg a{padding:5px 12px;color:var(--fg);text-decoration:none;border-right:1px solid var(--line)}
.seg a:last-child{border-right:0}
.seg a.on{background:var(--accent);color:#fff}
.muted{color:var(--muted)}.warn{color:var(--warn)}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px;margin-bottom:12px}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px}
.big{font-size:28px;font-weight:600;font-variant-numeric:tabular-nums}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:12px;margin-bottom:12px}
table{width:100%;border-collapse:collapse;font-variant-numeric:tabular-nums}
th,td{text-align:left;padding:5px 6px;border-bottom:1px solid var(--line)}th{color:var(--muted);font-weight:500}
td.n{text-align:right;white-space:nowrap}.hbar>span:last-child{white-space:nowrap;min-width:84px;text-align:right}
.hbar{display:grid;grid-template-columns:minmax(70px,auto) 1fr auto;gap:8px;align-items:center;margin:3px 0}
.hbar .t{height:10px;background:var(--line);border-radius:5px;overflow:hidden}
.hbar .t span{display:block;height:100%;background:var(--bar)}
.hbar.unknown .t span{background:var(--muted)}
svg text{fill:var(--muted);font-size:11px}
form{margin:0}
button{font:inherit;background:none;border:1px solid var(--line);color:var(--fg);border-radius:6px;padding:4px 10px;
  cursor:pointer}
"""


def _page(title: str, body: str) -> str:
    return (
        "<!doctype html><html lang='en'><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
        f"<title>{escape(title)}</title><style>{CSS}</style></head><body><main>{body}</main></body></html>"
    )


def _pct(n: float | None) -> str:
    return "–" if n is None else f"{n:.0%}"


def _bar_chart(days: list[str], values: list[int], flagged: set[str]) -> str:
    width, height, pad_l, pad_b, pad_t = 720, 180, 34, 20, 8
    top = max(values + [1])
    slot = (width - pad_l) / max(len(days), 1)
    bar_w = max(slot * 0.75, 1)
    parts = [f"<svg viewBox='0 0 {width} {height}' width='100%' role='img' aria-label='Daily active installs'>"]
    inner = height - pad_b - pad_t
    for frac in (0, 0.5, 1):
        y = pad_t + inner * (1 - frac)
        parts.append(f"<line x1='{pad_l}' x2='{width}' y1='{y:.1f}' y2='{y:.1f}' stroke='var(--line)'/>")
        parts.append(f"<text x='{pad_l - 4}' y='{y + 4:.1f}' text-anchor='end'>{round(top * frac)}</text>")
    for i, (day, v) in enumerate(zip(days, values, strict=True)):
        h = inner * v / top
        x = pad_l + i * slot + (slot - bar_w) / 2
        color = "var(--warn)" if day in flagged else "var(--bar)"
        parts.append(
            f"<rect x='{x:.1f}' y='{pad_t + inner - h:.1f}' width='{bar_w:.1f}' height='{h:.1f}' "
            f"rx='1.5' fill='{color}'>"
            f"<title>{escape(day)}: {v}</title></rect>"
        )
    for i in sorted({0, len(days) // 2, len(days) - 1}):
        x = pad_l + i * slot + slot / 2
        parts.append(f"<text x='{x:.1f}' y='{height - 5}' text-anchor='middle'>{escape(days[i][5:])}</text>")
    parts.append("</svg>")
    return "".join(parts)


def _hbars(values: dict[str, int], total: int) -> str:
    if not values:
        return "<p class='muted'>No data.</p>"
    rows = []
    known = sorted(((v, n) for v, n in values.items() if v != UNKNOWN), key=lambda x: (-x[1], x[0]))
    if UNKNOWN in values:
        known.append((UNKNOWN, values[UNKNOWN]))
    for value, n in known:
        share = n / total if total else 0
        cls = "hbar unknown" if value == UNKNOWN else "hbar"
        label = f"<i>{UNKNOWN}</i>" if value == UNKNOWN else escape(value)
        rows.append(
            f"<div class='{cls}'><span>{label}</span>"
            f"<div class='t'><span style='width:{share * 100:.1f}%'></span></div>"
            f"<span class='muted'>{n} · {_pct(share)}</span></div>"
        )
    return "".join(rows)


def _dashboard(db_path: Path, schema: Schema, channels: list[str], channel: str, days: int, who: dict[str, Any]) -> str:
    signed_in_as = str(who.get("email") or who.get("sub", ""))
    nav_channels = "".join(
        f"<a class='{'on' if c == channel else ''}' href='/?{urlencode({'channel': c, 'days': days})}'>{escape(c)}</a>"
        for c in channels
    )
    nav_days = "".join(
        f"<a class='{'on' if d == days else ''}' href='/?{urlencode({'channel': channel, 'days': d})}'>{d}d</a>"
        for d in RANGES
    )
    header = (
        "<header><h1>Swift Paperless telemetry</h1>"
        f"<div class='seg'>{nav_channels}</div><div class='seg'>{nav_days}</div>"
        f"<form method='post' action='/logout'><span class='muted'>{escape(signed_in_as)}</span> "
        "<button type='submit'>Sign out</button></form></header>"
    )
    if not db_path.exists():
        return _page("Telemetry", header + "<p class='muted'>No database yet.</p>")
    conn = open_readonly(db_path)
    try:
        end = latest_day(conn)
        if end is None:
            return _page("Telemetry", header + "<p class='muted'>No data yet.</p>")
        window = day_range(end, days)
        start = window[0]
        counts = Counts(conn, channel, day_range(end, max(days, MAU_WINDOW_DAYS))[0], end)
    finally:
        conn.close()

    daily = counts.daily_pings("health", window)
    health_total = counts.values("health", "_pings", start, end).get("total", 0)
    flagged = {d for d, _, _ in implausible_days(counts) if d >= start}
    age_today = distribution(counts, schema, "install_age", end, end)
    avg = health_total / days

    cards = (
        "<div class='cards'>"
        f"<div class='card'><div class='muted'>Daily active · {escape(end)}</div><div class='big'>{daily[-1]}</div>"
        f"<div class='muted'>avg {avg:.1f}/day over {days}d</div></div>"
        "<div class='card'><div class='muted'>MAU estimate · 30d</div>"
        f"<div class='big'>{mau_estimate(counts, end):.0f}</div>"
        "<div class='muted'>Σ 1/midpoint(active_days_30)</div></div>"
        f"<div class='card'><div class='muted'>Installs &lt;7 days old · {escape(end)}</div>"
        f"<div class='big'>{age_today.get('<7d', 0)}</div>"
        f"<div class='muted'>&lt;30d: {age_today.get('<30d', 0)}</div></div>"
        f"<div class='card'><div class='muted'>Feature pings · {escape(end)}</div>"
        f"<div class='big'>{counts.pings('feature', end)}</div>"
        f"<div class='muted'>{len(flagged)} implausible day(s) in range</div></div>"
        "</div>"
    )
    chart = (
        f"<div class='card' style='margin-bottom:12px'><h2>Daily active installs (health pings), last {days} days</h2>"
        f"{_bar_chart(window, daily, flagged)}"
        + (f"<p class='warn'>Highlighted: feature pings exceed {1.5}× health pings.</p>" if flagged else "")
        + "</div>"
    )

    feature_rows = []
    for s in feature_stats(counts, list(schema.features), start, end):
        breakdown = " / ".join(str(s.buckets.get(b, 0)) for b in schema.count_buckets)
        flag = (
            "<span class='warn'>no use in range</span>"
            if s.unused
            else ("<span class='muted'>not available</span>" if not s.available else "")
        )
        feature_rows.append(
            f"<tr><td>{escape(s.name)}</td><td class='n'>{s.used}</td><td class='n'>{s.available}</td>"
            f"<td class='n'>{_pct(s.ratio)}</td><td class='n muted'>{breakdown}</td><td>{flag}</td></tr>"
        )
    features = (
        f"<div class='card'><h2>Features · install-days, last {days} days</h2><table>"
        "<tr><th>Feature</th><th class='n'>Used</th><th class='n'>Available</th><th class='n'>Ratio</th>"
        f"<th class='n'>{escape(' / '.join(schema.count_buckets))}</th><th></th></tr>"
        + "".join(feature_rows)
        + "</table></div>"
    )

    stats = {s.name: s for s in feature_stats(counts, list(schema.features), start, end)}
    pair_rows = "".join(
        f"<tr><td>{escape(a)} → {escape(b)}</td><td class='n'>{stats[a].used}</td><td class='n'>{stats[b].used}</td>"
        f"<td class='n'>{_pct(stats[b].used / stats[a].used if stats[a].used else None)}</td></tr>"
        for a, b in completion_pairs(list(schema.features))
    )
    errors = counts.values("health", "errors", start, end)
    error_rows = "".join(
        f"<tr><td>{escape(e)}</td><td class='n'>{errors.get(e, 0)}</td>"
        f"<td class='n'>{_pct(errors.get(e, 0) / health_total if health_total else None)}</td></tr>"
        for e in sorted(schema.errors, key=lambda e: -errors.get(e, 0))
    )
    side = (
        "<div class='card'><h2>Completion (install-days)</h2><table><tr><th>Pair</th><th class='n'>Started</th>"
        f"<th class='n'>Done</th><th class='n'>Rate</th></tr>{pair_rows}</table>"
        "<p class='muted'>Ratio of marginals; not a per-install funnel.</p>"
        "<h2 style='margin-top:16px'>Error classes</h2><table><tr><th>Error</th><th class='n'>Install-days</th>"
        f"<th class='n'>of health</th></tr>{error_rows}</table></div>"
    )

    env_cards = "".join(
        f"<div class='card'><h2>{escape(f)}</h2>"
        f"{_hbars(distribution(counts, schema, f, start, end), health_total)}</div>"
        for f in schema.environment_fields
    )
    body = (
        header + f"<p class='muted'>Data through {escape(end)} "
        "(UTC; the latest day may be partial, and the collector writes in batches). "
        f"Channel <b>{escape(channel)}</b>. Counts are install-days from opted-in users.</p>"
        + cards
        + chart
        + f"<div class='grid'>{features}{side}</div>"
        + f"<h2>Environment · health pings, last {days} days</h2><div class='grid'>{env_cards}</div>"
    )
    return _page("Telemetry", body)
