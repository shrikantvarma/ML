# AgentDesk: Agentic E-Commerce Customer Support System

## Overview

AgentDesk is a multi-agent customer ticket resolution system for e-commerce, built with LangGraph. A Supervisor agent orchestrates specialized agents that triage, investigate, resolve, and respond to customer tickets — with human-in-the-loop for risky actions.

## Tech Stack

- Python 3.11+
- LangGraph — agent orchestration, state management, human-in-the-loop
- LangChain — LLM abstraction (configurable: OpenAI, Anthropic, Ollama)
- FastAPI — REST API layer
- Pydantic — data models and validation
- In-memory mock store — orders, products, customers, policies (JSON-seeded)

## Architecture

Supervisor pattern with the Resolution Agent implemented as a subgraph.

```
┌─────────────────────────────────────────────────┐
│                   FastAPI API                     │
│  POST /tickets    GET /tickets/{id}              │
│  POST /tickets/{id}/review                       │
│  GET /tickets/{id}/trace                         │
└──────────────────────┬──────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────┐
│              Supervisor Graph                     │
│                                                   │
│  ┌──────────┐  ┌────────────┐  ┌──────────────┐ │
│  │  Triage   │  │   Order    │  │   Policy     │ │
│  │  Agent    │  │   Lookup   │  │   Agent      │ │
│  └──────────┘  └────────────┘  └──────────────┘ │
│                                                   │
│  ┌──────────────────────┐  ┌──────────────────┐  │
│  │  Resolution Agent    │  │  Response Agent  │  │
│  │  (Subgraph)          │  │                  │  │
│  │  ┌────────────────┐  │  └──────────────────┘  │
│  │  │ Decide → Check │  │                        │
│  │  │ → Execute/Esc  │  │                        │
│  │  └────────────────┘  │                        │
│  └──────────────────────┘                        │
│                                                   │
│         ┌────────────────────┐                   │
│         │  Human Review      │                   │
│         │  (interrupt)       │                   │
│         └────────────────────┘                   │
└──────────────────────┬──────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────┐
│           Mock E-Commerce Store                   │
│  Orders │ Products │ Customers │ Policies        │
└─────────────────────────────────────────────────┘
```

The Supervisor loops after each agent completes, deciding the next step via structured LLM output. This allows dynamic routing — simple inquiries skip unnecessary agents, while complex cases get the full pipeline.

## State Schema

```python
class TicketState(TypedDict):
    # Input
    ticket_id: str
    customer_id: str
    customer_message: str

    # Triage output
    category: str             # "order_issue", "return_request", "product_question", "billing", "complaint"
    urgency: str              # "low", "medium", "high", "critical"
    extracted_entities: dict   # {"order_id": "...", "product_id": "...", etc.}

    # Order Lookup output
    order_details: dict | None
    customer_history: dict | None

    # Policy output
    applicable_policies: list[str]
    allowed_actions: list[str]

    # Resolution output
    resolution_action: str        # "refund", "replacement", "escalate", "info_only", etc.
    resolution_details: dict
    requires_human_review: bool
    human_review_reason: str | None

    # Response output
    customer_response: str
    internal_notes: str

    # Tracing
    trace_log: list[dict]

    # Status
    status: str                   # "processing", "awaiting_human_review", "resolved", "escalated"
```

## Mock E-Commerce Data Models

- **Customer:** customer_id, name, email, tier (standard/premium/vip), account_age_days
- **Order:** order_id, customer_id, items, total, status (delivered/shipped/processing/cancelled), order_date, delivery_date, payment_method, shipping_address
- **Product:** product_id, name, category, price, in_stock, return_eligible
- **Policy rules (JSON config):** auto_refund_limit, return_window_days, vip_refund_limit, requires_human_review_above, free_replacement_eligible_tiers

## Agent Details

### 1. Triage Agent
- Classifies ticket: category, urgency, entity extraction
- Single LLM call with structured output (Pydantic model)
- No tools — pure classification

### 2. Order Lookup Agent
- Retrieves order details and customer history
- Tool-calling agent with tools: get_order(), get_customer(), get_product()
- Tools hit the mock store

### 3. Policy Agent
- Determines applicable policies and allowed actions
- LLM call with full policy ruleset as context
- Structured output, no tools

### 4. Resolution Agent (Subgraph)
- **Decide Node** — chooses best resolution action given triage + order + policies
- **Threshold Check Node** — compares action against policy thresholds (refund limits, tier allowances)
- **Execute Node** — within thresholds: executes via tools (process_refund, create_replacement_order, update_order_status)
- **Escalate Node** — outside thresholds: sets requires_human_review=True, triggers interrupt()

### 5. Response Agent
- Crafts customer-facing response and internal notes
- Single LLM call with tone guidelines
- Adjusts tone based on urgency and customer tier

### 6. Supervisor
- Orchestrates all agents via structured output routing
- Re-invoked after each agent to decide next step
- Can short-circuit (skip agents) or re-route dynamically

## Graph Flow

```
START → Supervisor
  ├─→ Triage Agent ─→ Supervisor (re-evaluates)
  ├─→ Order Lookup Agent ─→ Supervisor (re-evaluates)
  ├─→ Policy Agent ─→ Supervisor (re-evaluates)
  ├─→ Resolution Agent (subgraph)
  │     ├─→ Decide → Threshold Check → Execute ─→ Supervisor
  │     └─→ Decide → Threshold Check → Escalate ─→ interrupt() ─→ Human resumes ─→ Supervisor
  ├─→ Response Agent ─→ END
  └─→ END (direct escalation for critical cases)
```

## API Design

```
POST   /tickets                        # Submit new ticket, kicks off graph
  Body: { "customer_id": "...", "message": "..." }
  Returns: { "ticket_id": "...", "status": "processing" }

GET    /tickets/{ticket_id}            # Get ticket status and result
  Returns: { ticket_id, status, category, resolution_action, customer_response, internal_notes }

GET    /tickets/{ticket_id}/trace      # Full agent trace log
  Returns: { "trace_log": [...] }

POST   /tickets/{ticket_id}/review     # Human approves/rejects/modifies escalation
  Body: { "action": "approve|reject|modify", "modified_response": "..." }
  Returns: { "status": "resolved|escalated" }

GET    /tickets                        # List tickets with filtering
  Query: ?status=awaiting_human_review&category=return_request
```

## Traceability

- **Built-in:** Every agent appends a structured trace entry to trace_log in graph state (agent name, timestamp, input summary, decision/output, confidence)
- **Optional LangSmith:** Toggle with LANGSMITH_API_KEY env var for deeper LLM-level observability

## Autonomy Levels

- **Auto-approve:** Refunds under $50, order status inquiries, product information responses
- **Human review required:** Refunds over $100, VIP customer complaints, actions outside policy, critical urgency tickets
- **Configurable thresholds:** All limits defined in policies.json

## Project Structure

```
AgenticSystems/
├── agentdesk/
│   ├── __init__.py
│   ├── main.py                  # FastAPI app entrypoint
│   ├── api/
│   │   ├── __init__.py
│   │   └── routes.py
│   ├── agents/
│   │   ├── __init__.py
│   │   ├── supervisor.py
│   │   ├── triage.py
│   │   ├── order_lookup.py
│   │   ├── policy.py
│   │   ├── resolution.py
│   │   └── response.py
│   ├── models/
│   │   ├── __init__.py
│   │   ├── state.py
│   │   └── schemas.py
│   ├── store/
│   │   ├── __init__.py
│   │   ├── mock_data.py
│   │   ├── store.py
│   │   └── policies.json
│   ├── llm/
│   │   ├── __init__.py
│   │   └── provider.py
│   └── tracing/
│       ├── __init__.py
│       └── tracer.py
├── tests/
│   ├── test_triage.py
│   ├── test_resolution.py
│   ├── test_graph.py
│   └── test_api.py
├── docs/
│   └── plans/
├── .env.example
├── pyproject.toml
└── README.md
```

## Testing Strategy

- **Unit tests per agent:** Mock the LLM, verify state updates for given inputs
- **Resolution subgraph tests:** Verify threshold logic (auto-approve vs escalate)
- **Integration tests:** Full graph with mock LLM, verify supervisor routing
- **API tests:** FastAPI TestClient, full request lifecycle including human review
