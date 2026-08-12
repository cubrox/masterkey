"""Passage model.

A piece of text the user is reading. Originates from paste (INGEST-1)
or PDF upload (INGEST-2 #14). The `text_hash` column is the
content-addressable key into `comprehension_question_cache` (per
ADR-001 in docs/TECHNICAL-ARCHITECTURE.md), so the SAME passage pasted
by two different users hits the same cached questions.

`source_type` is constrained to `'paste' | 'pdf' | 'preset'`.
`source_filename` is populated only for PDF uploads (kept for display,
never re-read from disk — the parsed text is the source of truth
post-ingestion).

`owner_id` references `auth.users(id)` in Supabase. The FK constraint
lives in the SQL migration (supabase/migrations/*.sql), not on the
SQLModel field — `auth.users` is in a different schema and isn't a
SQLModel-managed table.

PRESET-1 (#279): the `attribution_*` columns are populated only when a
passage was created by selecting a preset (`source_type='preset'`), so
the reading surface can render the required
`Copyright © Bahá'í International Community` + source/author. They are
NULL for paste/pdf passages.
"""

import uuid
from datetime import UTC, datetime

import sqlalchemy as sa
from sqlmodel import Field, SQLModel


class Passage(SQLModel, table=True):
    __tablename__ = "passage"
    # Mirror the migration's source_type CHECK so the test conftest's
    # `SQLModel.metadata.create_all` enforces it too — otherwise the tests
    # would accept a bogus source_type that Supabase-managed Postgres rejects.
    # Same precedent as ReadingEvent's lines_processed CHECK.
    __table_args__ = (
        sa.CheckConstraint(
            "source_type IN ('paste', 'pdf', 'preset')",
            name="passage_source_type_check",
        ),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    owner_id: uuid.UUID = Field(nullable=False)
    text: str
    text_hash: bytes
    source_type: str
    source_filename: str | None = Field(default=None)
    # PRESET-1 (#279): attribution carried from a preset onto the user-owned
    # passage created by copy-on-select. NULL for paste/pdf.
    attribution_title: str | None = Field(default=None)
    attribution_author: str | None = Field(default=None)
    attribution_copyright: str | None = Field(default=None)
    attribution_source_url: str | None = Field(default=None)
    # COMP-5 (#128): per-passage comprehension toggle. Default on; a reader
    # can disable questions for a passage where the auto-generated ones are
    # unhelpful (PRD Risk #2 mitigation for sacred/poetic text).
    comprehension_enabled: bool = Field(default=True, nullable=False)
    # INGEST-3 (#145): documents larger than MAX_TEXT_LEN are auto-split into
    # ordered parts that share a `document_id`, so a big PDF reads as a
    # navigable sequence instead of being truncated or rejected. A standalone
    # passage has document_id=None, part_index=0, part_count=1.
    document_id: uuid.UUID | None = Field(default=None, index=True)
    part_index: int = Field(default=0, nullable=False)
    part_count: int = Field(default=1, nullable=False)
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
