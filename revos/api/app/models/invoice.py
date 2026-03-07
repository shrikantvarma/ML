import enum
import uuid
from datetime import datetime
from decimal import Decimal

from sqlalchemy import DateTime, Enum, ForeignKey, Numeric
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.models.base import TimestampMixin


class InvoiceStatus(enum.Enum):
    draft = "draft"
    sent = "sent"
    overdue = "overdue"
    paid = "paid"
    cancelled = "cancelled"


class Invoice(TimestampMixin, Base):
    __tablename__ = "invoices"

    business_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    customer_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("customers.id", ondelete="CASCADE"),
        nullable=False,
    )
    job_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("jobs.id", ondelete="SET NULL"),
    )
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    status: Mapped[InvoiceStatus] = mapped_column(
        Enum(InvoiceStatus, name="invoice_status"),
        nullable=False,
        default=InvoiceStatus.draft,
        index=True,
    )
    due_date: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    paid_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    # Relationships
    business: Mapped["Business"] = relationship(back_populates="invoices")  # noqa: F821
    customer: Mapped["Customer"] = relationship(back_populates="invoices")  # noqa: F821
    job: Mapped["Job | None"] = relationship(back_populates="invoice")  # noqa: F821
    payments: Mapped[list["Payment"]] = relationship(back_populates="invoice")  # noqa: F821
