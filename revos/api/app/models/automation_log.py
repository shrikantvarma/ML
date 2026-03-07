import enum
import uuid
from typing import Any

from sqlalchemy import Enum, ForeignKey, String
from sqlalchemy.dialects.postgresql import JSON
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.models.base import TimestampMixin


class AutomationStatus(enum.Enum):
    success = "success"
    failed = "failed"


class AutomationLog(TimestampMixin, Base):
    __tablename__ = "automation_logs"

    business_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    action_type: Mapped[str] = mapped_column(String(100), nullable=False)
    target_type: Mapped[str] = mapped_column(String(100), nullable=False)
    target_id: Mapped[uuid.UUID] = mapped_column(nullable=False)
    details: Mapped[Any | None] = mapped_column(JSON)
    status: Mapped[AutomationStatus] = mapped_column(
        Enum(AutomationStatus, name="automation_status"),
        nullable=False,
        index=True,
    )

    # Relationships
    business: Mapped["Business"] = relationship()  # noqa: F821
