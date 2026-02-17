from __future__ import annotations

import os
from datetime import datetime, timezone


def create_trace_entry(
    agent: str,
    input_summary: str,
    output_summary: str,
    confidence: float | None = None,
) -> dict:
    """Create a structured trace log entry."""
    return {
        "agent": agent,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "input_summary": input_summary,
        "output_summary": output_summary,
        "confidence": confidence,
    }


def setup_langsmith_tracing() -> None:
    """Enable LangSmith tracing if API key is set."""
    if os.getenv("LANGSMITH_API_KEY"):
        os.environ.setdefault("LANGCHAIN_TRACING_V2", "true")
        os.environ.setdefault("LANGCHAIN_PROJECT", "agentdesk")
