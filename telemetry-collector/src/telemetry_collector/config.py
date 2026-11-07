"""Settings from environment variables. Invalid values fail at construction, naming the variable.

Each field is read only from its exact env var name (its alias). No .env file is
read, so production never picks one up by accident.
"""

from __future__ import annotations

from pathlib import Path
from typing import Annotated, Any, Literal

from pydantic import Field, SecretStr, TypeAdapter, field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict

# Request bodies larger than this get 413.
MAX_BODY_BYTES = 4096
PRODUCTION_CHANNELS = frozenset({"appstore", "testflight"})
DEV_CHANNELS = PRODUCTION_CHANNELS | {"dev"}

# Comma-separated in the environment (`a, b,c`), not JSON.
CommaSet = Annotated[frozenset[str], NoDecode]


def split_commas(value: Any) -> Any:
    if isinstance(value, str):
        return frozenset(v.strip() for v in value.split(",") if v.strip())
    return value


class CommonSettings(BaseSettings):
    model_config = SettingsConfigDict(frozen=True, case_sensitive=True)

    db_path: Path = Field(default=Path("telemetry.sqlite3"), alias="TELEMETRY_DB_PATH")
    schema_path: Path | None = Field(default=None, alias="TELEMETRY_SCHEMA_PATH")
    # Dev mode: the collector accepts the "dev" channel and serves /docs; the dashboard may run without auth.
    dev: bool = Field(default=False, alias="TELEMETRY_DEV")


class Settings(CommonSettings):
    """Collector settings."""

    # Defaults to appstore,testflight, plus dev in dev mode.
    channels: CommaSet = Field(default=PRODUCTION_CHANNELS, alias="TELEMETRY_CHANNELS")
    batch_size: int = Field(default=20, ge=1, alias="TELEMETRY_BATCH_SIZE")

    @model_validator(mode="before")
    @classmethod
    def _default_channels(cls, data: Any) -> Any:
        if isinstance(data, dict) and "TELEMETRY_CHANNELS" not in data:
            try:
                dev = TypeAdapter(bool).validate_python(data.get("TELEMETRY_DEV", False))
            except ValueError:
                return data  # field validation reports the invalid TELEMETRY_DEV
            data = {**data, "TELEMETRY_CHANNELS": DEV_CHANNELS if dev else PRODUCTION_CHANNELS}
        return data

    @field_validator("channels", mode="before")
    @classmethod
    def _split_channels(cls, value: Any) -> Any:
        return split_commas(value)

    @model_validator(mode="after")
    def _dev_channel_needs_dev_mode(self) -> Settings:
        if "dev" in self.channels and not self.dev:
            raise ValueError("the dev channel is only accepted in dev mode")
        return self


class DashboardSettings(CommonSettings):
    """Dashboard settings. Construction fails unless sign-in is fully configured (or explicitly off in dev mode)."""

    auth: Literal["oidc", "off"] = Field(default="oidc", alias="DASHBOARD_AUTH")
    issuer: str = Field(default="", alias="OIDC_ISSUER")
    client_id: str = Field(default="", alias="OIDC_CLIENT_ID")
    client_secret: SecretStr = Field(default=SecretStr(""), alias="OIDC_CLIENT_SECRET")
    redirect_uri: str = Field(default="", alias="OIDC_REDIRECT_URI")
    session_secret: SecretStr = Field(default=SecretStr(""), alias="DASHBOARD_SESSION_SECRET")
    allowed_subjects: CommaSet = Field(default=frozenset(), alias="OIDC_ALLOWED_SUBJECTS")
    allowed_emails: CommaSet = Field(default=frozenset(), alias="OIDC_ALLOWED_EMAILS")
    required_group: str = Field(default="", alias="OIDC_REQUIRED_GROUP")

    @property
    def auth_enabled(self) -> bool:
        return self.auth == "oidc"

    @field_validator("allowed_subjects", "allowed_emails", mode="before")
    @classmethod
    def _split_lists(cls, value: Any) -> Any:
        return split_commas(value)

    @field_validator("required_group")
    @classmethod
    def _strip(cls, value: str) -> str:
        return value.strip()

    @model_validator(mode="after")
    def _check_auth(self) -> DashboardSettings:
        if not self.auth_enabled:
            if not self.dev:
                raise ValueError("DASHBOARD_AUTH=off is only allowed with TELEMETRY_DEV=1")
            return self
        missing = [
            name
            for name, value in (
                ("OIDC_ISSUER", self.issuer),
                ("OIDC_CLIENT_ID", self.client_id),
                ("OIDC_CLIENT_SECRET", self.client_secret.get_secret_value()),
                ("OIDC_REDIRECT_URI", self.redirect_uri),
            )
            if not value
        ]
        if missing:
            raise ValueError(f"missing settings: {', '.join(missing)}")
        if len(self.session_secret.get_secret_value()) < 32:
            raise ValueError("DASHBOARD_SESSION_SECRET must be at least 32 characters")
        if not (self.allowed_subjects or self.allowed_emails or self.required_group):
            raise ValueError("set OIDC_ALLOWED_SUBJECTS, OIDC_ALLOWED_EMAILS and/or OIDC_REQUIRED_GROUP")
        if not self.redirect_uri.startswith("https://") and not self.dev:
            raise ValueError("OIDC_REDIRECT_URI must be https")
        return self

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
