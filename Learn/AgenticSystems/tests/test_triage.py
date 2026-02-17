from unittest.mock import MagicMock

from agentdesk.agents.triage import triage_node


def _make_state(message: str) -> dict:
    return {
        "ticket_id": "T001",
        "customer_id": "C001",
        "customer_message": message,
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


def test_triage_classifies_order_issue():
    mock_llm = MagicMock()
    mock_structured = MagicMock()
    mock_llm.with_structured_output.return_value = mock_structured

    mock_structured.invoke.return_value = MagicMock(
        category="order_issue",
        urgency="low",
        extracted_entities={"order_id": "ORD-001"},
    )

    state = _make_state("Where is my order ORD-001?")
    result = triage_node(state, llm=mock_llm)

    assert result["category"] == "order_issue"
    assert result["urgency"] == "low"
    assert result["extracted_entities"]["order_id"] == "ORD-001"
    assert len(result["trace_log"]) == 1
    assert result["trace_log"][0]["agent"] == "triage"


def test_triage_classifies_return_request():
    mock_llm = MagicMock()
    mock_structured = MagicMock()
    mock_llm.with_structured_output.return_value = mock_structured

    mock_structured.invoke.return_value = MagicMock(
        category="return_request",
        urgency="medium",
        extracted_entities={"order_id": "ORD-003", "product_id": "P003"},
    )

    state = _make_state("I want to return the coffee maker from order ORD-003")
    result = triage_node(state, llm=mock_llm)

    assert result["category"] == "return_request"
    assert result["urgency"] == "medium"
