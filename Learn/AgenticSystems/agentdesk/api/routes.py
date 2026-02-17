from __future__ import annotations

import uuid

from fastapi import APIRouter, HTTPException
from langgraph.types import Command

from agentdesk.agents.supervisor import build_graph
from agentdesk.models.schemas import (
    HumanReviewRequest,
    HumanReviewResponse,
    TicketListResponse,
    TicketRequest,
    TicketResponse,
    TraceResponse,
)

router = APIRouter()

# In-memory ticket store and graph instance
_tickets: dict[str, dict] = {}
_graph = None


def get_graph():
    global _graph
    if _graph is None:
        _graph = build_graph()
    return _graph


def _initial_state(ticket_id: str, request: TicketRequest) -> dict:
    return {
        "ticket_id": ticket_id,
        "customer_id": request.customer_id,
        "customer_message": request.message,
        "category": "",
        "urgency": "",
        "extracted_entities": {},
        "order_details": None,
        "customer_history": None,
        "applicable_policies": [],
        "allowed_actions": [],
        "resolution_action": "",
        "resolution_details": {},
        "requires_human_review": False,
        "human_review_reason": None,
        "customer_response": "",
        "internal_notes": "",
        "trace_log": [],
        "status": "processing",
    }


@router.post("/tickets", response_model=TicketResponse)
def create_ticket(request: TicketRequest):
    ticket_id = f"T-{uuid.uuid4().hex[:8].upper()}"
    config = {"configurable": {"thread_id": ticket_id}}

    graph = get_graph()
    initial_state = _initial_state(ticket_id, request)

    result = graph.invoke(initial_state, config=config)

    _tickets[ticket_id] = {
        "config": config,
        "result": result,
    }

    return TicketResponse(
        ticket_id=ticket_id,
        status=result.get("status", "processing"),
        category=result.get("category"),
        urgency=result.get("urgency"),
        resolution_action=result.get("resolution_action"),
        customer_response=result.get("customer_response"),
        internal_notes=result.get("internal_notes"),
    )


@router.get("/tickets", response_model=TicketListResponse)
def list_tickets(status: str | None = None, category: str | None = None):
    tickets = []
    for tid, data in _tickets.items():
        result = data["result"]
        if status and result.get("status") != status:
            continue
        if category and result.get("category") != category:
            continue
        tickets.append(
            TicketResponse(
                ticket_id=tid,
                status=result.get("status", "unknown"),
                category=result.get("category"),
                urgency=result.get("urgency"),
                resolution_action=result.get("resolution_action"),
                customer_response=result.get("customer_response"),
                internal_notes=result.get("internal_notes"),
            )
        )
    return TicketListResponse(tickets=tickets)


@router.get("/tickets/{ticket_id}", response_model=TicketResponse)
def get_ticket(ticket_id: str):
    if ticket_id not in _tickets:
        raise HTTPException(status_code=404, detail="Ticket not found")

    result = _tickets[ticket_id]["result"]
    return TicketResponse(
        ticket_id=ticket_id,
        status=result.get("status", "unknown"),
        category=result.get("category"),
        urgency=result.get("urgency"),
        resolution_action=result.get("resolution_action"),
        customer_response=result.get("customer_response"),
        internal_notes=result.get("internal_notes"),
    )


@router.get("/tickets/{ticket_id}/trace", response_model=TraceResponse)
def get_ticket_trace(ticket_id: str):
    if ticket_id not in _tickets:
        raise HTTPException(status_code=404, detail="Ticket not found")

    result = _tickets[ticket_id]["result"]
    return TraceResponse(
        ticket_id=ticket_id,
        trace_log=result.get("trace_log", []),
    )


@router.post("/tickets/{ticket_id}/review", response_model=HumanReviewResponse)
def review_ticket(ticket_id: str, review: HumanReviewRequest):
    if ticket_id not in _tickets:
        raise HTTPException(status_code=404, detail="Ticket not found")

    ticket_data = _tickets[ticket_id]
    config = ticket_data["config"]

    graph = get_graph()

    resume_value = {"action": review.action}
    if review.modified_response:
        resume_value["modified_response"] = review.modified_response

    result = graph.invoke(Command(resume=resume_value), config=config)

    ticket_data["result"] = result

    return HumanReviewResponse(
        ticket_id=ticket_id,
        status=result.get("status", "unknown"),
    )
