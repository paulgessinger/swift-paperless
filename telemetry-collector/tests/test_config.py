from __future__ import annotations

from pathlib import Path

import pytest
from conftest import by_field
from pydantic import ValidationError

from telemetry_collector.config import DashboardSettings, Settings

DASHBOARD_ENV = {
    "OIDC_ISSUER": "https://id.example.test",
    "OIDC_CLIENT_ID": "dash",
    "OIDC_CLIENT_SECRET": "client-secret-value",
    "OIDC_REDIRECT_URI": "https://dash.example.test/auth/callback",
    "DASHBOARD_SESSION_SECRET": "session-secret-" + "x" * 32,
    "OIDC_REQUIRED_GROUP": "telemetry",
}


def test_env_var_names_unchanged():
    assert {f.alias for f in Settings.model_fields.values()} == {
        "TELEMETRY_DB_PATH",
        "TELEMETRY_SCHEMA_PATH",
        "TELEMETRY_DEV",
        "TELEMETRY_BATCH_SIZE",
    }
    assert {f.alias for f in DashboardSettings.model_fields.values()} == {
        "TELEMETRY_DB_PATH",
        "TELEMETRY_SCHEMA_PATH",
        "TELEMETRY_DEV",
        "DASHBOARD_AUTH",
        "OIDC_ISSUER",
        "OIDC_CLIENT_ID",
        "OIDC_CLIENT_SECRET",
        "OIDC_REDIRECT_URI",
        "DASHBOARD_SESSION_SECRET",
        "OIDC_ALLOWED_SUBJECTS",
        "OIDC_ALLOWED_EMAILS",
        "OIDC_REQUIRED_GROUP",
    }


def test_collector_from_env(monkeypatch):
    monkeypatch.setenv("TELEMETRY_DB_PATH", "/data/t.sqlite3")
    monkeypatch.setenv("TELEMETRY_BATCH_SIZE", "5")
    s = Settings()
    assert s.db_path == Path("/data/t.sqlite3")
    assert s.batch_size == 5
    assert not s.dev


@pytest.mark.parametrize(
    ("name", "value"),
    [("TELEMETRY_BATCH_SIZE", "abc"), ("TELEMETRY_BATCH_SIZE", "0"), ("TELEMETRY_DEV", "maybe")],
)
def test_invalid_collector_values_name_the_variable(monkeypatch, name, value):
    monkeypatch.setenv(name, value)
    with pytest.raises(ValidationError) as exc:
        Settings()
    assert name in str(exc.value)


def test_only_exact_env_names_are_read(monkeypatch, tmp_path):
    monkeypatch.setenv("batch_size", "7")
    monkeypatch.setenv("telemetry_batch_size", "8")
    # No .env file is read either.
    (tmp_path / ".env").write_text("TELEMETRY_BATCH_SIZE=9\n")
    monkeypatch.chdir(tmp_path)
    assert Settings().batch_size == 20


def test_settings_are_frozen():
    s = Settings()
    with pytest.raises(ValidationError):
        s.batch_size = 3


def test_dashboard_from_env(monkeypatch):
    for k, v in DASHBOARD_ENV.items():
        monkeypatch.setenv(k, v)
    monkeypatch.setenv("OIDC_ALLOWED_EMAILS", "a@example.test, b@example.test,")
    monkeypatch.setenv("OIDC_ALLOWED_SUBJECTS", "sub-1")
    s = DashboardSettings()
    assert s.allowed_emails == frozenset({"a@example.test", "b@example.test"})
    assert s.allowed_subjects == frozenset({"sub-1"})
    assert s.auth_enabled
    assert s.client_secret.get_secret_value() == "client-secret-value"


def test_secrets_hidden(monkeypatch):
    for k, v in DASHBOARD_ENV.items():
        monkeypatch.setenv(k, v)
    s = DashboardSettings()
    for text in (repr(s), str(s), repr(s.client_secret), str(s.session_secret)):
        assert "client-secret-value" not in text
        assert "session-secret-" not in text


@pytest.mark.parametrize(("name", "value"), [("TELEMETRY_DEV", "maybe"), ("DASHBOARD_AUTH", "disabled")])
def test_invalid_dashboard_values_name_the_variable(monkeypatch, name, value):
    for k, v in DASHBOARD_ENV.items():
        monkeypatch.setenv(k, v)
    monkeypatch.setenv(name, value)
    with pytest.raises(ValidationError) as exc:
        DashboardSettings()
    assert name in str(exc.value)


@pytest.mark.parametrize(
    ("overrides", "message"),
    [
        ({"auth": "off"}, "DASHBOARD_AUTH=off is only allowed with TELEMETRY_DEV=1"),
        ({"client_secret": ""}, "missing settings: OIDC_CLIENT_SECRET"),
        ({"session_secret": "short"}, "DASHBOARD_SESSION_SECRET must be at least 32 characters"),
        ({"required_group": " "}, "set OIDC_ALLOWED_SUBJECTS, OIDC_ALLOWED_EMAILS and/or OIDC_REQUIRED_GROUP"),
        ({"redirect_uri": "http://x/auth/callback"}, "OIDC_REDIRECT_URI must be https"),
    ],
)
def test_dashboard_refusals(overrides, message):
    fields = {
        "issuer": "https://id.example.test",
        "client_id": "dash",
        "client_secret": "s",
        "redirect_uri": "https://dash.example.test/auth/callback",
        "session_secret": "x" * 32,
        "required_group": "telemetry",
    } | overrides
    with pytest.raises(ValidationError, match=message):
        by_field(DashboardSettings, **fields)


def test_auth_off_allowed_in_dev_mode():
    assert not by_field(DashboardSettings, dev=True, auth="off").auth_enabled


def test_serve_fails_at_startup_on_invalid_env(monkeypatch):
    from telemetry_collector import serve

    monkeypatch.setenv("TELEMETRY_BATCH_SIZE", "twenty")
    with pytest.raises(ValidationError, match="TELEMETRY_BATCH_SIZE"):
        serve._app()
