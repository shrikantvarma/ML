from __future__ import annotations

from typing import Literal

from pydantic import BaseModel


class TicketRequest(BaseModel):
    customer_id: str
    message: str


class TicketResponse(BaseModel):
    ticket_id: str
    status: str
    category: str | None = None
    urgency: str | None = None
    resolution_action: str | None = None
    customer_response: str | None = None
    internal_notes: str | None = None


class TicketListResponse(BaseModel):
    tickets: list[TicketResponse]


class TraceResponse(BaseModel):
    ticket_id: str
    trace_log: list[dict]


class HumanReviewRequest(BaseModel):
    action: Literal["approve", "reject", "modify"]
    modified_response: str | None = None


class HumanReviewResponse(BaseModel):
    ticket_id: str
    status: str
