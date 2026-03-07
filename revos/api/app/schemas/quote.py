import uuid
from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict


class QuoteCreate(BaseModel):
    business_id: uuid.UUID
    customer_id: uuid.UUID
    description: str
    line_items: list[dict]
    total_amount: Decimal
    valid_until: datetime | None = None


class QuoteUpdate(BaseModel):
    description: str | None = None
    line_items: list[dict] | None = None
    total_amount: Decimal | None = None
    status: str | None = None
    valid_until: datetime | None = None


class QuoteResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    business_id: uuid.UUID
    customer_id: uuid.UUID
    description: str
    line_items: list[dict]
    total_amount: Decimal
    status: str
    valid_until: datetime | None = None
    created_at: datetime
