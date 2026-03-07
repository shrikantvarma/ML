import enum
import uuid
from datetime import datetime
from decimal import Decimal
from typing import Any

from sqlalchemy import DateTime, Enum, ForeignKey, Numeric, String, Text
from sqlalchemy.dialects.postgresql import JSON
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.models.base import TimestampMixin


class QuoteStatus(enum.Enum):
    draft = "draft"
    sent = "sent"
    accepted = "accepted"
    rejected = "rejected"
    expired = "expired"


class Quote(TimestampMixin, Base):
    __tablename__ = "quotes"

    business_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    customer_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("customers.id", ondelete="CASCADE"),
        nullable=False,
    )
    description: Mapped[str | None] = mapped_column(Text)
    line_items: Mapped[Any | None] = mapped_column(JSON)
    total_amount: Mapped[Decimal | None] = mapped_column(Numeric(12, 2))
    status: Mapped[QuoteStatus] = mapped_column(
        Enum(QuoteStatus, name="quote_status"),
        nullable=False,
        default=QuoteStatus.draft,
        index=True,
    )
    valid_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    # Relationships
    business: Mapped["Business"] = relationship(back_populates="quotes")  # noqa: F821
    customer: Mapped["Customer"] = relationship(back_populates="quotes")  # noqa: F821
    job: Mapped["Job | None"] = relationship(back_populates="quote")  # noqa: F821
