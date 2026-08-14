"""Unit tests for scripts/smoke_auth.py pure logic.

The synthetic monitor itself can't run without a live Supabase + deployed
app, but `_cookie_header_clears` is pure Set-Cookie parsing — the one piece
of nontrivial logic that can drift silently (e.g. if Starlette changes how
`delete_cookie` formats its header). Pin its behavior here.
"""

from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

import scripts.smoke_auth as smoke
from scripts.smoke_auth import _cookie_header_clears


def _set_required_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("SMOKE_BASE_URL", "http://app.test")
    monkeypatch.setenv("SUPABASE_URL", "http://sb.test")
    monkeypatch.setenv("SUPABASE_ANON_KEY", "anon")
    monkeypatch.setenv("SUPABASE_SERVICE_KEY", "service")


def test_empty_value_counts_as_cleared() -> None:
    assert _cookie_header_clears(["sb-access-token=; Path=/; HttpOnly; SameSite=lax"]) is True


def test_max_age_zero_counts_as_cleared() -> None:
    # Non-empty value but Max-Age=0 still means the browser drops it.
    assert _cookie_header_clears(["sb-access-token=stale; Max-Age=0; Path=/"]) is True


def test_epoch_expiry_counts_as_cleared() -> None:
    assert (
        _cookie_header_clears(
            ["sb-access-token=stale; expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=/"]
        )
        is True
    )


def test_active_cookie_is_not_cleared() -> None:
    assert (
        _cookie_header_clears(["sb-access-token=realtoken123; Path=/; Max-Age=604800; HttpOnly"])
        is False
    )


def test_other_cookies_are_ignored() -> None:
    # A different cookie being cleared must not count as the session cookie
    # being cleared.
    assert _cookie_header_clears(["other=; Max-Age=0; Path=/"]) is False


def test_empty_header_list_is_not_cleared() -> None:
    assert _cookie_header_clears([]) is False


def test_finds_clear_among_multiple_set_cookie_lines() -> None:
    assert (
        _cookie_header_clears(["csrftoken=abc; Path=/", "sb-access-token=; Max-Age=0; Path=/"])
        is True
    )


# ---------------------------------------------------------------------------
# Cleanup robustness — the throwaway user must never leak (runs hourly on prod)
# ---------------------------------------------------------------------------


def test_throwaway_user_deleted_when_sign_in_raises(monkeypatch: pytest.MonkeyPatch) -> None:
    """If sign-in raises a transient Supabase error AFTER the user is created,
    main() must still delete the user and report a clean FAIL (exit 1) — not
    leak the user or crash with a traceback."""
    _set_required_env(monkeypatch)

    service_fake = MagicMock()
    service_fake.auth.admin.create_user.return_value = SimpleNamespace(
        user=SimpleNamespace(id="user-abc")
    )
    anon_fake = MagicMock()
    anon_fake.auth.sign_in_with_password.side_effect = RuntimeError("supabase 503")

    monkeypatch.setattr(smoke, "create_client", MagicMock(side_effect=[service_fake, anon_fake]))

    assert smoke.main() == 1
    service_fake.auth.admin.delete_user.assert_called_once_with("user-abc")


def test_no_delete_when_user_creation_fails(monkeypatch: pytest.MonkeyPatch) -> None:
    """If create_user never yields a user, there's nothing to clean up —
    delete must not be called with a bogus/None id."""
    _set_required_env(monkeypatch)

    service_fake = MagicMock()
    service_fake.auth.admin.create_user.return_value = SimpleNamespace(user=None)
    anon_fake = MagicMock()

    monkeypatch.setattr(smoke, "create_client", MagicMock(side_effect=[service_fake, anon_fake]))

    assert smoke.main() == 1
    service_fake.auth.admin.delete_user.assert_not_called()


# ---------------------------------------------------------------------------
# #291 — POST /login email-send check classifies statuses correctly
# ---------------------------------------------------------------------------


def test_login_send_202_is_ok() -> None:
    assert smoke._login_send_outcome(202) == "ok"


def test_login_send_429_is_soft_rate_limited() -> None:
    """A rate limit is self-clearing, not an outage — must not fail the run."""
    assert smoke._login_send_outcome(429) == "rate_limited"


@pytest.mark.parametrize("status", [502, 500, 400, 422, 503])
def test_login_send_other_statuses_raise(status: int) -> None:
    """502 (broken mailer, e.g. SMTP 535) and any other non-202/429 status
    must raise so the monitor fails and pages."""
    with pytest.raises(smoke.SmokeFailure):
        smoke._login_send_outcome(status)


def test_login_send_failure_fails_run_and_cleans_up(monkeypatch: pytest.MonkeyPatch) -> None:
    """An email-send outage (POST /login → 502) must fail the monitor (exit 1)
    AND still delete the throwaway user — the outage this check exists to catch
    must not also leak a user."""
    _set_required_env(monkeypatch)

    service_fake = MagicMock()
    service_fake.auth.admin.create_user.return_value = SimpleNamespace(
        user=SimpleNamespace(id="user-xyz")
    )
    anon_fake = MagicMock()
    monkeypatch.setattr(smoke, "create_client", MagicMock(side_effect=[service_fake, anon_fake]))
    # Simulate the mailer being down: the send check raises before sign-in.
    monkeypatch.setattr(
        smoke,
        "check_login_send",
        MagicMock(side_effect=smoke.SmokeFailure("POST /login returned 502")),
    )

    assert smoke.main() == 1
    service_fake.auth.admin.delete_user.assert_called_once_with("user-xyz")
    # The session flow must not have run once the send check failed.
    anon_fake.auth.sign_in_with_password.assert_not_called()
