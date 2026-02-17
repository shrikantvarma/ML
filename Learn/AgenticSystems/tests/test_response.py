from unittest.mock import MagicMock

from agentdesk.agents.response import response_node


def _make_state(tier: str = "standard", urgency: str = "low") -> dict:
    return {
        "ticket_id": "T001",
        "customer_id": "C001",
        "customer_message": "Where is my order ORD-001?",
        "category": "order_issue",
        "urgency": urgency,
        "extracted_entities": {"order_id": "ORD-001"},
        "order_details": {"order_id": "ORD-001", "status": "shipped", "total": 79.99},
        "customer_history": {"tier": tier, "name": "Alice", "total_orders": 5},
        "applicable_policies": [],
        "allowed_actions": ["info_only"],
        "resolution_action": "info_only",
        "resolution_details": {"reason": "Order is in transit"},
        "requires_human_review": False,
        "human_review_reason": None,
        "customer_response": "",
        "internal_notes": "",
        "trace_log": [],
        "status": "resolved",
    }


def test_response_generates_customer_message():
    mock_llm = MagicMock()
    mock_structured = MagicMock()
    mock_llm.with_structured_output.return_value = mock_structured
    mock_structured.invoke.return_value = MagicMock(
        customer_response="Your order ORD-001 is currently shipped and on its way.",
        internal_notes="Customer inquired about order status. No action needed.",
    )

    state = _make_state()
    result = response_node(state, llm=mock_llm)

    assert result["customer_response"] != ""
    assert result["internal_notes"] != ""
    assert len(result["trace_log"]) == 1
    assert result["trace_log"][0]["agent"] == "response"
