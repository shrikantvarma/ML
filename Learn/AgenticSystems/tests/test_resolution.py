from unittest.mock import MagicMock

from agentdesk.agents.resolution import decide_node, threshold_check_node, execute_node
from agentdesk.store.store import MockStore


def _make_state(
    category: str = "return_request",
    tier: str = "standard",
    order_total: float = 40.00,
    allowed_actions: list | None = None,
) -> dict:
    return {
        "ticket_id": "T001",
        "customer_id": "C001",
        "customer_message": "I want a refund",
        "category": category,
        "urgency": "medium",
        "extracted_entities": {"order_id": "ORD-001"},
        "order_details": {"order_id": "ORD-001", "total": order_total, "status": "delivered",
                          "items": [{"product_id": "P001", "name": "Headphones", "price": order_total}]},
        "customer_history": {"tier": tier, "total_orders": 3},
        "applicable_policies": ["30-day return window"],
        "allowed_actions": allowed_actions or ["refund", "replacement"],
        "resolution_action": "",
        "resolution_details": {},
        "requires_human_review": False,
        "human_review_reason": None,
        "customer_response": "",
        "internal_notes": "",
        "trace_log": [],
        "status": "processing",
    }


def test_decide_node_picks_refund():
    mock_llm = MagicMock()
    mock_structured = MagicMock()
    mock_llm.with_structured_output.return_value = mock_structured
    mock_structured.invoke.return_value = MagicMock(
        action="refund",
        reason="Customer wants refund within return window",
        refund_amount=40.00,
    )

    state = _make_state()
    result = decide_node(state, llm=mock_llm)
    assert result["resolution_action"] == "refund"
    assert result["resolution_details"]["refund_amount"] == 40.00


def test_threshold_check_auto_approves_small_refund():
    store = MockStore()
    state = _make_state(order_total=30.00)
    state["resolution_action"] = "refund"
    state["resolution_details"] = {"refund_amount": 30.00}
    state["customer_history"] = {"tier": "standard"}

    result = threshold_check_node(state, store=store)
    assert result["requires_human_review"] is False


def test_threshold_check_escalates_large_refund():
    store = MockStore()
    state = _make_state(order_total=150.00)
    state["resolution_action"] = "refund"
    state["resolution_details"] = {"refund_amount": 150.00}
    state["customer_history"] = {"tier": "standard"}

    result = threshold_check_node(state, store=store)
    assert result["requires_human_review"] is True
    assert result["human_review_reason"] is not None


def test_threshold_check_vip_gets_higher_limit():
    store = MockStore()
    state = _make_state(order_total=150.00, tier="vip")
    state["resolution_action"] = "refund"
    state["resolution_details"] = {"refund_amount": 150.00}
    state["customer_history"] = {"tier": "vip"}

    result = threshold_check_node(state, store=store)
    assert result["requires_human_review"] is False


def test_execute_node_processes_refund():
    store = MockStore()
    state = _make_state(order_total=30.00)
    state["resolution_action"] = "refund"
    state["resolution_details"] = {"refund_amount": 30.00, "reason": "Return request"}
    state["requires_human_review"] = False

    result = execute_node(state, store=store)
    assert result["status"] == "resolved"
    assert "refund_id" in result["resolution_details"]
