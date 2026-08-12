"""PresetPassage model.

The curated preset message library (PRESET-1 #279, epic #278) — e.g. recent
Universal House of Justice messages a reader can pick instead of pasting their
own text. Shared reference data, not per-user: readable by any authenticated
session (RLS SELECT policy), writable only by the service role (seeded via
migration/script in PRESET-2).

Selecting a preset creates a normal user-owned `Passage` with
`source_type='preset'` that copies this row's `text` and carries its
attribution (copy-on-select, PRESET-4), so the whole existing reading pipeline
is reused and the required attribution travels with the text.

`text_hash` is the same content-addressable key `Passage` uses into
`comprehension_question_cache` (ADR-001): every reader who opens the same
preset shares one set of generated comprehension questions.

Rights basis: bahai.org content is usable provided each message displays
`Copyright © Bahá'í International Community` and source/author attribution —
hence `copyright_holder` and `source_url` are NOT NULL, and `author` is
nullable only because not every message names an individual author.
"""

import uuid
from datetime import UTC, date, datetime

from sqlmodel import Field, SQLModel


class PresetPassage(SQLModel, table=True):
    __tablename__ = "preset_passage"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    title: str
    # Nullable: not every message names an individual author.
    author: str | None = Field(default=None)
    copyright_holder: str = Field(default="Bahá'í International Community", nullable=False)
    source_url: str
    source_date: date | None = Field(default=None)
    text: str
    text_hash: bytes
    # Soft on/off; the picker (PRESET-3) lists only active rows.
    is_active: bool = Field(default=True, nullable=False)
    sort_order: int = Field(default=0, nullable=False)
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
