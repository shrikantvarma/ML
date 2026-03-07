import enum
import uuid
from datetime import datetime
from decimal import Decimal

from sqlalchemy import DateTime, Enum, ForeignKey, Numeric, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.models.base import TimestampMixin


class PaymentMethod(enum.Enum):
    cash = "cash"
    card = "card"
    check = "check"
    bank_transfer = "bank_transfer"
    other = "other"


class Payment(TimestampMixin, Base):
    __tablename__ = "payments"

    business_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    customer_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("customers.id", ondelete="CASCADE"),
        nullable=False,
    )
    invoice_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("invoices.id", ondelete="CASCADE"),
        nullable=False,
    )
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    method: Mapped[PaymentMethod] = mapped_column(
        Enum(PaymentMethod, name="payment_method"),
        nullable=False,
    )
    paid_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    reference: Mapped[str | None] = mapped_column(String(255))

    # Relationships
    business: Mapped["Business"] = relationship()  # noqa: F821
    customer: Mapped["Customer"] = relationship(back_populates="payments")  # noqa: F821
    invoice: Mapped["Invoice"] = relationship(back_populates="payments")  # noqa: F821
