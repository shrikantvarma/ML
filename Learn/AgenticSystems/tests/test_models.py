from agentdesk.models.state import TicketState
from agentdesk.models.schemas import TicketRequest, TicketResponse, HumanReviewRequest


def test_ticket_state_can_be_constructed():
    state: TicketState = {
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
    assert state["ticket_id"] == "T001"
    assert state["status"] == "processing"


def test_ticket_request_validation():
    req = TicketRequest(customer_id="C001", message="Where is my order #ORD-123?")
    assert req.customer_id == "C001"


def test_human_review_request_validation():
    req = HumanReviewRequest(action="approve")
    assert req.action == "approve"


def test_human_review_reject_with_reason():
    req = HumanReviewRequest(action="modify", modified_response="We apologize...")
    assert req.modified_response == "We apologize..."
