"""Session cookie sign + verify helpers + current_user dependency.

**Transitional state (SUPA-3, #82):** `current_user` is now dual-path.
It first checks the Supabase JWT cookie (`sb-access-token`) and, if
that's valid, returns a lazily-mirrored `User` row whose primary key
matches the Supabase `auth.users.id`. If no Supabase cookie is present
(or it's invalid), it falls back to the legacy itsdangerous-signed
cookie. The legacy path stays alive so the test suite (which sets
`sign_session(...)` cookies directly) keeps working until SUPA-5
rewrites it. SUPA-2b (#87) deletes the legacy path entirely.

The legacy half — `sign_session`, `verify_session`, the
`itsdangerous`-based payload, and the `_legacy_current_user` helper —
is preserved verbatim from the ADR-002 implementation.
"""

import uuid
from datetime import UTC, datetime, timedelta
from typing import Annotated, Any

from fastapi import Depends, Request, Response
from itsdangerous import BadSignature, SignatureExpired, URLSafeTimedSerializer
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session

from app.config import Settings, get_settings
from app.db import get_session
from app.models.user import User

SESSION_COOKIE_NAME = "session"
SESSION_SALT = "cubrox-session-cookie-v1"
SUPABASE_COOKIE_NAME = "sb-access-token"

# A cookie older than this gets re-issued with a fresh issued_at on the
# next authenticated request. The cookie's max_age stays at the full
# SESSION_TTL_DAYS — re-issue extends the user's effective session as
# long as they keep using Cubrox.
SESSION_REISSUE_AFTER_DAYS = 7


class UnauthenticatedError(Exception):
    """Raised by `current_user` when the request has no valid session.

    Caught by the app-level exception handler (in app/main.py), which
    converts it to either:
      - 303 redirect to /login (browser top-level navigation), or
      - 200 + HX-Redirect: /login (HTMX request — won't follow a normal
        303 because it intercepts the response before the browser does).
    """


def _serializer(secret: str) -> URLSafeTimedSerializer:
    return URLSafeTimedSerializer(secret_key=secret, salt=SESSION_SALT)


def sign_session(*, user_id: uuid.UUID, secret: str) -> str:
    """Produce the signed cookie value for a user just signed in.

    Payload contains only `user_id` and `issued_at` — no email or other
    PII. The signature pins both values; tampering with either yields
    BadSignature on verification.
    """
    payload: dict[str, Any] = {
        "user_id": str(user_id),
        "issued_at": datetime.now(UTC).isoformat(),
    }
    return _serializer(secret).dumps(payload)


def verify_session(*, value: str, secret: str, max_age_seconds: int) -> dict[str, Any] | None:
    """Decode + verify a session cookie value.

    Returns the payload dict on success, or None on ANY failure
    (bad signature, expired, malformed). Callers should treat `None` as
    "unauthenticated" — same outcome as if no cookie was sent.
    """
    try:
        payload = _serializer(secret).loads(value, max_age=max_age_seconds)
    except (BadSignature, SignatureExpired):
        return None
    if not isinstance(payload, dict):
        return None
    return payload


def _ensure_neon_user_mirror(*, supabase_user_id: str, email: str, session: Session) -> User:
    """Return the Neon `User` row whose PK matches the Supabase user id.

    Lazy-create the row if it doesn't exist yet (first time we see a
    given Supabase user). Race-safe via `IntegrityError` rollback +
    re-fetch — two concurrent first-requests for the same user can't
    both insert. This is the shim that lets the rest of the app keep
    using the legacy `User` SQLModel while auth is sourced from
    Supabase; SUPA-2b deletes both the model and this helper.
    """
    user_id = uuid.UUID(supabase_user_id)
    existing = session.get(User, user_id)
    if existing is not None:
        return existing
    mirror = User(id=user_id, email=email)
    session.add(mirror)
    try:
        session.commit()
        session.refresh(mirror)
        return mirror
    except IntegrityError:
        session.rollback()
        racer = session.get(User, user_id)
        if racer is not None:
            return racer
        # Extremely unlikely — IntegrityError without the row being there
        # would mean a constraint violation other than the PK race.
        raise UnauthenticatedError() from None


def current_user(
    request: Request,
    response: Response,
    session: Annotated[Session, Depends(get_session)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> User:
    """FastAPI dependency that resolves the request's signed-in user.

    **Dual-path (SUPA-3 transitional):**

    1. If the request has a Supabase JWT cookie (`sb-access-token`),
       validate it via Supabase Auth and return a lazily-mirrored Neon
       `User` row. This is the production path.
    2. Otherwise, fall back to the legacy itsdangerous-signed `session`
       cookie. This path keeps existing tests and any in-flight
       pre-cutover sessions working until SUPA-2b (#87) deletes it.

    Either path raising → `UnauthenticatedError`, caught by the
    app-level handler in `app/main.py` for the redirect.
    """
    sb_token = request.cookies.get(SUPABASE_COOKIE_NAME)
    if sb_token:
        # Local import — avoid pulling the supabase package at module
        # import time so the tests that don't touch auth don't pay the
        # import cost, and so a missing SUPABASE_URL in dev doesn't
        # crash the whole import graph.
        from app.integrations.supabase.client import anon_client  # noqa: PLC0415

        try:
            sb_resp = anon_client().auth.get_user(sb_token)
        except Exception:
            sb_resp = None
        if sb_resp is not None and sb_resp.user is not None and sb_resp.user.email:
            return _ensure_neon_user_mirror(
                supabase_user_id=sb_resp.user.id,
                email=sb_resp.user.email,
                session=session,
            )
        # sb-access-token was present but invalid — fall through to
        # the legacy path. In steady-state production this is the
        # signal to raise; we keep falling through during transition
        # so that the legacy cookie still works if the user has both.

    return _legacy_current_user(
        request=request,
        response=response,
        session=session,
        settings=settings,
    )


def _legacy_current_user(
    *,
    request: Request,
    response: Response,
    session: Session,
    settings: Settings,
) -> User:
    """Original itsdangerous-signed-cookie auth path.

    Preserved verbatim from the pre-SUPA-3 implementation. Used as the
    fallback in `current_user` and removed entirely in SUPA-2b (#87)
    once tests are rewritten in SUPA-5.
    """
    cookie_value = request.cookies.get(SESSION_COOKIE_NAME)
    if cookie_value is None:
        raise UnauthenticatedError()

    max_age = settings.session_ttl_days * 86400
    payload = verify_session(
        value=cookie_value, secret=settings.session_secret, max_age_seconds=max_age
    )
    if payload is None:
        raise UnauthenticatedError()

    raw_user_id = payload.get("user_id")
    if not isinstance(raw_user_id, str):
        raise UnauthenticatedError()
    try:
        user_id = uuid.UUID(raw_user_id)
    except ValueError as exc:
        raise UnauthenticatedError() from exc

    user = session.get(User, user_id)
    if user is None:
        # The user_id in the cookie no longer exists in the DB (deleted
        # via psql admin, or the cookie was forged with a plausible
        # UUID). Treat as unauthenticated.
        raise UnauthenticatedError()

    # Rolling re-issue. Cheap to do every time we cross the 7-day mark.
    issued_at_str = payload.get("issued_at")
    if isinstance(issued_at_str, str):
        try:
            issued_at = datetime.fromisoformat(issued_at_str)
        except ValueError:
            issued_at = None
        if issued_at is not None:
            age = datetime.now(UTC) - issued_at
            if age > timedelta(days=SESSION_REISSUE_AFTER_DAYS):
                response.set_cookie(
                    key=SESSION_COOKIE_NAME,
                    value=sign_session(user_id=user.id, secret=settings.session_secret),
                    max_age=max_age,
                    httponly=True,
                    secure=settings.session_cookie_secure,
                    samesite="lax",
                )

    return user


def try_current_user(
    request: Request,
    response: Response,
    session: Annotated[Session, Depends(get_session)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> User | None:
    """Soft-auth variant of `current_user`: returns `User | None` instead of
    raising on no/invalid session.

    Use this when a route needs to render differently for signed-in vs.
    anonymous visitors but should NOT trigger the AUTH-3 redirect for
    anonymous ones (e.g. the landing page, which renders the sign-in
    form for anonymous visitors and redirects authed visitors away).

    Shares all cookie-verification logic with `current_user` so the
    "is this session valid" rules stay in one place.
    """
    try:
        return current_user(
            request=request,
            response=response,
            session=session,
            settings=settings,
        )
    except UnauthenticatedError:
        return None
