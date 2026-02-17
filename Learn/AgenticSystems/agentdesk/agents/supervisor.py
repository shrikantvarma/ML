from __future__ import annotations

from typing import Literal

from langchain_core.language_models import BaseChatModel
from langchain_core.messages import HumanMessage, SystemMessage
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.graph import END, START, StateGraph
from langgraph.types import Command
from pydantic import BaseModel, Field

from agentdesk.agents.order_lookup import order_lookup_node
from agentdesk.agents.policy import policy_node
from agentdesk.agents.resolution import build_resolution_subgraph
from agentdesk.agents.response import response_node
from agentdesk.agents.triage import triage_node
from agentdesk.llm.provider import get_llm
from agentdesk.models.state import TicketState
from agentdesk.tracing.tracer import create_trace_entry

SUPERVISOR_SYSTEM_PROMPT = """\
You are a supervisor agent orchestrating a customer support workflow.

Based on the current ticket state, decide which agent should handle the ticket next.

Available agents:
- triage: Classify the ticket (use when category is empty)
- order_lookup: Look up order details (use when order info is needed for the category)
- policy: Evaluate policies (use after order lookup for action-required categories)
- resolution: Decide and execute resolution (use after policy evaluation)
- response: Generate customer response (use when resolution is complete or for simple info requests)
- done: Ticket is fully handled, end the workflow

Current state:
- Category: {category}
- Urgency: {urgency}
- Has order details: {has_order}
- Has policies evaluated: {has_policies}
- Resolution action: {resolution_action}
- Has customer response: {has_response}
- Status: {status}

Rules:
1. Always start with triage if category is empty
2. For product_question: triage → response (skip order/policy/resolution)
3. For order_issue, return_request, billing: triage → order_lookup → policy → resolution → response
4. For complaint: triage → order_lookup → resolution (escalate) → response
5. After response is generated, choose done
6. If status is "resolved" or "escalated" and response exists, choose done
"""


class SupervisorDecision(BaseModel):
    next_agent: Literal[
        "triage", "order_lookup", "policy", "resolution", "response", "done"
    ] = Field(description="The next agent to invoke")
    reasoning: str = Field(description="Brief reasoning for the routing decision")


def supervisor_node(state: TicketState, *, llm: BaseChatModel | None = None) -> dict:
    """Decide which agent to invoke next."""
    llm = llm or get_llm()

    prompt = SUPERVISOR_SYSTEM_PROMPT.format(
        category=state["category"] or "(not yet classified)",
        urgency=state["urgency"] or "(not yet classified)",
        has_order=state["order_details"] is not None,
        has_policies=len(state["applicable_policies"]) > 0,
        resolution_action=state["resolution_action"] or "(none)",
        has_response=bool(state["customer_response"]),
        status=state["status"],
    )

    structured_llm = llm.with_structured_output(SupervisorDecision)
    decision = structured_llm.invoke([
        SystemMessage(content=prompt),
        HumanMessage(content=f"Customer message: {state['customer_message']}"),
    ])

    trace = create_trace_entry(
        agent="supervisor",
        input_summary=f"category={state['category']}, status={state['status']}",
        output_summary=f"next={decision.next_agent}, reason={decision.reasoning}",
    )

    return {
        "trace_log": [trace],
        "next_agent": decision.next_agent,
    }


def _route_from_supervisor(state: dict) -> str:
    next_agent = state.get("next_agent", "done")
    if next_agent == "done":
        return END
    return next_agent


def build_graph(checkpointer=None):
    """Build and compile the full AgentDesk supervisor graph."""

    # We need next_agent in the state for routing — extend TicketState
    class GraphState(TicketState, total=False):
        next_agent: str

    resolution_subgraph = build_resolution_subgraph().compile()

    builder = StateGraph(GraphState)

    # Add nodes
    builder.add_node("supervisor", supervisor_node)
    builder.add_node("triage", triage_node)
    builder.add_node("order_lookup", order_lookup_node)
    builder.add_node("policy", policy_node)
    builder.add_node("resolution", resolution_subgraph)
    builder.add_node("response", response_node)

    # Start → Supervisor
    builder.add_edge(START, "supervisor")

    # Supervisor routes to agents
    builder.add_conditional_edges(
        "supervisor",
        _route_from_supervisor,
        {
            "triage": "triage",
            "order_lookup": "order_lookup",
            "policy": "policy",
            "resolution": "resolution",
            "response": "response",
            END: END,
        },
    )

    # All agents route back to supervisor
    builder.add_edge("triage", "supervisor")
    builder.add_edge("order_lookup", "supervisor")
    builder.add_edge("policy", "supervisor")
    builder.add_edge("resolution", "supervisor")
    builder.add_edge("response", "supervisor")

    if checkpointer is None:
        checkpointer = InMemorySaver()

    return builder.compile(checkpointer=checkpointer)
