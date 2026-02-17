from __future__ import annotations

from langchain_core.language_models import BaseChatModel
from langchain_core.messages import HumanMessage, SystemMessage
from pydantic import BaseModel, Field

from agentdesk.llm.provider import get_llm
from agentdesk.models.state import TicketState
from agentdesk.tracing.tracer import create_trace_entry

RESPONSE_SYSTEM_PROMPT = """\
You are a customer support response writer for an e-commerce company.

Write a professional, empathetic, and concise response to the customer.
Also write brief internal notes summarizing the ticket for the support team.

Context:
- Customer name: {customer_name}
- Customer tier: {tier}
- Urgency: {urgency}
- Category: {category}
- Original message: {message}
- Order details: {order_details}
- Resolution action: {resolution_action}
- Resolution details: {resolution_details}

Tone guidelines:
- Always be empathetic and professional
- For VIP customers: use personalized, premium tone
- For high/critical urgency: acknowledge frustration, prioritize reassurance
- Keep responses concise but thorough
- Include specific details (order IDs, dates, amounts) when relevant
"""


class ResponseOutput(BaseModel):
    customer_response: str = Field(description="The customer-facing response message")
    internal_notes: str = Field(description="Internal notes for the support team")


def response_node(state: TicketState, *, llm: BaseChatModel | None = None) -> dict:
    """Generate the customer-facing response and internal notes."""
    llm = llm or get_llm()
    customer = state["customer_history"] or {}
    order = state["order_details"] or {}

    prompt = RESPONSE_SYSTEM_PROMPT.format(
        customer_name=customer.get("name", "Customer"),
        tier=customer.get("tier", "standard"),
        urgency=state["urgency"],
        category=state["category"],
        message=state["customer_message"],
        order_details=order,
        resolution_action=state["resolution_action"],
        resolution_details=state["resolution_details"],
    )

    structured_llm = llm.with_structured_output(ResponseOutput)
    result = structured_llm.invoke([
        SystemMessage(content=prompt),
        HumanMessage(content="Write the response."),
    ])

    trace = create_trace_entry(
        agent="response",
        input_summary=f"action={state['resolution_action']}, tier={customer.get('tier')}",
        output_summary=f"response_length={len(result.customer_response)}",
    )

    return {
        "customer_response": result.customer_response,
        "internal_notes": result.internal_notes,
        "trace_log": [trace],
    }
