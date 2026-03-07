import uuid
from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict


class InvoiceCreate(BaseModel):
    business_id: uuid.UUID
    customer_id: uuid.UUID
    job_id: uuid.UUID | None = None
    amount: Decimal
    due_date: datetime


class InvoiceUpdate(BaseModel):
    status: str | None = None
    due_date: datetime | None = None
    sent_at: datetime | None = None
    paid_at: datetime | None = None


class InvoiceResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    business_id: uuid.UUID
    customer_id: uuid.UUID
    job_id: uuid.UUID | None = None
    amount: Decimal
    due_date: datetime
    status: str
    sent_at: datetime | None = None
    paid_at: datetime | None = None
    created_at: datetime
