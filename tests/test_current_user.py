"""Tests for the `current_user` FastAPI dependency (Supabase, single-path).

After SUPA-2c (#91), `current_user` is single-path Supabase — the
legacy itsdangerous fallback and the lazy-Neon-mirror shim are both
gone. Routes get the Supabase `gotrue.types.User` object directly;
the only attributes they touch are `.id` and `.email`.

`signed_in()` in conftest authenticates by overriding the dependency
(not by setting a cookie), so the cookie-validation path itself is
exercised here.
"""

from types import SimpleNamespace
from unittest.mock import MagicMock
from uuid import uuid4

from fastapi.testclient import TestClient

SUPABASE_COOKIE = "sb-access-token"


def test_valid_supabase_jwt_returns_user_info(client: TestClient, supabase_mock: MagicMock) -> None:
    """The happy path: a valid Supabase JWT cookie → /api/me returns
    the user's id + email."""
    fake_id = str(uuid4())
    fake_user = SimpleNamespace(id=fake_id, email="reader@example.com")
    supabase_mock.auth.get_user.return_value = SimpleNamespace(user=fake_user)
    client.cookies.set(SUPABASE_COOKIE, "valid-jwt")

    response = client.get("/api/me")
    assert response.status_code == 200
    body = response.json()
    assert body["email"] == "reader@example.com"
    assert body["id"] == fake_id


def test_missing_cookie_browser_request_redirects_to_landing(
    client: TestClient,
) -> None:
    """No cookie → UnauthenticatedError → 303 to /."""
    response = client.get("/api/me", follow_redirects=False)
    assert response.status_code == 303
    assert response.headers["location"] == "/"


def test_missing_cookie_htmx_request_returns_hx_redirect(client: TestClient) -> None:
    """HTMX requests get the HX-Redirect header instead of a 303 the
    browser would intercept."""
    response = client.get("/api/me", headers={"HX-Request": "true"})
    assert response.status_code == 200
    assert response.headers["HX-Redirect"] == "/"


def test_invalid_supabase_jwt_redirects(client: TestClient, supabase_mock: MagicMock) -> None:
    """sb-access-token present but Supabase returns no user →
    UnauthenticatedError → 303."""
    supabase_mock.auth.get_user.return_value = SimpleNamespace(user=None)
    client.cookies.set(SUPABASE_COOKIE, "expired-or-forged")
    response = client.get("/api/me", follow_redirects=False)
    assert response.status_code == 303


def test_supabase_raises_redirects(client: TestClient, supabase_mock: MagicMock) -> None:
    """If supabase-py raises (network / malformed JWT), treat as
    unauthenticated rather than 500."""
    supabase_mock.auth.get_user.side_effect = RuntimeError("network")
    client.cookies.set(SUPABASE_COOKIE, "garbage")
    response = client.get("/api/me", follow_redirects=False)
    assert response.status_code == 303
