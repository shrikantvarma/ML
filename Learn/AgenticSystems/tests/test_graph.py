from unittest.mock import MagicMock, patch

from agentdesk.agents.supervisor import build_graph, supervisor_node


def test_supervisor_routes_to_triage_first():
    mock_llm = MagicMock()
    mock_structured = MagicMock()
    mock_llm.with_structured_output.return_value = mock_structured
    mock_structured.invoke.return_value = MagicMock(next_agent="triage", reasoning="No category yet")

    state = {
        "ticket_id": "T001",
        "customer_id": "C001",
        "customer_message": "Where is my order?",
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

    result = supervisor_node(state, llm=mock_llm)
    assert result["trace_log"][0]["agent"] == "supervisor"
    assert result["next_agent"] == "triage"


def test_build_graph_compiles():
    graph = build_graph()
    assert graph is not None
