from __future__ import annotations

from langchain_core.language_models import BaseChatModel
from langchain_core.messages import HumanMessage, SystemMessage
from pydantic import BaseModel, Field

from agentdesk.llm.provider import get_llm
from agentdesk.models.state import TicketState
from agentdesk.store.store import MockStore
from agentdesk.tracing.tracer import create_trace_entry

POLICY_SYSTEM_PROMPT = """\
You are a policy evaluation agent for an e-commerce company.

Given the ticket category, order details, and customer tier, determine which policies apply
and what actions the system is allowed to take.

Policy Rules:
{policies}

Customer tier: {tier}
Order total: ${order_total}
Order status: {order_status}
Category: {category}

Return the applicable policy names and the list of allowed actions.

Possible actions: refund, replacement, escalate, info_only, cancel_order, update_shipping
"""


class PolicyOutput(BaseModel):
    applicable_policies: list[str] = Field(description="List of policy rules that apply")
    allowed_actions: list[str] = Field(description="Actions the system is allowed to take")


def policy_node(state: TicketState, *, llm: BaseChatModel | None = None, store: MockStore | None = None) -> dict:
    """Evaluate policies and determine allowed actions."""
    llm = llm or get_llm()
    store = store or MockStore()

    policies = store.get_policies()
    order = state["order_details"] or {}
    customer = state["customer_history"] or {}

    prompt = POLICY_SYSTEM_PROMPT.format(
        policies=policies,
        tier=customer.get("tier", "standard"),
        order_total=order.get("total", 0),
        order_status=order.get("status", "unknown"),
        category=state["category"],
    )

    structured_llm = llm.with_structured_output(PolicyOutput)
    result = structured_llm.invoke([
        SystemMessage(content=prompt),
        HumanMessage(content=f"Evaluate policies for this {state['category']} ticket."),
    ])

    trace = create_trace_entry(
        agent="policy",
        input_summary=f"category={state['category']}, tier={customer.get('tier', 'unknown')}",
        output_summary=f"policies={result.applicable_policies}, actions={result.allowed_actions}",
    )

    return {
        "applicable_policies": result.applicable_policies,
        "allowed_actions": result.allowed_actions,
        "trace_log": [trace],
    }
