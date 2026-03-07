import uuid
from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict


class PaymentCreate(BaseModel):
    business_id: uuid.UUID
    customer_id: uuid.UUID
    invoice_id: uuid.UUID
    amount: Decimal
    method: str
    paid_at: datetime
    reference: str | None = None


class PaymentResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    business_id: uuid.UUID
    customer_id: uuid.UUID
    invoice_id: uuid.UUID
    amount: Decimal
    method: str
    paid_at: datetime
    reference: str | None = None
    created_at: datetime
