"""Todo model.

This is the workshop's demo data model. Attendees should delete this and
the corresponding routes/templates, then build their own product.
"""

from datetime import UTC, datetime

from sqlmodel import Field, SQLModel


class Todo(SQLModel, table=True):
    """A single todo item."""

    id: int | None = Field(default=None, primary_key=True)
    title: str = Field(max_length=200)
    done: bool = Field(default=False)
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
