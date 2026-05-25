"""Supabase-backed authentication helpers.

The `current_user` / `try_current_user` FastAPI dependencies and the
`UnauthenticatedError` exception that signals auth failure to
`app/main.py`'s handler. After SUPA-2c (#91) this is the single source
of identity — the legacy itsdangerous cookie path was deleted along
with the User SQLModel + MagicLinkToken table.

The Supabase user object (returned by `db.auth.get_user(token)`) is
the canonical identity now. Routes that previously took
`Annotated[User, Depends(current_user)]` now get a `gotrue.types.User`
or equivalent — the only attributes most routes touch are `.id` and
`.email`, which the Supabase shape preserves.
"""

from typing import Annotated, Any

from fastapi import Depends, Request

from app.integrations.supabase.client import anon_client

SUPABASE_COOKIE_NAME = "sb-access-token"


class UnauthenticatedError(Exception):
    """Raised by `current_user` when the request has no valid Supabase session.

    Caught by the app-level exception handler in `app/main.py`, which
    converts it to either:
      - 303 redirect to `/` (browser top-level navigation), or
      - 200 + `HX-Redirect: /` header (HTMX request)
    """


def current_user(request: Request) -> Any:
    """FastAPI dependency that resolves the request's Supabase user.

    Reads the `sb-access-token` cookie, validates it via Supabase
    Auth, and returns the Supabase user object. Raises
    `UnauthenticatedError` on any failure (no cookie, invalid token,
    Supabase unreachable).
    """
    sb_token = request.cookies.get(SUPABASE_COOKIE_NAME)
    if not sb_token:
        raise UnauthenticatedError()
    try:
        resp = anon_client().auth.get_user(sb_token)
    except Exception as exc:
        raise UnauthenticatedError() from exc
    if resp is None or resp.user is None:
        raise UnauthenticatedError()
    return resp.user


def try_current_user(request: Request) -> Any | None:
    """Soft-auth variant: returns `None` instead of raising on failure.

    Used by routes that render differently for signed-in vs anonymous
    visitors but shouldn't trigger the AUTH-3 redirect for anonymous
    ones (e.g. the landing page renders the sign-in form for None
    users and redirects authed visitors away).
    """
    try:
        return current_user(request)
    except UnauthenticatedError:
        return None


# Re-export Depends-annotated aliases for convenience at call sites.
CurrentUser = Annotated[Any, Depends(current_user)]
OptionalUser = Annotated[Any | None, Depends(try_current_user)]
