"""Shared pytest fixtures.

Uses an in-memory SQLite database per test so tests don't touch Neon or
pollute each other. The app's get_session dependency is overridden to
yield sessions bound to the test engine.

The autouse `_stub_supabase` fixture replaces the real Supabase client
with a MagicMock so any route that calls `anon_client()` (POST /login,
GET /auth/callback) succeeds without network. Tests authenticate via
the legacy itsdangerous cookie path — `current_user` falls through to
it when no `sb-access-token` cookie is set. SUPA-5 (#84) rewrites this
fixture set against a real local Supabase.
"""

from collections.abc import Generator
from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session, SQLModel, create_engine
from sqlmodel.pool import StaticPool

from app.db import get_session
from app.integrations.supabase import client as supabase_client_module
from app.main import app


@pytest.fixture(autouse=True)
def _stub_supabase(monkeypatch: pytest.MonkeyPatch) -> None:
    """Patch supabase.create_client to return a MagicMock for every test.

    Auth-flow tests that POST /login or GET /auth/callback hit the new
    Supabase path; without this stub, anon_client() would attempt a
    real HTTP call to Supabase (which would fail anyway since
    SUPABASE_URL is the empty-string default in test env).
    """
    fake = MagicMock()
    monkeypatch.setattr(supabase_client_module, "create_client", lambda *a, **k: fake)
    supabase_client_module.anon_client.cache_clear()
    supabase_client_module.service_client.cache_clear()


@pytest.fixture(name="session")
def session_fixture() -> Generator[Session, None, None]:
    """Fresh in-memory SQLite database for each test."""
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)
    with Session(engine) as session:
        yield session


@pytest.fixture(name="client")
def client_fixture(session: Session) -> Generator[TestClient, None, None]:
    """TestClient with get_session overridden to use the test session."""

    def get_session_override() -> Generator[Session, None, None]:
        yield session

    app.dependency_overrides[get_session] = get_session_override
    with TestClient(app) as client:
        yield client
    app.dependency_overrides.clear()
