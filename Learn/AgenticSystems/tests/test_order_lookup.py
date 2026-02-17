from agentdesk.agents.order_lookup import order_lookup_node
from agentdesk.store.store import MockStore


def _make_state(customer_id: str, entities: dict) -> dict:
    return {
        "ticket_id": "T001",
        "customer_id": customer_id,
        "customer_message": "test",
        "category": "order_issue",
        "urgency": "low",
        "extracted_entities": entities,
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


def test_order_lookup_with_order_id():
    store = MockStore()
    state = _make_state("C001", {"order_id": "ORD-001"})
    result = order_lookup_node(state, store=store)

    assert result["order_details"] is not None
    assert result["order_details"]["order_id"] == "ORD-001"
    assert result["customer_history"] is not None
    assert result["customer_history"]["tier"] == "premium"
    assert len(result["trace_log"]) == 1


def test_order_lookup_without_order_id_falls_back_to_customer():
    store = MockStore()
    state = _make_state("C002", {})
    result = order_lookup_node(state, store=store)

    assert result["order_details"] is not None
    assert result["customer_history"] is not None


def test_order_lookup_unknown_customer():
    store = MockStore()
    state = _make_state("CXXX", {"order_id": "ORD-999"})
    result = order_lookup_node(state, store=store)

    assert result["order_details"] is None
    assert result["customer_history"] is None
