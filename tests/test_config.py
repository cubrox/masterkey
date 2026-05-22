"""Tests for app.config.Settings.

Pins two contracts:
  1. database_url is normalized to use the psycopg3 driver scheme.
     SQLAlchemy resolves the bare `postgresql://` scheme to psycopg2
     (not installed in this project), so without normalization every
     Neon-backed deploy would ImportError on first DB use.
  2. In production, an empty or sqlite-shaped DATABASE_URL fails fast
     at Settings construction (model validator) — turns the silent
     "first request 500s with no such table: todo" failure mode into
     a loud ValueError at startup. See #63.
"""

import pytest


def _make_settings(database_url: str | None = None):
    # Import inside the helper so each call sees the patched env. The
    # @lru_cache on get_settings is process-level; we instantiate
    # Settings() directly to bypass it.
    from app.config import Settings

    if database_url is None:
        return Settings()
    return Settings(database_url=database_url)


@pytest.mark.parametrize(
    "input_url,expected",
    [
        # The live-bug case: Neon emits postgresql://, must become postgresql+psycopg://
        (
            "postgresql://u:p@h/db",
            "postgresql+psycopg://u:p@h/db",
        ),
        # Already-normalized URLs pass through unchanged
        (
            "postgresql+psycopg://u:p@h/db",
            "postgresql+psycopg://u:p@h/db",
        ),
        # Non-postgres schemes are untouched
        ("sqlite:///./dev.db", "sqlite:///./dev.db"),
        ("sqlite://", "sqlite://"),
        # Only the scheme is rewritten; query string + path preserved
        (
            "postgresql://user:pa%40ss@host:5432/db?sslmode=require",
            "postgresql+psycopg://user:pa%40ss@host:5432/db?sslmode=require",
        ),
    ],
)
def test_database_url_scheme_normalization(input_url: str, expected: str) -> None:
    assert _make_settings(input_url).database_url == expected


def test_production_empty_database_url_fails(monkeypatch: pytest.MonkeyPatch) -> None:
    # Reading the empty-string case requires going through env vars: a
    # bare Settings(database_url="") would still trigger this, but the
    # realistic failure mode is the secret mount producing an empty env
    # var, so we exercise that path explicitly.
    monkeypatch.setenv("ENVIRONMENT", "production")
    monkeypatch.setenv("DATABASE_URL", "")
    from app.config import Settings

    with pytest.raises(ValueError, match="DATABASE_URL is empty in production"):
        Settings()


def test_production_sqlite_database_url_fails(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ENVIRONMENT", "production")
    monkeypatch.setenv("DATABASE_URL", "sqlite:///./dev.db")
    from app.config import Settings

    with pytest.raises(ValueError, match="DATABASE_URL is SQLite in production"):
        Settings()


def test_development_empty_database_url_uses_sqlite_default(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Development is the local-dev path: missing DATABASE_URL must NOT
    # raise — pydantic's default ("sqlite:///./dev.db") applies and the
    # app boots against the local SQLite file.
    monkeypatch.setenv("ENVIRONMENT", "development")
    monkeypatch.delenv("DATABASE_URL", raising=False)
    from app.config import Settings

    settings = Settings()
    assert settings.database_url == "sqlite:///./dev.db"


def test_production_postgres_url_passes(monkeypatch: pytest.MonkeyPatch) -> None:
    # The happy path: real Neon URL in production. Field validator
    # normalizes it to psycopg3; model validator sees a non-sqlite,
    # non-empty URL and returns clean.
    monkeypatch.setenv("ENVIRONMENT", "production")
    monkeypatch.setenv("DATABASE_URL", "postgresql://u:p@h.neon.tech/db")
    monkeypatch.setenv("SESSION_SECRET", "test-only-not-the-real-secret")
    from app.config import Settings

    settings = Settings()
    assert settings.database_url == "postgresql+psycopg://u:p@h.neon.tech/db"


def test_preview_sqlite_database_url_fails(monkeypatch: pytest.MonkeyPatch) -> None:
    # The 2026-04-30 dry-run failure mode: Neon unconfigured, preview
    # falls through to the dev-default `sqlite:///./dev.db`, app boots
    # and 500s on the first DB query. The validator must catch this
    # before the container starts, with the same loudness as production.
    monkeypatch.setenv("ENVIRONMENT", "preview")
    monkeypatch.setenv("DATABASE_URL", "sqlite:///./dev.db")
    from app.config import Settings

    with pytest.raises(ValueError, match="DATABASE_URL is SQLite in preview"):
        Settings()


def test_preview_postgres_url_passes(monkeypatch: pytest.MonkeyPatch) -> None:
    # Happy path for preview: Neon branch URL flows through field
    # validator psycopg3 normalization and is accepted by the model
    # validator. Confirms #78 didn't accidentally break the preview
    # happy path while widening the gate.
    monkeypatch.setenv("ENVIRONMENT", "preview")
    monkeypatch.setenv("DATABASE_URL", "postgresql://u:p@h.neon.tech/preview-pr-1")
    monkeypatch.setenv("SESSION_SECRET", "test-only-not-the-real-secret")
    from app.config import Settings

    settings = Settings()
    assert settings.database_url == "postgresql+psycopg://u:p@h.neon.tech/preview-pr-1"


def test_unfamiliar_environment_treated_as_non_dev(monkeypatch: pytest.MonkeyPatch) -> None:
    # Future-proofing: any environment name that isn't "development" or
    # "test" is treated as a non-dev runtime. A staging deploy with
    # ENVIRONMENT=staging gets the same SQLite refusal as production.
    monkeypatch.setenv("ENVIRONMENT", "staging")
    monkeypatch.setenv("DATABASE_URL", "sqlite://")
    from app.config import Settings

    with pytest.raises(ValueError, match="DATABASE_URL is SQLite in staging"):
        Settings()


def test_test_environment_allows_sqlite(monkeypatch: pytest.MonkeyPatch) -> None:
    # The test fixtures explicitly use sqlite:// (in-memory) — so
    # ENVIRONMENT=test must be in the allow list alongside development.
    # Without this, every pytest run that sets ENVIRONMENT=test would
    # fail at Settings() construction.
    monkeypatch.setenv("ENVIRONMENT", "test")
    monkeypatch.setenv("DATABASE_URL", "sqlite://")
    from app.config import Settings

    settings = Settings()
    assert settings.database_url == "sqlite://"


# ── Neon Auth consistency validator (AUTH-7 / #62) ───────────────────


def test_auth_provider_default_is_resend(monkeypatch: pytest.MonkeyPatch) -> None:
    # Backwards-compat: existing deploys without AUTH_PROVIDER set keep
    # the Resend path. T12 (#71) flips production to "neon" by setting
    # the repo variable; until then, omission must equal "resend".
    monkeypatch.delenv("AUTH_PROVIDER", raising=False)
    from app.config import Settings

    assert Settings().auth_provider == "resend"


def test_auth_provider_invalid_value_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("AUTH_PROVIDER", "auth0")
    from app.config import Settings

    with pytest.raises(ValueError, match="AUTH_PROVIDER must be 'resend' or 'neon'"):
        Settings()


def test_auth_provider_neon_requires_all_env_vars(monkeypatch: pytest.MonkeyPatch) -> None:
    # The migration-safety gate: flipping AUTH_PROVIDER=neon with any
    # Neon Auth env var missing is a misconfiguration that would 500 on
    # the first sign-in request. Refuse to start instead.
    monkeypatch.setenv("AUTH_PROVIDER", "neon")
    monkeypatch.delenv("NEON_AUTH_BASE_URL", raising=False)
    monkeypatch.delenv("NEON_AUTH_JWKS_URL", raising=False)
    monkeypatch.delenv("NEON_AUTH_COOKIE_SECRET", raising=False)
    monkeypatch.delenv("STACK_SECRET_SERVER_KEY", raising=False)
    monkeypatch.delenv("STACK_PUBLISHABLE_CLIENT_KEY", raising=False)
    from app.config import Settings

    with pytest.raises(ValueError, match="AUTH_PROVIDER=neon requires all Neon Auth env vars"):
        Settings()


def test_auth_provider_neon_partial_config_lists_missing(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # The error message must name the specific missing vars so operators
    # don't have to bisect — `missing: STACK_SECRET_SERVER_KEY, ...`
    # rather than a generic "config invalid".
    monkeypatch.setenv("AUTH_PROVIDER", "neon")
    monkeypatch.setenv("NEON_AUTH_BASE_URL", "https://example.neon.app")
    monkeypatch.setenv("NEON_AUTH_JWKS_URL", "https://example.neon.app/.well-known/jwks.json")
    monkeypatch.setenv("NEON_AUTH_COOKIE_SECRET", "test-cookie-secret-32-bytes-min-aaaa")
    monkeypatch.delenv("STACK_SECRET_SERVER_KEY", raising=False)
    monkeypatch.delenv("STACK_PUBLISHABLE_CLIENT_KEY", raising=False)
    from app.config import Settings

    with pytest.raises(
        ValueError,
        match=r"missing: STACK_SECRET_SERVER_KEY, STACK_PUBLISHABLE_CLIENT_KEY",
    ):
        Settings()


def test_auth_provider_neon_with_all_vars_passes(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("AUTH_PROVIDER", "neon")
    monkeypatch.setenv("NEON_AUTH_BASE_URL", "https://example.neon.app")
    monkeypatch.setenv("NEON_AUTH_JWKS_URL", "https://example.neon.app/.well-known/jwks.json")
    monkeypatch.setenv("NEON_AUTH_COOKIE_SECRET", "test-cookie-secret-32-bytes-min-aaaa")
    monkeypatch.setenv("STACK_SECRET_SERVER_KEY", "ssk_test_abcdef")
    monkeypatch.setenv("STACK_PUBLISHABLE_CLIENT_KEY", "spk_test_abcdef")
    from app.config import Settings

    settings = Settings()
    assert settings.auth_provider == "neon"
    assert settings.neon_auth_jwks_url == "https://example.neon.app/.well-known/jwks.json"


def test_auth_provider_resend_does_not_require_neon_vars(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Default path: AUTH_PROVIDER=resend means the Neon Auth code path is
    # never exercised, so its env vars don't need to be populated. This
    # is what every existing deploy looks like prior to T12.
    monkeypatch.setenv("AUTH_PROVIDER", "resend")
    monkeypatch.delenv("NEON_AUTH_BASE_URL", raising=False)
    monkeypatch.delenv("STACK_SECRET_SERVER_KEY", raising=False)
    from app.config import Settings

    settings = Settings()
    assert settings.auth_provider == "resend"


# ── Non-ASCII secret validator (defense against PR #50 paste-mishap) ─


def test_resend_api_key_with_non_ascii_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    # PR #50 incident: a `√` character snuck into RESEND_API_KEY via
    # Word-style clipboard autoformat. urllib3 raised UnicodeEncodeError
    # at the first outbound HTTP call, but background-task wrapping
    # swallowed the error — magic-link emails silently failed in prod.
    # Refuse the value at startup instead.
    monkeypatch.setenv("RESEND_API_KEY", "re_abc√def")
    from app.config import Settings

    with pytest.raises(ValueError, match="RESEND_API_KEY contains non-ASCII char"):
        Settings()


def test_neon_auth_cookie_secret_with_non_ascii_rejected(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("NEON_AUTH_COOKIE_SECRET", "secret-with-em-dash-—-inside")
    from app.config import Settings

    with pytest.raises(ValueError, match="NEON_AUTH_COOKIE_SECRET contains non-ASCII char"):
        Settings()


def test_stack_server_key_with_non_ascii_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("STACK_SECRET_SERVER_KEY", "ssk_test_ñope")
    from app.config import Settings

    with pytest.raises(ValueError, match="STACK_SECRET_SERVER_KEY contains non-ASCII char"):
        Settings()


def test_empty_secrets_skip_ascii_check(monkeypatch: pytest.MonkeyPatch) -> None:
    # Empty values must not trigger the validator — the dev/test path
    # leaves all five secrets empty and the validator should pass cleanly.
    monkeypatch.delenv("RESEND_API_KEY", raising=False)
    monkeypatch.delenv("STACK_SECRET_SERVER_KEY", raising=False)
    monkeypatch.delenv("STACK_PUBLISHABLE_CLIENT_KEY", raising=False)
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    monkeypatch.delenv("NEON_AUTH_COOKIE_SECRET", raising=False)
    from app.config import Settings

    Settings()  # must not raise


def test_ascii_secrets_pass(monkeypatch: pytest.MonkeyPatch) -> None:
    # Happy path: realistic-shaped ASCII values across every guarded
    # secret slot pass through cleanly.
    monkeypatch.setenv("RESEND_API_KEY", "re_abcdef123456")
    monkeypatch.setenv("STACK_SECRET_SERVER_KEY", "ssk_test_abcdef")
    monkeypatch.setenv("STACK_PUBLISHABLE_CLIENT_KEY", "spk_test_abcdef")
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-api03-abcdef")
    monkeypatch.setenv("NEON_AUTH_COOKIE_SECRET", "0123456789abcdef0123456789abcdef")
    from app.config import Settings

    Settings()  # must not raise
