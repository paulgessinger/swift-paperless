from __future__ import annotations

import base64
import json
import subprocess
import sys
import time
from typing import Any
from urllib.parse import parse_qs, urlparse

import httpx
import pytest
from conftest import feature_payload, health_payload
from fastapi.testclient import TestClient
from joserfc import jwt
from joserfc.jwk import RSAKey

from telemetry_collector.dashboard import SESSION_COOKIE, DashboardSettings, create_dashboard_app

ISSUER = "https://id.example.test"
CLIENT_ID = "dash"
REDIRECT = "https://dash.example.test/auth/callback"
SECRET = "s" * 40

KEY = RSAKey.generate_key(2048, parameters={"kid": "k1", "use": "sig", "alg": "RS256"})
OTHER_KEY = RSAKey.generate_key(2048, parameters={"kid": "k1"})


def b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


class FakeProvider:
    """OIDC provider behind an httpx.MockTransport: discovery, JWKS, token endpoint."""

    def __init__(self) -> None:
        self.issuer = ISSUER
        self.id_token = ""
        self.token_requests: list[httpx.Request] = []

    def handler(self, request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if url == f"{ISSUER}/.well-known/openid-configuration":
            return httpx.Response(
                200,
                json={
                    "issuer": self.issuer,
                    "authorization_endpoint": f"{ISSUER}/authorize",
                    "token_endpoint": f"{ISSUER}/api/oidc/token",
                    "jwks_uri": f"{ISSUER}/.well-known/jwks.json",
                    "id_token_signing_alg_values_supported": ["RS256"],
                },
            )
        if url == f"{ISSUER}/.well-known/jwks.json":
            return httpx.Response(200, json={"keys": [KEY.as_dict(private=False)]})
        if url == f"{ISSUER}/api/oidc/token":
            self.token_requests.append(request)
            return httpx.Response(200, json={"access_token": "at", "token_type": "Bearer", "id_token": self.id_token})
        return httpx.Response(404)


class Clock:
    def __init__(self) -> None:
        self.now = time.time()

    def __call__(self) -> float:
        return self.now


def settings(db_path, **overrides) -> DashboardSettings:
    values: dict[str, Any] = dict(
        db_path=db_path,
        issuer=ISSUER,
        client_id=CLIENT_ID,
        client_secret="client-secret",
        redirect_uri=REDIRECT,
        session_secret=SECRET,
        allowed_emails=frozenset({"owner@example.test"}),
    )
    values.update(overrides)
    return DashboardSettings(**values)


@pytest.fixture
def provider() -> FakeProvider:
    return FakeProvider()


@pytest.fixture
def dclock() -> Clock:
    return Clock()


@pytest.fixture
def make_dashboard(db_path, provider, dclock):
    def factory(**overrides) -> TestClient:
        app = create_dashboard_app(
            settings(db_path, **overrides), transport=httpx.MockTransport(provider.handler), clock=dclock
        )
        return TestClient(app, base_url="https://dash.example.test", follow_redirects=False)

    return factory


def claims(nonce: str, **overrides) -> dict:
    now = int(time.time())
    values = {
        "iss": ISSUER,
        "aud": CLIENT_ID,
        "sub": "user-1",
        "email": "owner@example.test",
        "email_verified": True,
        "groups": ["telemetry"],
        "iat": now,
        "exp": now + 300,
        "nonce": nonce,
    }
    values.update(overrides)
    return {k: v for k, v in values.items() if v is not None}


def sign(payload: dict, key: RSAKey = KEY) -> str:
    return jwt.encode({"alg": "RS256", "kid": "k1"}, payload, key)


def start_login(client: TestClient, next_path: str = "/?channel=testflight") -> tuple[str, str]:
    r = client.get("/login", params={"next": next_path})
    assert r.status_code == 302, r.text
    q = parse_qs(urlparse(r.headers["location"]).query)
    return q["state"][0], q["nonce"][0]


def sign_in(client, provider, key=KEY, state_override=None, nonce_override=None, **claim_overrides):
    state, nonce = start_login(client)
    provider.id_token = sign(claims(nonce_override or nonce, **claim_overrides), key)
    return client.get("/auth/callback", params={"code": "c0de", "state": state_override or state})


@pytest.fixture
def seeded_db(make_client, db_path, clock):
    with make_client(batch_size=50) as c:
        for day, n in (("2026-11-05", 3), ("2026-11-06", 4), ("2026-11-07", 5)):
            clock.day = day
            for i in range(n):
                c.post(
                    "/t/health",
                    json=health_payload(install_age="<7d" if i == 0 else "existing", auth=None if i == 1 else "token"),
                )
                c.post("/t/feature", json=feature_payload())
        c.post("/t/health", json=health_payload(channel="testflight"))
    return db_path


# ------------------------------------------------------------------ auth


def test_every_route_requires_auth(make_dashboard):
    client = make_dashboard()
    public = {"/login", "/auth/callback", "/logout"}
    protected = [r.path for r in client.app.routes if getattr(r, "path", None) not in public]
    assert protected == ["/"]
    for path in protected:
        r = client.get(path, params={"channel": "testflight"})
        assert r.status_code == 303
        assert r.headers["location"].startswith("/login?next=")
    assert client.get("/docs").status_code == 404
    assert client.get("/openapi.json").status_code == 404


def test_login_redirect_uses_pkce(make_dashboard):
    client = make_dashboard()
    r = client.get("/login")
    url = urlparse(r.headers["location"])
    q = parse_qs(url.query)
    assert f"{url.scheme}://{url.netloc}{url.path}" == f"{ISSUER}/authorize"
    assert q["response_type"] == ["code"]
    assert q["code_challenge_method"] == ["S256"] and q["code_challenge"][0]
    assert q["redirect_uri"] == [REDIRECT]
    assert q["state"][0] and q["nonce"][0]
    assert "groups" in q["scope"][0].split()
    cookie = r.headers["set-cookie"]
    assert cookie.startswith(SESSION_COOKIE) and "httponly" in cookie.lower() and "secure" in cookie.lower()
    assert "samesite=lax" in cookie.lower() and "Max-Age=7200" in cookie


def test_sign_in_and_render(make_dashboard, provider, seeded_db):
    client = make_dashboard()
    r = sign_in(client, provider)
    assert r.status_code == 303, r.text
    assert r.headers["location"] == "/?channel=testflight"
    body = provider.token_requests[-1].content.decode()
    assert "code_verifier=" in body and "code=c0de" in body

    page = client.get("/", params={"channel": "appstore", "days": "7"})
    assert page.status_code == 200
    html = page.text
    assert "Content-Security-Policy" in page.headers
    assert "Daily active · 2026-11-07" in html
    assert "<svg" in html
    assert "saved_view" in html and "scan_started → scan_uploaded" in html
    assert "<i>unknown</i>" in html  # auth omitted by some pings
    assert "owner@example.test" in html
    for field in (
        "backend",
        "ios",
        "app",
        "device",
        "lang",
        "docs",
        "auth",
        "servers",
        "client_cert",
        "custom_headers",
    ):
        assert f"<h2>{field}</h2>" in html


def test_session_expires(make_dashboard, provider, dclock):
    client = make_dashboard()
    sign_in(client, provider)
    assert client.get("/").status_code == 200
    dclock.now += 2 * 3600 + 1
    assert client.get("/").status_code == 303


def test_forged_session_rejected(make_dashboard, provider):
    client = make_dashboard()
    sign_in(client, provider)
    value = client.cookies.get(SESSION_COOKIE)
    data, rest = value.split(".", 1)
    forged = b64(json.dumps({"user": {"sub": "evil", "exp": 9999999999}}).encode())
    client.cookies.set(SESSION_COOKIE, f"{forged}.{rest}", domain="dash.example.test")
    assert client.get("/").status_code == 303


def test_logout_clears_session(make_dashboard, provider):
    client = make_dashboard()
    sign_in(client, provider)
    assert client.post("/logout").status_code == 200
    assert client.get("/").status_code == 303


@pytest.mark.parametrize(
    ("overrides", "status"),
    [
        ({"state_override": "wrong"}, 400),
        ({"nonce_override": "wrong"}, 400),
        ({"iss": "https://evil.example.test"}, 400),
        ({"aud": "someone-else"}, 400),
        ({"exp": int(time.time()) - 3600, "iat": int(time.time()) - 7200}, 400),
        ({"key": OTHER_KEY}, 400),
        ({"email": "stranger@example.test"}, 403),
        ({"email_verified": False}, 403),
    ],
)
def test_callback_rejections(make_dashboard, provider, overrides, status):
    client = make_dashboard()
    r = sign_in(client, provider, **overrides)
    assert r.status_code == status
    assert client.get("/").status_code == 303


def test_callback_without_login_transaction(make_dashboard, provider):
    client = make_dashboard()
    state, nonce = start_login(client)
    provider.id_token = sign(claims(nonce))
    client.cookies.clear()
    assert client.get("/auth/callback", params={"code": "c", "state": state}).status_code == 400


def test_alg_none_rejected(make_dashboard, provider):
    client = make_dashboard()
    state, nonce = start_login(client)
    header = b64(json.dumps({"alg": "none"}).encode())
    provider.id_token = f"{header}.{b64(json.dumps(claims(nonce)).encode())}."
    assert client.get("/auth/callback", params={"code": "c", "state": state}).status_code == 400


def test_discovery_issuer_mismatch(make_dashboard, provider):
    provider.issuer = "https://other.example.test"
    client = make_dashboard()
    assert client.get("/login").status_code == 502


def test_required_group(make_dashboard, provider):
    client = make_dashboard(allowed_emails=frozenset(), required_group="telemetry")
    assert sign_in(client, provider).status_code == 303
    client = make_dashboard(allowed_emails=frozenset(), required_group="telemetry")
    assert sign_in(client, provider, groups=["other"]).status_code == 403


def test_subject_allow_list(make_dashboard, provider):
    client = make_dashboard(allowed_emails=frozenset(), allowed_subjects=frozenset({"user-1"}))
    assert sign_in(client, provider, email=None).status_code == 303
    client = make_dashboard(allowed_emails=frozenset(), allowed_subjects=frozenset({"user-2"}))
    assert sign_in(client, provider).status_code == 403


@pytest.mark.parametrize("target", ["//evil.example", "https://evil.example/", "/\\evil.example"])
def test_open_redirect_blocked(make_dashboard, provider, target):
    client = make_dashboard()
    state, nonce = start_login(client, next_path=target)
    provider.id_token = sign(claims(nonce))
    r = client.get("/auth/callback", params={"code": "c", "state": state})
    assert r.headers["location"] == "/"


# --------------------------------------------------------------- settings


@pytest.mark.parametrize(
    "overrides",
    [
        {"auth": False},  # auth off outside dev mode
        {"session_secret": "short"},
        {"client_secret": ""},
        {"allowed_emails": frozenset()},
        {"redirect_uri": "http://dash.example.test/auth/callback"},
    ],
)
def test_settings_refused(db_path, overrides):
    with pytest.raises(ValueError):
        create_dashboard_app(settings(db_path, **overrides))


def test_auth_off_in_dev_mode(db_path, seeded_db):
    app = create_dashboard_app(DashboardSettings(db_path=db_path, dev=True, auth=False))
    client = TestClient(app, base_url="https://dash.example.test")
    assert client.get("/").status_code == 200


# ---------------------------------------------------------------- database


def test_dashboard_never_writes(db_path):
    app = create_dashboard_app(DashboardSettings(db_path=db_path, dev=True, auth=False))
    client = TestClient(app, base_url="https://dash.example.test")
    assert "No database yet" in client.get("/").text
    assert not db_path.exists()


def test_readonly_connection_rejects_writes(seeded_db):
    import sqlite3

    from telemetry_collector.report import open_readonly

    conn = open_readonly(seeded_db)
    with pytest.raises(sqlite3.OperationalError, match="readonly"):
        conn.execute("UPDATE counters SET count = 0")
    conn.close()


# ------------------------------------------------------------ process roles


def test_collector_role_does_not_load_dashboard_dependencies(tmp_path):
    code = (
        "import sys\n"
        "from telemetry_collector import serve\n"
        "serve._app()\n"
        "heavy = {'authlib', 'joserfc', 'cryptography', 'httpx', 'itsdangerous', 'typer'}\n"
        "print(','.join(sorted({m.split('.')[0] for m in sys.modules} & heavy)))\n"
    )
    env = {"TELEMETRY_ROLE": "collector", "TELEMETRY_DB_PATH": str(tmp_path / "t.sqlite3"), "PATH": ""}
    # S603: fixed interpreter and code string, no untrusted input.
    out = subprocess.run([sys.executable, "-c", code], env=env, capture_output=True, text=True, check=True)  # noqa: S603
    assert out.stdout.strip() == ""
