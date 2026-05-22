"""Runtime configuration.

All env vars are read at runtime — FastAPI has no build-time env var baking
like Next.js, so this just works with `gcloud run deploy --set-env-vars`
or Cloud Run Secret Manager mounts.
"""

from functools import lru_cache
from typing import Self

from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """App settings loaded from environment variables."""

    database_url: str = "sqlite:///./dev.db"
    app_url: str = "http://localhost:8080"
    environment: str = "development"

    # Magic-link sign-in (ADR-002). RESEND_API_KEY is required in any
    # environment where /login is exercised; the Settings validator below
    # gates non-dev environments. The base URL and from-email default to
    # values safe for local dev so the test suite needs no env setup.
    resend_api_key: str = ""
    magic_link_base_url: str = "http://localhost:8080"
    magic_link_from_email: str = "onboarding@resend.dev"

    # Anthropic LLM (ADR-001). Used by app/services/comprehension/generator.py
    # to generate reading-comprehension questions. The route layer that
    # consumes this builds the client lazily so missing config doesn't
    # fail the app boot — just the /questions feature degrades.
    anthropic_api_key: str = ""
    anthropic_model: str = "claude-haiku-4-5"

    # Session cookie signing (AUTH-2). 32+ random bytes, set per environment
    # via Secret Manager. The dev default is the literal string "dev-only"
    # so tests can run with no env setup; the validator below refuses this
    # default in non-dev environments.
    session_secret: str = "dev-only"
    session_ttl_days: int = 30
    session_cookie_secure: bool = True

    # Neon Auth (AUTH-7 / #62). Populated per-environment from the values
    # captured by Laura in AUTH-6 / #61 via the Neon Console. Per Neon's
    # 2026-01-30 breaking change, NEON_AUTH_COOKIE_SECRET became mandatory
    # for session signing — generate once with
    # `python -c "import secrets; print(secrets.token_urlsafe(32))"` and
    # share across environments (it's the cookie signer, not a per-branch
    # key).
    #
    # The migration ships behind the AUTH_PROVIDER flag (T6 / #66): both
    # the Resend code path AND the Neon Auth code path live in the same
    # image, and the flag selects which one /login dispatches to. Default
    # `resend` preserves current behavior; T12 flips production to `neon`.
    auth_provider: str = "resend"  # "resend" | "neon"
    neon_auth_base_url: str = ""
    neon_auth_jwks_url: str = ""
    neon_auth_cookie_secret: str = ""
    stack_secret_server_key: str = ""
    # Publishable client key — public-by-design, exposed to the browser via
    # the sign-in template. Name follows Neon's convention which mirrors
    # Stack Auth's frontend-framework prefixes (NEXT_PUBLIC_ / VITE_); we
    # don't host a JS bundler so we drop the framework prefix here and
    # surface the value to Jinja via this single name.
    stack_publishable_client_key: str = ""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    @field_validator("database_url")
    @classmethod
    def _force_psycopg3_driver(cls, v: str) -> str:
        # Neon emits postgresql:// URLs, which SQLAlchemy resolves to the
        # psycopg2 driver. We ship psycopg3 only, so rewrite the scheme.
        if v.startswith("postgresql://"):
            return v.replace("postgresql://", "postgresql+psycopg://", 1)
        return v

    @model_validator(mode="after")
    def _refuse_sqlite_outside_dev(self) -> Self:
        # Defense-in-depth: the dev-default sqlite URL must never reach
        # any non-dev runtime (production, preview, staging). If
        # DATABASE_URL is missing or doesn't override the default, fail
        # at startup with a clear message rather than 500ing on the
        # first DB query with `no such table: todo`. Originally only
        # gated `production`; #78 generalized after a 2026-04-30 dry-run
        # showed previews silently fell through to SQLite when Neon was
        # unconfigured. See #63 / #71 / #78.
        if self.environment in ("development", "test"):
            return self
        if not self.database_url:
            raise ValueError(
                f"DATABASE_URL is empty in {self.environment}. "
                "Check that DATABASE_URL is set on the Cloud Run revision "
                "(production reads from PRODUCTION_DATABASE_URL secret; "
                "preview reads from the Neon branch action output)."
            )
        if self.database_url.startswith("sqlite"):
            raise ValueError(
                f"DATABASE_URL is SQLite in {self.environment}: {self.database_url!r}. "
                "Non-dev environments must use Postgres. Likely cause: the "
                "DATABASE_URL env var didn't override the dev default — for "
                "previews, NEON_API_KEY may be unconfigured so the Neon branch "
                "step was skipped."
            )
        if self.session_secret in ("", "dev-only"):
            raise ValueError(
                f"SESSION_SECRET is the dev default or empty in {self.environment}. "
                "Generate 32+ random bytes (e.g. `python -c 'import secrets; "
                "print(secrets.token_urlsafe(32))'`) and set as a Cloud Run env "
                "var (production reads from the SESSION_SECRET secret in Secret "
                "Manager). Without this, every session cookie is forgeable."
            )
        return self

    @model_validator(mode="after")
    def _validate_neon_auth_consistency(self) -> Self:
        # When AUTH_PROVIDER is "neon", all five Neon Auth env vars must be
        # populated. We refuse to start rather than 500ing on the first sign-in
        # request. The AUTH_PROVIDER flag (T6) keeps the migration safely
        # gated: default "resend" preserves current behavior; flipping to
        # "neon" requires all values present.
        if self.auth_provider not in ("resend", "neon"):
            raise ValueError(
                f"AUTH_PROVIDER must be 'resend' or 'neon' (got {self.auth_provider!r})."
            )
        if self.auth_provider == "neon":
            missing = [
                name
                for name, value in (
                    ("NEON_AUTH_BASE_URL", self.neon_auth_base_url),
                    ("NEON_AUTH_JWKS_URL", self.neon_auth_jwks_url),
                    ("NEON_AUTH_COOKIE_SECRET", self.neon_auth_cookie_secret),
                    ("STACK_SECRET_SERVER_KEY", self.stack_secret_server_key),
                    (
                        "STACK_PUBLISHABLE_CLIENT_KEY",
                        self.stack_publishable_client_key,
                    ),
                )
                if not value
            ]
            if missing:
                raise ValueError(
                    f"AUTH_PROVIDER=neon requires all Neon Auth env vars; "
                    f"missing: {', '.join(missing)}. See AUTH-6 / issue #61 for "
                    "where these values come from (Neon Console)."
                )
        return self

    @model_validator(mode="after")
    def _refuse_non_ascii_in_secrets(self) -> Self:
        # Defense-in-depth against paste-mishap bugs (the PR #50 `√` incident).
        # Header-bound values MUST be ASCII or urllib3 raises UnicodeEncodeError
        # at the first outbound HTTP call — invisible because background tasks
        # swallow the error before it reaches the user.
        header_bound_secrets = {
            "RESEND_API_KEY": self.resend_api_key,
            "STACK_SECRET_SERVER_KEY": self.stack_secret_server_key,
            "STACK_PUBLISHABLE_CLIENT_KEY": self.stack_publishable_client_key,
            "ANTHROPIC_API_KEY": self.anthropic_api_key,
            "NEON_AUTH_COOKIE_SECRET": self.neon_auth_cookie_secret,
        }
        for name, value in header_bound_secrets.items():
            if value and not value.isascii():
                bad_char = next(c for c in value if ord(c) > 127)
                raise ValueError(
                    f"{name} contains non-ASCII char {bad_char!r} (likely a paste "
                    "mishap — Word/clipboard autoformat introduces these silently). "
                    "Re-copy the value from its source and re-set the secret."
                )
        return self


@lru_cache
def get_settings() -> Settings:
    """Cached settings accessor.

    Uses lru_cache so settings are loaded exactly once per process.
    Tests can override this via dependency injection.
    """
    return Settings()
