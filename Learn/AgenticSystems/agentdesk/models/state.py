from __future__ import annotations

import operator
from typing import Annotated, TypedDict


class TicketState(TypedDict):
    """Shared state flowing through the AgentDesk supervisor graph."""

    # Input
    ticket_id: str
    customer_id: str
    customer_message: str

    # Triage output
    category: str
    urgency: str
    extracted_entities: dict

    # Order Lookup output
    order_details: dict | None
    customer_history: dict | None

    # Policy output
    applicable_policies: list[str]
    allowed_actions: list[str]

    # Resolution output
    resolution_action: str
    resolution_details: dict
    requires_human_review: bool
    human_review_reason: str | None

    # Response output
    customer_response: str
    internal_notes: str

    # Tracing — append-only via Annotated reducer
    trace_log: Annotated[list[dict], operator.add]

    # Status
    status: str
