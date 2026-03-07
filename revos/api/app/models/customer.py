import uuid

from sqlalchemy import ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.models.base import TimestampMixin


class Customer(TimestampMixin, Base):
    __tablename__ = "customers"

    business_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    phone: Mapped[str | None] = mapped_column(String(30))
    email: Mapped[str | None] = mapped_column(String(255))
    address: Mapped[str | None] = mapped_column(String(500))
    notes: Mapped[str | None] = mapped_column(Text)

    # Relationships
    business: Mapped["Business"] = relationship(back_populates="customers")  # noqa: F821
    quotes: Mapped[list["Quote"]] = relationship(back_populates="customer")  # noqa: F821
    jobs: Mapped[list["Job"]] = relationship(back_populates="customer")  # noqa: F821
    invoices: Mapped[list["Invoice"]] = relationship(back_populates="customer")  # noqa: F821
    payments: Mapped[list["Payment"]] = relationship(back_populates="customer")  # noqa: F821
