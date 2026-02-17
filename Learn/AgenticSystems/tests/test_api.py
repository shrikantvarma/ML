from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from agentdesk.main import app

client = TestClient(app)


def test_health_check():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_create_ticket_returns_ticket_id():
    with patch("agentdesk.api.routes.get_graph") as mock_get_graph:
        mock_graph = MagicMock()
        mock_graph.invoke.return_value = {
            "ticket_id": "T-test",
            "status": "resolved",
            "category": "product_question",
            "urgency": "low",
            "resolution_action": "info_only",
            "customer_response": "Here is the product info.",
            "internal_notes": "Simple inquiry.",
            "trace_log": [],
        }
        mock_get_graph.return_value = mock_graph

        response = client.post(
            "/tickets",
            json={"customer_id": "C001", "message": "What colors does P001 come in?"},
        )

        assert response.status_code == 200
        data = response.json()
        assert "ticket_id" in data
        assert data["status"] in ("resolved", "processing", "awaiting_human_review")


def test_list_tickets():
    response = client.get("/tickets")
    assert response.status_code == 200
    assert "tickets" in response.json()
