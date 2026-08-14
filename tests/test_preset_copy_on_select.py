"""Tests for copy-on-select + attribution rendering (PRESET-4 #282).

POST /passages/from-preset/{id} creates a user-owned Passage from a curated
preset, copying its attribution, then opens the reading view where the
copyright/author must render.
"""

import hashlib
import uuid

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.models.passage import Passage
from app.models.preset_passage import PresetPassage
from tests.conftest import make_user, signed_in


def _add_preset(session: Session, *, text: str = "O Son of Spirit!", is_active: bool = True):
    preset = PresetPassage(
        title="The Hidden Words",
        author="Bahá'u'lláh",
        source_url="https://www.bahai.org/library/x",
        text=text,
        text_hash=hashlib.sha256(text.encode()).digest(),
        is_active=is_active,
    )
    session.add(preset)
    session.commit()
    session.refresh(preset)
    return preset


def test_from_preset_creates_owned_passage_with_attribution(
    client: TestClient, session: Session
) -> None:
    user = signed_in(session)
    preset = _add_preset(session)

    response = client.post(f"/passages/from-preset/{preset.id}", follow_redirects=False)
    assert response.status_code == 303

    passage = session.exec(select(Passage)).one()
    assert response.headers["location"] == f"/read/{passage.id}"
    assert passage.owner_id == user.id
    assert passage.source_type == "preset"
    assert passage.text == preset.text
    # All attribution copied from the preset (compliance guardrail).
    assert passage.attribution_title == "The Hidden Words"
    assert passage.attribution_author == "Bahá'u'lláh"
    assert passage.attribution_copyright == "Bahá'í International Community"
    assert passage.attribution_source_url == "https://www.bahai.org/library/x"


def test_reading_view_renders_attribution_for_preset_passage(
    client: TestClient, session: Session
) -> None:
    signed_in(session)
    preset = _add_preset(session)
    client.post(f"/passages/from-preset/{preset.id}", follow_redirects=False)
    passage = session.exec(select(Passage)).one()

    body = client.get(f"/read/{passage.id}").text

    assert "passage-attribution" in body
    assert "Copyright" in body and "International Community" in body
    assert "Bahá" in body  # author/copyright present
    assert "The Hidden Words" in body


def test_reading_view_has_no_attribution_for_paste_passage(
    client: TestClient, session: Session
) -> None:
    """Paste/pdf passages carry no attribution, so the block must not render."""
    user = signed_in(session)
    text = "just some pasted text"
    p = Passage(
        owner_id=user.id,
        text=text,
        text_hash=hashlib.sha256(text.encode()).digest(),
        source_type="paste",
    )
    session.add(p)
    session.commit()
    session.refresh(p)

    body = client.get(f"/read/{p.id}").text
    assert "passage-attribution" not in body


def test_unknown_preset_returns_404_no_passage(client: TestClient, session: Session) -> None:
    signed_in(session)
    response = client.post(f"/passages/from-preset/{uuid.uuid4()}", follow_redirects=False)
    assert response.status_code == 404
    assert session.exec(select(Passage)).all() == []


def test_inactive_preset_returns_404_no_passage(client: TestClient, session: Session) -> None:
    signed_in(session)
    preset = _add_preset(session, is_active=False)
    response = client.post(f"/passages/from-preset/{preset.id}", follow_redirects=False)
    assert response.status_code == 404
    assert session.exec(select(Passage)).all() == []


def test_two_users_same_preset_share_text_hash(client: TestClient, session: Session) -> None:
    """Both users' preset passages share one text_hash → one comprehension
    cache entry (ADR-001), so questions are generated once, not per user."""
    preset = _add_preset(session)

    signed_in(session)  # user A
    client.post(f"/passages/from-preset/{preset.id}", follow_redirects=False)

    signed_in(session, email="userb@example.com")  # user B
    client.post(f"/passages/from-preset/{preset.id}", follow_redirects=False)

    hashes = {p.text_hash for p in session.exec(select(Passage)).all()}
    assert len(hashes) == 1  # identical text_hash across both users' passages


def test_from_preset_requires_auth(client: TestClient, session: Session) -> None:
    preset = _add_preset(session)
    make_user(session)  # a user exists, but the request is unauthenticated
    response = client.post(f"/passages/from-preset/{preset.id}", follow_redirects=False)
    assert response.status_code in (302, 303)
    assert response.headers["location"] == "/"
    assert session.exec(select(Passage)).all() == []


# ---------------------------------------------------------------------------
# Review follow-ups (#282 review)
# ---------------------------------------------------------------------------


def test_split_preset_carries_attribution_on_later_parts(
    client: TestClient, session: Session
) -> None:
    """A preset longer than MAX_TEXT_LEN splits into linked parts. Every part —
    not just part 0 — must carry the attribution, so the reading surface shows
    the copyright on whichever page the reader is on."""
    from app.api.passages import MAX_TEXT_LEN

    long_text = ("Consider the words of justice and mercy. " * 5000)[: MAX_TEXT_LEN + 20_000]
    assert len(long_text) > MAX_TEXT_LEN  # guard: actually triggers a split
    preset = _add_preset(session, text=long_text)

    signed_in(session)
    client.post(f"/passages/from-preset/{preset.id}", follow_redirects=False)

    parts = session.exec(select(Passage).order_by(Passage.part_index)).all()  # type: ignore[arg-type]
    assert len(parts) > 1, "expected the long preset to split into multiple parts"
    # Every part carries the attribution, and they share one document_id.
    assert all(p.attribution_copyright == "Bahá'í International Community" for p in parts)
    assert all(p.attribution_author == "Bahá'u'lláh" for p in parts)
    later = next(p for p in parts if p.part_index >= 1)
    assert later.attribution_title == "The Hidden Words"


def test_source_link_only_rendered_for_https(client: TestClient, session: Session) -> None:
    """The Source link renders only for an https URL; a non-https scheme is
    dropped (defensive), but the copyright/author still render."""
    user = signed_in(session)

    def _preset_passage(url: str) -> Passage:
        # Text must NOT contain the url, else it appears in the body regardless
        # of the link — the assertions below are about the rendered link only.
        text = f"passage body for {url[:4]}"
        p = Passage(
            owner_id=user.id,
            text=text,
            text_hash=hashlib.sha256(text.encode()).digest(),
            source_type="preset",
            attribution_title="T",
            attribution_author="A",
            attribution_copyright="Bahá'í International Community",
            attribution_source_url=url,
        )
        session.add(p)
        session.commit()
        session.refresh(p)
        return p

    https_p = _preset_passage("https://www.bahai.org/x")
    http_p = _preset_passage("http://insecure.example.com/x")

    https_body = client.get(f"/read/{https_p.id}").text
    assert ">Source</a>" in https_body
    assert "https://www.bahai.org/x" in https_body

    http_body = client.get(f"/read/{http_p.id}").text
    assert ">Source</a>" not in http_body  # link dropped for non-https
    assert "insecure.example.com" not in http_body
    # ...but the copyright still renders — attribution is not gated on the link.
    assert "Copyright" in http_body and "International Community" in http_body
