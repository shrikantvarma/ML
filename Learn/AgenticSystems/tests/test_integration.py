"""End-to-end integration tests using mocked LLM responses.

These tests verify the full graph flow -- supervisor routing through all agents --
without making real LLM calls.
"""

from unittest.mock import MagicMock, patch

from agentdesk.agents.supervisor import build_graph


def _mock_llm_factory():
    """Create a mock LLM that returns appropriate structured outputs based on the prompt.

    The mock dispatches on the Pydantic schema passed to ``with_structured_output``.
    For the ``SupervisorDecision`` schema a small counter is used to walk the
    supervisor through the expected routing sequence:

        triage -> order_lookup -> policy -> resolution -> response -> done

    Every other schema (TriageOutput, PolicyOutput, ResolutionDecision,
    ResponseOutput) is handled by returning a fixed mock that matches the
    fields each agent node expects.
    """
    mock_llm = MagicMock()

    # Track how many times the supervisor has been invoked so we can
    # return the correct routing decision for each pass through the loop.
    supervisor_calls = {"n": 0}

    def mock_with_structured_output(schema):
        mock_structured = MagicMock()

        def mock_invoke(messages):
            schema_name = schema.__name__

            if schema_name == "SupervisorDecision":
                supervisor_calls["n"] += 1
                n = supervisor_calls["n"]
                # Routing sequence the supervisor should follow:
                #  1 -> triage
                #  2 -> order_lookup  (after triage returns)
                #  3 -> policy        (after order_lookup returns)
                #  4 -> resolution    (after policy returns)
                #  5 -> response      (after resolution returns)
                #  6 -> done          (after response returns)
                route_sequence = {
                    1: ("triage", "Start with triage"),
                    2: ("order_lookup", "Need order details"),
                    3: ("policy", "Check policies"),
                    4: ("resolution", "Apply resolution"),
                    5: ("response", "Generate response"),
                }
                next_agent, reasoning = route_sequence.get(
                    n, ("done", "Workflow complete")
                )
                return MagicMock(next_agent=next_agent, reasoning=reasoning)

            elif schema_name == "TriageOutput":
                return MagicMock(
                    category="return_request",
                    urgency="medium",
                    extracted_entities={"order_id": "ORD-001"},
                )

            elif schema_name == "PolicyOutput":
                return MagicMock(
                    applicable_policies=[
                        "30-day return window",
                        "Auto-refund up to $100 for premium",
                    ],
                    allowed_actions=["refund", "replacement"],
                )

            elif schema_name == "ResolutionDecision":
                return MagicMock(
                    action="refund",
                    reason="Within return window",
                    refund_amount=40.00,
                )

            elif schema_name == "ResponseOutput":
                return MagicMock(
                    customer_response=(
                        "We've processed your refund of $40.00 for order ORD-001."
                    ),
                    internal_notes=(
                        "Refund processed automatically within premium tier limits."
                    ),
                )

            # Fallback for any unexpected schema
            return MagicMock()

        mock_structured.invoke = mock_invoke
        return mock_structured

    mock_llm.with_structured_output = mock_with_structured_output
    return mock_llm


# ---------------------------------------------------------------------------
# Full return-request flow
# ---------------------------------------------------------------------------


@patch("agentdesk.agents.triage.get_llm")
@patch("agentdesk.agents.policy.get_llm")
@patch("agentdesk.agents.resolution.get_llm")
@patch("agentdesk.agents.response.get_llm")
@patch("agentdesk.agents.supervisor.get_llm")
def test_full_return_request_flow(
    mock_sup_llm,
    mock_resp_llm,
    mock_res_llm,
    mock_pol_llm,
    mock_tri_llm,
):
    """Walk a return-request ticket through the entire supervisor graph.

    Expected agent sequence:
        supervisor -> triage -> supervisor -> order_lookup -> supervisor
        -> policy -> supervisor -> resolution (decide -> threshold_check
        -> execute) -> supervisor -> response -> supervisor -> END
    """
    mock_llm = _mock_llm_factory()
    mock_sup_llm.return_value = mock_llm
    mock_tri_llm.return_value = mock_llm
    mock_pol_llm.return_value = mock_llm
    mock_res_llm.return_value = mock_llm
    mock_resp_llm.return_value = mock_llm

    graph = build_graph()
    config = {"configurable": {"thread_id": "test-integration-001"}}

    initial_state = {
        "ticket_id": "T-INT-001",
        "customer_id": "C001",
        "customer_message": "I want to return the wireless headphones from order ORD-001",
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

    result = graph.invoke(initial_state, config=config)

    # -- Triage populated correctly --
    assert result["category"] == "return_request"
    assert result["urgency"] == "medium"
    assert result["extracted_entities"] == {"order_id": "ORD-001"}

    # -- Order lookup populated from mock store --
    assert result["order_details"] is not None
    assert result["order_details"]["order_id"] == "ORD-001"

    # -- Policy evaluation populated --
    assert len(result["applicable_policies"]) > 0
    assert len(result["allowed_actions"]) > 0

    # -- Resolution decided and executed --
    assert result["resolution_action"] == "refund"
    assert result["resolution_details"].get("refund_amount") == 40.00

    # -- Customer response generated --
    assert result["customer_response"] != ""
    assert "40.00" in result["customer_response"]
    assert result["internal_notes"] != ""

    # -- Workflow marked complete --
    assert result["status"] == "resolved"

    # -- Trace log captured key agents --
    agents_in_trace = [entry["agent"] for entry in result["trace_log"]]
    assert "supervisor" in agents_in_trace
    assert "triage" in agents_in_trace
    assert "order_lookup" in agents_in_trace
    assert "policy" in agents_in_trace
    assert "response" in agents_in_trace

    # Resolution sub-graph produces its own trace entries
    assert "resolution_decide" in agents_in_trace
    assert "resolution_threshold" in agents_in_trace
    assert "resolution_execute" in agents_in_trace

    # Supervisor should have been called multiple times (at least 6: one per
    # routing decision plus the final "done" decision)
    supervisor_trace_count = agents_in_trace.count("supervisor")
    assert supervisor_trace_count >= 6
