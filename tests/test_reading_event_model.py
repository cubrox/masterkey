"""Tests for the ReadingEvent model (METRIC-1 #21).

Covers persistence + the CHECK invariant. CASCADE behavior is tested
in tests/test_reading_event_migration.py against an Alembic-applied
schema with SQLite FK enforcement explicitly enabled — the default
test engine does not enforce FKs.
"""

import time
import uuid
from datetime import UTC, datetime

import pytest
import sqlalchemy.exc
from sqlmodel import Session, select

from app.models.passage import Passage
from app.models.reading_event import ReadingEvent
from app.models.user import User


def _seed_user_and_passage(session: Session) -> tuple[User, Passage]:
    user = User(email="reader@example.com")
    session.add(user)
    session.commit()
    session.refresh(user)

    passage = Passage(
        user_id=user.id,
        text="lorem ipsum",
        text_hash=b"\x00" * 32,
        source_type="paste",
    )
    session.add(passage)
    session.commit()
    session.refresh(passage)
    return user, passage


def test_insert_and_select_roundtrip(session: Session) -> None:
    user, passage = _seed_user_and_passage(session)

    event = ReadingEvent(
        user_id=user.id,
        passage_id=passage.id,
        lines_processed=42,
    )
    session.add(event)
    session.commit()

    rows = session.exec(select(ReadingEvent)).all()
    assert len(rows) == 1
    saved = rows[0]
    assert saved.user_id == user.id
    assert saved.passage_id == passage.id
    assert saved.lines_processed == 42


def test_occurred_at_defaults_to_now_when_unset(session: Session) -> None:
    """Both layers (model default_factory + migration's server_default
    `now()`) cover this. Under the model-level test path, the
    default_factory fires before INSERT, so we assert it lands close
    to wall-clock time."""
    user, passage = _seed_user_and_passage(session)
    before = datetime.now(UTC)
    time.sleep(0.001)  # ensure default is strictly between before/after

    event = ReadingEvent(user_id=user.id, passage_id=passage.id, lines_processed=1)
    session.add(event)
    session.commit()
    session.refresh(event)

    occurred = event.occurred_at
    if occurred.tzinfo is None:
        # SQLite round-trips TIMESTAMPTZ as naive; treat as UTC.
        occurred = occurred.replace(tzinfo=UTC)
    after = datetime.now(UTC)
    assert before <= occurred <= after
    # Within 1 second of "now" per the ticket DoD.
    assert (after - occurred).total_seconds() < 1.0


def test_lines_processed_zero_is_rejected(session: Session) -> None:
    """The CHECK constraint rejects 0 (and any negative). The error
    surfaces from the DB at commit time as IntegrityError."""
    user, passage = _seed_user_and_passage(session)

    event = ReadingEvent(user_id=user.id, passage_id=passage.id, lines_processed=0)
    session.add(event)
    with pytest.raises(sqlalchemy.exc.IntegrityError):
        session.commit()
    session.rollback()


def test_lines_processed_negative_is_rejected(session: Session) -> None:
    """Belt-and-braces: the same CHECK that catches 0 also catches
    negative values."""
    user, passage = _seed_user_and_passage(session)

    event = ReadingEvent(user_id=user.id, passage_id=passage.id, lines_processed=-5)
    session.add(event)
    with pytest.raises(sqlalchemy.exc.IntegrityError):
        session.commit()
    session.rollback()


def test_explicit_occurred_at_is_respected(session: Session) -> None:
    """If the writer (METRIC-2) chooses to supply `occurred_at`
    explicitly — e.g. backfilling a historical event — the model
    accepts it rather than overwriting with `now()`."""
    user, passage = _seed_user_and_passage(session)
    historical = datetime(2026, 1, 1, 12, 0, 0, tzinfo=UTC)

    event = ReadingEvent(
        user_id=user.id,
        passage_id=passage.id,
        lines_processed=10,
        occurred_at=historical,
    )
    session.add(event)
    session.commit()
    session.refresh(event)

    saved = event.occurred_at
    if saved.tzinfo is None:
        saved = saved.replace(tzinfo=UTC)
    assert saved == historical


def test_distinct_user_passage_pairs_persist_independently(session: Session) -> None:
    """A user can read many passages; two events for the same
    (user, passage) pair are also fine — append-only by design, no
    unique constraint."""
    user, passage = _seed_user_and_passage(session)
    session.add(ReadingEvent(user_id=user.id, passage_id=passage.id, lines_processed=3))
    session.add(ReadingEvent(user_id=user.id, passage_id=passage.id, lines_processed=7))
    session.commit()

    rows = session.exec(select(ReadingEvent)).all()
    assert len(rows) == 2
    assert sum(r.lines_processed for r in rows) == 10


def test_unique_ids_per_event(session: Session) -> None:
    """Default `id=default_factory=uuid.uuid4` produces distinct PKs
    so two rapid inserts don't collide on PK."""
    user, passage = _seed_user_and_passage(session)
    e1 = ReadingEvent(user_id=user.id, passage_id=passage.id, lines_processed=1)
    e2 = ReadingEvent(user_id=user.id, passage_id=passage.id, lines_processed=1)
    session.add_all([e1, e2])
    session.commit()

    assert e1.id != e2.id
    # And both are valid UUIDs (sanity — caught by type but worth
    # asserting at runtime in case anyone changes the default factory).
    uuid.UUID(str(e1.id))
    uuid.UUID(str(e2.id))
