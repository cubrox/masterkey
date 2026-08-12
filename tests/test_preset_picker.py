"""Tests for the preset picker on GET /passages/new (PRESET-3 #281).

Covers the Definition of Done:
  - lists active presets with title + attribution
  - excludes inactive presets
  - orders by sort_order
  - empty-corpus state renders cleanly (no broken section)
"""

import hashlib

from fastapi.testclient import TestClient
from sqlmodel import Session

from app.models.preset_passage import PresetPassage
from tests.conftest import signed_in


def _add_preset(
    session: Session,
    *,
    title: str,
    author: str | None = None,
    is_active: bool = True,
    sort_order: int = 0,
) -> PresetPassage:
    text = f"body of {title}"
    preset = PresetPassage(
        title=title,
        author=author,
        source_url="https://www.bahai.org/x",
        text=text,
        text_hash=hashlib.sha256(text.encode()).digest(),
        is_active=is_active,
        sort_order=sort_order,
    )
    session.add(preset)
    session.commit()
    session.refresh(preset)
    return preset


def test_empty_corpus_renders_clean_placeholder(client: TestClient, session: Session) -> None:
    """No presets → the section still renders with a readable placeholder,
    and the paste/PDF forms remain."""
    signed_in(session)
    body = client.get("/passages/new").text

    assert "Start from a message" in body
    assert "No preset messages are available yet" in body
    # The primary input methods are untouched.
    assert 'action="/passages"' in body
    assert 'action="/passages/pdf"' in body


def test_active_preset_listed_with_title_and_attribution(
    client: TestClient, session: Session
) -> None:
    signed_in(session)
    _add_preset(session, title="Ridván 2024 Message", author="The Universal House of Justice")

    body = client.get("/passages/new").text

    assert "Ridván 2024 Message" in body
    assert "The Universal House of Justice" in body  # author attribution
    # Copyright attribution renders (the apostrophe in "Bahá'í" is HTML-escaped
    # to &#39; by Jinja auto-escape, so match the unambiguous tail).
    assert "International Community" in body
    assert "No preset messages are available yet" not in body


def test_select_control_targets_the_preset4_route(client: TestClient, session: Session) -> None:
    """Each row's control points at PRESET-4's create route (read-only here)."""
    signed_in(session)
    preset = _add_preset(session, title="A Message")

    body = client.get("/passages/new").text

    assert f'action="/passages/from-preset/{preset.id}"' in body
    # Accessible, distinct label per row (a11y gate).
    assert 'aria-label="Read A Message"' in body


def test_inactive_presets_are_excluded(client: TestClient, session: Session) -> None:
    signed_in(session)
    _add_preset(session, title="Visible One", is_active=True)
    _add_preset(session, title="Hidden One", is_active=False)

    body = client.get("/passages/new").text

    assert "Visible One" in body
    assert "Hidden One" not in body


def test_presets_ordered_by_sort_order(client: TestClient, session: Session) -> None:
    signed_in(session)
    _add_preset(session, title="Third", sort_order=30)
    _add_preset(session, title="First", sort_order=10)
    _add_preset(session, title="Second", sort_order=20)

    body = client.get("/passages/new").text

    assert body.index("First") < body.index("Second") < body.index("Third")


def test_picker_requires_auth(client: TestClient) -> None:
    """Unauthenticated GET redirects to the landing page, like the rest of
    /passages/new (no preset data leaks to anon)."""
    response = client.get("/passages/new", follow_redirects=False)
    assert response.status_code in (302, 303)
    assert response.headers["location"] == "/"
