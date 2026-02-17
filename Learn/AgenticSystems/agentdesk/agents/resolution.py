from __future__ import annotations

from typing import Literal

from langchain_core.language_models import BaseChatModel
from langchain_core.messages import HumanMessage, SystemMessage
from langgraph.graph import END, START, StateGraph
from langgraph.types import interrupt
from pydantic import BaseModel, Field

from agentdesk.llm.provider import get_llm
from agentdesk.models.state import TicketState
from agentdesk.store.store import MockStore
from agentdesk.tracing.tracer import create_trace_entry

DECIDE_SYSTEM_PROMPT = """\
You are a resolution agent for an e-commerce company.

Given the ticket context, decide the best resolution action.
Only choose actions from the allowed_actions list.

Ticket category: {category}
Customer message: {message}
Order details: {order_details}
Customer tier: {tier}
Allowed actions: {allowed_actions}
Applicable policies: {policies}

Choose the single best action and explain why.
If the action is a refund, specify the refund amount.
"""


class ResolutionDecision(BaseModel):
    action: str = Field(description="The resolution action to take")
    reason: str = Field(description="Why this action was chosen")
    refund_amount: float | None = Field(default=None, description="Refund amount if applicable")


def decide_node(state: TicketState, *, llm: BaseChatModel | None = None) -> dict:
    """Decide the best resolution action."""
    llm = llm or get_llm()
    order = state["order_details"] or {}
    customer = state["customer_history"] or {}

    prompt = DECIDE_SYSTEM_PROMPT.format(
        category=state["category"],
        message=state["customer_message"],
        order_details=order,
        tier=customer.get("tier", "standard"),
        allowed_actions=state["allowed_actions"],
        policies=state["applicable_policies"],
    )

    structured_llm = llm.with_structured_output(ResolutionDecision)
    result = structured_llm.invoke([
        SystemMessage(content=prompt),
        HumanMessage(content="Decide the resolution."),
    ])

    details = {"reason": result.reason}
    if result.refund_amount is not None:
        details["refund_amount"] = result.refund_amount

    trace = create_trace_entry(
        agent="resolution_decide",
        input_summary=f"category={state['category']}, allowed={state['allowed_actions']}",
        output_summary=f"action={result.action}, reason={result.reason}",
    )

    return {
        "resolution_action": result.action,
        "resolution_details": details,
        "trace_log": [trace],
    }


def threshold_check_node(state: TicketState, *, store: MockStore | None = None) -> dict:
    """Check if the resolution action is within auto-approval thresholds."""
    store = store or MockStore()
    policies = store.get_policies()
    customer = state["customer_history"] or {}
    tier = customer.get("tier", "standard")
    action = state["resolution_action"]

    requires_review = False
    reason = None

    if action == "refund":
        amount = state["resolution_details"].get("refund_amount", 0)
        limit = policies.get(f"{tier}_refund_limit", policies["auto_refund_limit"])
        if amount > limit:
            requires_review = True
            reason = f"Refund ${amount:.2f} exceeds {tier} auto-approval limit of ${limit:.2f}"

    elif action == "replacement":
        if tier not in policies.get("free_replacement_eligible_tiers", []):
            requires_review = True
            reason = f"Customer tier '{tier}' not eligible for free replacement"

    elif action == "escalate":
        requires_review = True
        reason = "Agent recommended manual escalation"

    trace = create_trace_entry(
        agent="resolution_threshold",
        input_summary=f"action={action}, tier={tier}",
        output_summary=f"requires_review={requires_review}, reason={reason}",
    )

    return {
        "requires_human_review": requires_review,
        "human_review_reason": reason,
        "trace_log": [trace],
    }


def execute_node(state: TicketState, *, store: MockStore | None = None) -> dict:
    """Execute the resolution action (refund, replacement, etc.)."""
    store = store or MockStore()
    action = state["resolution_action"]
    details = dict(state["resolution_details"])
    order = state["order_details"] or {}
    order_id = order.get("order_id", "")

    if action == "refund":
        result = store.process_refund(
            order_id,
            details.get("refund_amount", 0),
            details.get("reason", "Customer request"),
        )
        details.update(result)

    elif action == "replacement":
        result = store.create_replacement_order(order_id)
        details.update(result)

    elif action == "cancel_order":
        result = store.update_order_status(order_id, "cancelled")
        details.update(result)

    trace = create_trace_entry(
        agent="resolution_execute",
        input_summary=f"action={action}, order={order_id}",
        output_summary=f"executed={action}, details={details}",
    )

    return {
        "resolution_details": details,
        "status": "resolved",
        "trace_log": [trace],
    }


def escalate_node(state: TicketState) -> dict:
    """Pause for human review via LangGraph interrupt."""
    review_payload = {
        "ticket_id": state["ticket_id"],
        "customer_message": state["customer_message"],
        "proposed_action": state["resolution_action"],
        "resolution_details": state["resolution_details"],
        "reason": state["human_review_reason"],
    }

    human_decision = interrupt(review_payload)

    trace = create_trace_entry(
        agent="resolution_escalate",
        input_summary=f"reason={state['human_review_reason']}",
        output_summary=f"human_decision={human_decision}",
    )

    if human_decision.get("action") == "approve":
        return {
            "status": "resolved",
            "trace_log": [trace],
        }
    elif human_decision.get("action") == "modify":
        return {
            "customer_response": human_decision.get("modified_response", ""),
            "status": "resolved",
            "trace_log": [trace],
        }
    else:
        return {
            "status": "escalated",
            "trace_log": [trace],
        }


def _route_after_threshold(state: TicketState) -> str:
    if state["requires_human_review"]:
        return "escalate"
    return "execute"


def build_resolution_subgraph() -> StateGraph:
    """Build and return the resolution subgraph (uncompiled)."""
    builder = StateGraph(TicketState)

    builder.add_node("decide", decide_node)
    builder.add_node("threshold_check", threshold_check_node)
    builder.add_node("execute", execute_node)
    builder.add_node("escalate", escalate_node)

    builder.add_edge(START, "decide")
    builder.add_edge("decide", "threshold_check")
    builder.add_conditional_edges(
        "threshold_check",
        _route_after_threshold,
        {"execute": "execute", "escalate": "escalate"},
    )
    builder.add_edge("execute", END)
    builder.add_edge("escalate", END)

    return builder
