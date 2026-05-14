"""Migration cycle test for the reading_event table (revision 007).

Mirrors the existing migration tests, with an additional CASCADE-
delete test that runs against the Alembic-applied schema (the default
test engine in conftest.py does not enable SQLite FK enforcement, so
CASCADE behavior can only be observed in an engine that explicitly
turns it on).
"""

import uuid
from datetime import UTC, datetime
from pathlib import Path

import pytest
from alembic.config import Config
from sqlalchemy import Engine, create_engine, event, inspect, text

from alembic import command

REPO_ROOT = Path(__file__).resolve().parent.parent


def _enable_sqlite_foreign_keys(engine: Engine) -> None:
    """Force SQLite to enforce ON DELETE CASCADE.

    Postgres enforces FKs unconditionally; SQLite only does so when the
    `foreign_keys` PRAGMA is on, and the pragma is per-connection. The
    event listener ensures every new connection from this engine pool
    gets the pragma set before any DML runs.
    """

    @event.listens_for(engine, "connect")
    def _set_pragma(dbapi_conn, _) -> None:  # noqa: ANN001 - SQLAlchemy callback signature
        cursor = dbapi_conn.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()


@pytest.fixture
def alembic_cfg(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Config:
    db_path = tmp_path / "reading_event_migration_test.db"
    db_url = f"sqlite:///{db_path}"

    monkeypatch.setenv("DATABASE_URL", db_url)
    from app.config import get_settings

    get_settings.cache_clear()

    cfg = Config(str(REPO_ROOT / "alembic.ini"))
    cfg.set_main_option("script_location", str(REPO_ROOT / "alembic"))
    cfg.set_main_option("sqlalchemy.url", db_url)
    return cfg


def test_upgrade_creates_reading_event_table(alembic_cfg: Config) -> None:
    command.upgrade(alembic_cfg, "007")

    db_url = alembic_cfg.get_main_option("sqlalchemy.url")
    assert db_url is not None
    engine = create_engine(db_url)
    inspector = inspect(engine)

    assert "reading_event" in inspector.get_table_names()

    cols = {c["name"] for c in inspector.get_columns("reading_event")}
    assert cols == {"id", "user_id", "passage_id", "lines_processed", "occurred_at"}

    pk = inspector.get_pk_constraint("reading_event")
    assert pk["constrained_columns"] == ["id"]

    # Both FKs land with the right referent.
    fks = inspector.get_foreign_keys("reading_event")
    fk_targets = {(fk["referred_table"], tuple(fk["referred_columns"])) for fk in fks}
    assert ("user", ("id",)) in fk_targets
    assert ("passage", ("id",)) in fk_targets

    # The dashboard's date-range query in METRIC-3 leans on this index.
    indexes = {ix["name"] for ix in inspector.get_indexes("reading_event")}
    assert "ix_reading_event_occurred_at" in indexes

    # Composite (user_id, occurred_at) MUST NOT exist yet — per ticket
    # guardrail, premature index. Adding it later in METRIC-3 is fine.
    assert not any(
        set(ix["column_names"]) == {"user_id", "occurred_at"}
        for ix in inspector.get_indexes("reading_event")
    )


def test_upgrade_downgrade_upgrade_cycle(alembic_cfg: Config) -> None:
    command.upgrade(alembic_cfg, "007")
    command.downgrade(alembic_cfg, "006")

    db_url = alembic_cfg.get_main_option("sqlalchemy.url")
    assert db_url is not None
    engine = create_engine(db_url)
    inspector = inspect(engine)

    table_names = inspector.get_table_names()
    assert "reading_event" not in table_names
    # Earlier migrations untouched.
    assert "user" in table_names
    assert "passage" in table_names
    assert "rate_bucket" in table_names

    command.upgrade(alembic_cfg, "007")
    inspector = inspect(engine)
    assert "reading_event" in inspector.get_table_names()


def test_delete_user_cascades_to_reading_events(alembic_cfg: Config) -> None:
    """Deleting a User must take their ReadingEvent rows with them —
    orphan events have no meaning. Verified against the
    Alembic-applied schema with SQLite FK enforcement on."""
    command.upgrade(alembic_cfg, "007")

    db_url = alembic_cfg.get_main_option("sqlalchemy.url")
    assert db_url is not None
    engine = create_engine(db_url)
    _enable_sqlite_foreign_keys(engine)

    user_id = str(uuid.uuid4())
    passage_id = str(uuid.uuid4())
    event_id = str(uuid.uuid4())

    with engine.begin() as conn:
        conn.execute(
            text("INSERT INTO user (id, email, created_at) VALUES (:id, :email, :ts)"),
            {"id": user_id, "email": "drop@example.com", "ts": datetime.now(UTC)},
        )
        conn.execute(
            text(
                "INSERT INTO passage (id, user_id, text, text_hash, source_type) "
                "VALUES (:id, :user_id, :text, :text_hash, :source_type)"
            ),
            {
                "id": passage_id,
                "user_id": user_id,
                "text": "lorem",
                "text_hash": b"\x00" * 32,
                "source_type": "paste",
            },
        )
        conn.execute(
            text(
                "INSERT INTO reading_event (id, user_id, passage_id, lines_processed) "
                "VALUES (:id, :user_id, :passage_id, :lp)"
            ),
            {"id": event_id, "user_id": user_id, "passage_id": passage_id, "lp": 5},
        )

    with engine.begin() as conn:
        conn.execute(text("DELETE FROM user WHERE id = :id"), {"id": user_id})

    with engine.connect() as conn:
        remaining = conn.execute(
            text("SELECT COUNT(*) FROM reading_event WHERE id = :id"),
            {"id": event_id},
        ).scalar()
    assert remaining == 0


def test_delete_passage_cascades_to_reading_events(alembic_cfg: Config) -> None:
    """Same CASCADE invariant for the passage parent."""
    command.upgrade(alembic_cfg, "007")

    db_url = alembic_cfg.get_main_option("sqlalchemy.url")
    assert db_url is not None
    engine = create_engine(db_url)
    _enable_sqlite_foreign_keys(engine)

    user_id = str(uuid.uuid4())
    passage_id = str(uuid.uuid4())
    event_id = str(uuid.uuid4())

    with engine.begin() as conn:
        conn.execute(
            text("INSERT INTO user (id, email, created_at) VALUES (:id, :email, :ts)"),
            {"id": user_id, "email": "drop-passage@example.com", "ts": datetime.now(UTC)},
        )
        conn.execute(
            text(
                "INSERT INTO passage (id, user_id, text, text_hash, source_type) "
                "VALUES (:id, :user_id, :text, :text_hash, :source_type)"
            ),
            {
                "id": passage_id,
                "user_id": user_id,
                "text": "lorem",
                "text_hash": b"\x00" * 32,
                "source_type": "paste",
            },
        )
        conn.execute(
            text(
                "INSERT INTO reading_event (id, user_id, passage_id, lines_processed) "
                "VALUES (:id, :user_id, :passage_id, :lp)"
            ),
            {"id": event_id, "user_id": user_id, "passage_id": passage_id, "lp": 5},
        )

    with engine.begin() as conn:
        conn.execute(text("DELETE FROM passage WHERE id = :id"), {"id": passage_id})

    with engine.connect() as conn:
        remaining = conn.execute(
            text("SELECT COUNT(*) FROM reading_event WHERE id = :id"),
            {"id": event_id},
        ).scalar()
    assert remaining == 0
