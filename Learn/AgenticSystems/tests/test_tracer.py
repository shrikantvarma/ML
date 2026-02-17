from agentdesk.tracing.tracer import create_trace_entry


def test_create_trace_entry():
    entry = create_trace_entry(
        agent="triage",
        input_summary="Customer asks about order status",
        output_summary="Classified as order_issue, urgency=low",
        confidence=0.95,
    )
    assert entry["agent"] == "triage"
    assert entry["confidence"] == 0.95
    assert "timestamp" in entry
    assert entry["input_summary"] == "Customer asks about order status"
