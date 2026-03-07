import enum
import uuid
from typing import Any

from sqlalchemy import Enum, ForeignKey, String, Text
from sqlalchemy.dialects.postgresql import JSON
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.models.base import TimestampMixin


class Channel(enum.Enum):
    whatsapp = "whatsapp"
    sms = "sms"
    voice = "voice"
    web = "web"


class Direction(enum.Enum):
    inbound = "inbound"
    outbound = "outbound"


class Conversation(TimestampMixin, Base):
    __tablename__ = "conversations"

    business_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    customer_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("customers.id", ondelete="SET NULL"),
    )
    channel: Mapped[Channel] = mapped_column(
        Enum(Channel, name="channel_type"),
        nullable=False,
    )
    direction: Mapped[Direction] = mapped_column(
        Enum(Direction, name="direction_type"),
        nullable=False,
    )
    content: Mapped[str] = mapped_column(Text, nullable=False)
    metadata_: Mapped[Any | None] = mapped_column("metadata", JSON)

    # Relationships
    business: Mapped["Business"] = relationship()  # noqa: F821
    customer: Mapped["Customer | None"] = relationship()  # noqa: F821
