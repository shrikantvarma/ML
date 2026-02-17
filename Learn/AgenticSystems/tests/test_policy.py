from unittest.mock import MagicMock

from agentdesk.agents.policy import policy_node


def _make_state(category: str, tier: str, order_total: float) -> dict:
    return {
        "ticket_id": "T001",
        "customer_id": "C001",
        "customer_message": "test",
        "category": category,
        "urgency": "medium",
        "extracted_entities": {},
        "order_details": {"order_id": "ORD-001", "total": order_total, "status": "delivered",
                          "order_date": "2026-02-01", "items": []},
        "customer_history": {"tier": tier, "total_orders": 5},
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


def test_policy_return_request_standard_tier():
    mock_llm = MagicMock()
    mock_structured = MagicMock()
    mock_llm.with_structured_output.return_value = mock_structured

    mock_structured.invoke.return_value = MagicMock(
        applicable_policies=["30-day return window", "Auto-refund up to $50"],
        allowed_actions=["refund", "replacement"],
    )

    state = _make_state("return_request", "standard", 45.00)
    result = policy_node(state, llm=mock_llm)

    assert len(result["applicable_policies"]) > 0
    assert len(result["allowed_actions"]) > 0
    assert len(result["trace_log"]) == 1
    assert result["trace_log"][0]["agent"] == "policy"


def test_policy_product_question():
    mock_llm = MagicMock()
    mock_structured = MagicMock()
    mock_llm.with_structured_output.return_value = mock_structured

    mock_structured.invoke.return_value = MagicMock(
        applicable_policies=["Auto-resolve product questions"],
        allowed_actions=["info_only"],
    )

    state = _make_state("product_question", "standard", 0)
    result = policy_node(state, llm=mock_llm)

    assert "info_only" in result["allowed_actions"]
