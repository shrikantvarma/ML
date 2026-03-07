import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict


class JobCreate(BaseModel):
    business_id: uuid.UUID
    customer_id: uuid.UUID
    quote_id: uuid.UUID | None = None
    technician_id: uuid.UUID | None = None
    description: str
    scheduled_at: datetime
    address: str


class JobUpdate(BaseModel):
    status: str | None = None
    technician_id: uuid.UUID | None = None
    completed_at: datetime | None = None
    notes: str | None = None


class JobResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    business_id: uuid.UUID
    customer_id: uuid.UUID
    quote_id: uuid.UUID | None = None
    technician_id: uuid.UUID | None = None
    description: str
    scheduled_at: datetime
    address: str
    status: str
    completed_at: datetime | None = None
    notes: str | None = None
    created_at: datetime
