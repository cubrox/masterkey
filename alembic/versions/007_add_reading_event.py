"""add reading_event table

Revision ID: 007
Revises: 006
Create Date: 2026-05-14

Append-only event table for the "100k lines processed" PRD success
metric (Epic #7). One row per beacon dispatched on passage-close
(METRIC-2). The aggregate query (METRIC-3) groups by `occurred_at`
date — hence the single-column index on that column.

CASCADE on both FKs: a reading event without its user or its passage
is unattributable, so it goes away with them. Append-only — no
`updated_at` column, no UPDATE path expected.

UUID handling mirrors revisions 003 and 004: native on Postgres,
CHAR(36) on SQLite for the in-memory test database.
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "007"
down_revision: str | None = "006"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    bind = op.get_bind()
    is_pg = bind.dialect.name == "postgresql"
    uuid_type: sa.types.TypeEngine = sa.Uuid() if is_pg else sa.String(length=36)

    op.create_table(
        "reading_event",
        sa.Column(
            "id",
            uuid_type,
            primary_key=True,
            server_default=sa.text("gen_random_uuid()") if is_pg else None,
        ),
        sa.Column(
            "user_id",
            uuid_type,
            sa.ForeignKey("user.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "passage_id",
            uuid_type,
            sa.ForeignKey("passage.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("lines_processed", sa.Integer(), nullable=False),
        sa.Column(
            "occurred_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        # Append-only domain: a 0-line event is meaningless noise.
        # CHECK runs in both Postgres and SQLite.
        sa.CheckConstraint(
            "lines_processed >= 1",
            name="reading_event_lines_processed_positive",
        ),
    )

    # METRIC-3's aggregate query groups by date; this is the index that
    # makes that fast. Per the ticket: do NOT add (user_id, occurred_at)
    # until METRIC-3 surfaces a per-user query.
    op.create_index("ix_reading_event_occurred_at", "reading_event", ["occurred_at"])


def downgrade() -> None:
    op.drop_index("ix_reading_event_occurred_at", table_name="reading_event")
    op.drop_table("reading_event")
