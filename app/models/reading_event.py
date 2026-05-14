"""ReadingEvent model.

Append-only record of "a user finished reading some lines of a
passage". METRIC-2 (#22) writes one row per beacon dispatched on
passage-close. METRIC-3 (#23) aggregates them for the "100,000 lines
processed in three months" PRD success metric.

Design choices:
  - Append-only: no `updated_at` column, no UPDATE path anywhere.
    Reading is observed, not edited.
  - `lines_processed` is `INT NOT NULL, CHECK >= 1` — every event
    must claim at least one line. Zero would just be noise.
  - `occurred_at` is server-defaulted to `now()` so the writer in
    METRIC-2 can rely on the database's clock (consistent across
    Cloud Run instances).
  - CASCADE on both FKs: deleting a user or a passage takes their
    reading events too — orphan rows have no meaning.

Indexes:
  - `ix_reading_event_occurred_at` for the date-range aggregate in
    METRIC-3. No composite (user_id, occurred_at) index yet — the
    aggregate is cross-user, and adding indexes ahead of an
    observed query is premature.
"""

import uuid
from datetime import UTC, datetime

import sqlalchemy as sa
from sqlmodel import Field, SQLModel


class ReadingEvent(SQLModel, table=True):
    __tablename__ = "reading_event"
    # Mirror the migration's CHECK constraint here too so
    # `SQLModel.metadata.create_all` (used by the test conftest) also
    # enforces the >=1 invariant. Without this, the tests would see a
    # 0-line row succeed even though Alembic-managed Postgres rejects it.
    __table_args__ = (
        sa.CheckConstraint(
            "lines_processed >= 1",
            name="reading_event_lines_processed_positive",
        ),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    user_id: uuid.UUID = Field(foreign_key="user.id", nullable=False)
    passage_id: uuid.UUID = Field(foreign_key="passage.id", nullable=False)
    lines_processed: int = Field(nullable=False)
    # Python-side default mirrors the migration's `server_default=now()`.
    # Either layer alone would do the job; both means a stray
    # `ReadingEvent(...)` without `occurred_at` works whether or not the
    # writer relies on the DB's clock.
    occurred_at: datetime = Field(default_factory=lambda: datetime.now(UTC), nullable=False)
