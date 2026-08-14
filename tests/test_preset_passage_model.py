"""Tests for the PRESET-1 (#279) schema foundation.

Covers the Definition of Done:
  - preset_passage round-trips (create -> read) with its defaults
  - passage accepts source_type='preset'; an invalid source_type is rejected
  - the new passage attribution columns are nullable (paste/pdf leave them NULL)
    and populated for a preset-sourced passage
"""

import hashlib
import uuid
from datetime import date

import pytest
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.models.passage import Passage
from app.models.preset_passage import PresetPassage


def _hash(text: str) -> bytes:
    return hashlib.sha256(text.encode("utf-8")).digest()


# ---------------------------------------------------------------------------
# preset_passage
# ---------------------------------------------------------------------------


def test_preset_passage_round_trips_with_defaults(session: Session) -> None:
    text = "O Son of Spirit! My first counsel is this..."
    preset = PresetPassage(
        title="Ridván 2024 Message",
        source_url="https://www.bahai.org/library/authoritative-texts/x",
        text=text,
        text_hash=_hash(text),
    )
    session.add(preset)
    session.commit()

    row = session.exec(select(PresetPassage)).one()
    assert row.title == "Ridván 2024 Message"
    assert row.text == text
    assert row.text_hash == _hash(text)
    # Defaults applied.
    assert row.copyright_holder == "Bahá'í International Community"
    assert row.is_active is True
    assert row.sort_order == 0
    assert row.author is None
    assert row.source_date is None
    assert row.created_at is not None


def test_preset_passage_accepts_full_attribution(session: Session) -> None:
    preset = PresetPassage(
        title="A Named Letter",
        author="The Universal House of Justice",
        copyright_holder="Bahá'í International Community",
        source_url="https://www.bahai.org/x",
        source_date=date(2024, 4, 21),
        text="body",
        text_hash=_hash("body"),
        is_active=False,
        sort_order=5,
    )
    session.add(preset)
    session.commit()

    row = session.exec(select(PresetPassage)).one()
    assert row.author == "The Universal House of Justice"
    assert row.source_date == date(2024, 4, 21)
    assert row.is_active is False
    assert row.sort_order == 5


# ---------------------------------------------------------------------------
# passage source_type widening + attribution columns
# ---------------------------------------------------------------------------


def test_passage_accepts_source_type_preset(session: Session) -> None:
    p = Passage(
        owner_id=uuid.uuid4(),
        text="copied preset text",
        text_hash=_hash("copied preset text"),
        source_type="preset",
        attribution_title="Ridván 2024 Message",
        attribution_author="The Universal House of Justice",
        attribution_copyright="Bahá'í International Community",
        attribution_source_url="https://www.bahai.org/x",
    )
    session.add(p)
    session.commit()

    row = session.exec(select(Passage).where(Passage.source_type == "preset")).one()
    assert row.attribution_copyright == "Bahá'í International Community"
    assert row.attribution_author == "The Universal House of Justice"


@pytest.mark.parametrize("source_type", ["paste", "pdf", "preset"])
def test_passage_allows_every_valid_source_type(session: Session, source_type: str) -> None:
    p = Passage(
        owner_id=uuid.uuid4(),
        text="x",
        text_hash=_hash("x"),
        source_type=source_type,
    )
    session.add(p)
    session.commit()  # should not raise


def test_passage_rejects_invalid_source_type(session: Session) -> None:
    """The CHECK constraint (mirrored in __table_args__) must reject a
    source_type outside the allow-list, on SQLite as in Postgres."""
    p = Passage(
        owner_id=uuid.uuid4(),
        text="x",
        text_hash=_hash("x"),
        source_type="video",
    )
    session.add(p)
    with pytest.raises(IntegrityError):
        session.commit()


def test_paste_passage_leaves_attribution_null(session: Session) -> None:
    """A normal paste passage carries no attribution — the new columns stay
    NULL (they're only populated by copy-on-select from a preset)."""
    p = Passage(
        owner_id=uuid.uuid4(),
        text="just pasted",
        text_hash=_hash("just pasted"),
        source_type="paste",
    )
    session.add(p)
    session.commit()

    row = session.exec(select(Passage)).one()
    assert row.attribution_title is None
    assert row.attribution_author is None
    assert row.attribution_copyright is None
    assert row.attribution_source_url is None
