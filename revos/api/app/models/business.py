from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.models.base import TimestampMixin


class Business(TimestampMixin, Base):
    __tablename__ = "businesses"

    name: Mapped[str] = mapped_column(String(255), nullable=False)
    phone: Mapped[str | None] = mapped_column(String(30))
    email: Mapped[str | None] = mapped_column(String(255))
    address: Mapped[str | None] = mapped_column(String(500))
    timezone: Mapped[str] = mapped_column(
        String(50), nullable=False, default="America/New_York"
    )

    # Relationships
    customers: Mapped[list["Customer"]] = relationship(back_populates="business")  # noqa: F821
    technicians: Mapped[list["Technician"]] = relationship(back_populates="business")  # noqa: F821
    quotes: Mapped[list["Quote"]] = relationship(back_populates="business")  # noqa: F821
    jobs: Mapped[list["Job"]] = relationship(back_populates="business")  # noqa: F821
    invoices: Mapped[list["Invoice"]] = relationship(back_populates="business")  # noqa: F821
