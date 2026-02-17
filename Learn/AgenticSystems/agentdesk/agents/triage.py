from __future__ import annotations

from typing import Literal

from langchain_core.language_models import BaseChatModel
from langchain_core.messages import HumanMessage, SystemMessage
from pydantic import BaseModel, Field

from agentdesk.llm.provider import get_llm
from agentdesk.models.state import TicketState
from agentdesk.tracing.tracer import create_trace_entry

TRIAGE_SYSTEM_PROMPT = """\
You are a customer support triage agent for an e-commerce company.

Classify the customer message into exactly one category and urgency level.
Extract any relevant entity IDs (order IDs, product IDs) from the message.

Categories:
- order_issue: Questions about order status, delivery, shipping
- return_request: Customer wants to return or exchange a product
- product_question: Questions about product features, availability, specs
- billing: Payment issues, charges, invoices
- complaint: General dissatisfaction, negative experience

Urgency levels:
- low: General inquiries, no time pressure
- medium: Needs attention but not urgent
- high: Customer is frustrated or issue is time-sensitive
- critical: Potential legal issue, VIP escalation, or service outage
"""


class TriageOutput(BaseModel):
    category: Literal[
        "order_issue", "return_request", "product_question", "billing", "complaint"
    ] = Field(description="The ticket category")
    urgency: Literal["low", "medium", "high", "critical"] = Field(
        description="The urgency level"
    )
    extracted_entities: dict = Field(
        default_factory=dict,
        description="Extracted entity IDs, e.g. {'order_id': 'ORD-001', 'product_id': 'P001'}",
    )


def triage_node(state: TicketState, *, llm: BaseChatModel | None = None) -> dict:
    """Classify and extract entities from the customer message."""
    llm = llm or get_llm()
    structured_llm = llm.with_structured_output(TriageOutput)

    result = structured_llm.invoke([
        SystemMessage(content=TRIAGE_SYSTEM_PROMPT),
        HumanMessage(content=state["customer_message"]),
    ])

    trace = create_trace_entry(
        agent="triage",
        input_summary=state["customer_message"][:100],
        output_summary=f"category={result.category}, urgency={result.urgency}",
        confidence=None,
    )

    return {
        "category": result.category,
        "urgency": result.urgency,
        "extracted_entities": result.extracted_entities,
        "trace_log": [trace],
    }
