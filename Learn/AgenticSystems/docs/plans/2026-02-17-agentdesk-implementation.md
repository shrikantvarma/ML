# AgentDesk Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a multi-agent e-commerce customer support system using LangGraph with supervisor orchestration, human-in-the-loop, and a FastAPI REST API.

**Architecture:** Supervisor pattern — a central supervisor agent uses structured LLM output to route tickets through specialized agents (triage, order lookup, policy, resolution, response). The resolution agent is a subgraph with threshold-based escalation via LangGraph's `interrupt()`. Mock in-memory e-commerce data backs the system.

**Tech Stack:** Python 3.11+, LangGraph, LangChain, FastAPI, Pydantic, pytest

**Design doc:** `docs/plans/2026-02-17-agentdesk-design.md`

---

### Task 1: Project Scaffolding

**Files:**
- Create: `pyproject.toml`
- Create: `.env.example`
- Create: all `__init__.py` files for package structure

**Step 1: Create pyproject.toml**

```toml
[project]
name = "agentdesk"
version = "0.1.0"
description = "Agentic e-commerce customer support system"
requires-python = ">=3.11"
dependencies = [
    "langgraph>=0.4.0",
    "langchain>=0.3.0",
    "langchain-openai>=0.3.0",
    "langchain-anthropic>=0.3.0",
    "langchain-ollama>=0.3.0",
    "langchain-core>=0.3.0",
    "fastapi>=0.115.0",
    "uvicorn>=0.34.0",
    "pydantic>=2.0",
    "python-dotenv>=1.0.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=8.0",
    "pytest-asyncio>=0.24.0",
    "httpx>=0.28.0",
]

[build-system]
requires = ["setuptools>=75.0"]
build-backend = "setuptools.backends._legacy:_Backend"
```

**Step 2: Create .env.example**

```
# LLM Provider: "openai", "anthropic", or "ollama"
LLM_PROVIDER=openai

# API Keys (set the one matching your provider)
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...

# Ollama (if using local models)
OLLAMA_MODEL=llama3.1
OLLAMA_BASE_URL=http://localhost:11434

# Optional: LangSmith tracing
LANGSMITH_API_KEY=
LANGCHAIN_TRACING_V2=false
LANGCHAIN_PROJECT=agentdesk
```

**Step 3: Create directory structure with __init__.py files**

```bash
mkdir -p agentdesk/{api,agents,models,store,tracing}
mkdir -p tests
touch agentdesk/__init__.py
touch agentdesk/api/__init__.py
touch agentdesk/agents/__init__.py
touch agentdesk/models/__init__.py
touch agentdesk/store/__init__.py
touch agentdesk/tracing/__init__.py
touch tests/__init__.py
```

**Step 4: Install dependencies**

```bash
pip install -e ".[dev]"
```

**Step 5: Commit**

```bash
git add pyproject.toml .env.example agentdesk/ tests/
git commit -m "feat: scaffold agentdesk project structure"
```

---

### Task 2: State Models & API Schemas

**Files:**
- Create: `agentdesk/models/state.py`
- Create: `agentdesk/models/schemas.py`

**Step 1: Write test for state model**

Create `tests/test_models.py`:

```python
from agentdesk.models.state import TicketState


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
```

**Step 2: Run test to verify it fails**

```bash
pytest tests/test_models.py::test_ticket_state_can_be_constructed -v
```
Expected: FAIL — `ModuleNotFoundError: No module named 'agentdesk.models.state'`

**Step 3: Write state.py**

Create `agentdesk/models/state.py`:

```python
from __future__ import annotations

import operator
from typing import Annotated, TypedDict


class TicketState(TypedDict):
    """Shared state flowing through the AgentDesk supervisor graph."""

    # Input
    ticket_id: str
    customer_id: str
    customer_message: str

    # Triage output
    category: str
    urgency: str
    extracted_entities: dict

    # Order Lookup output
    order_details: dict | None
    customer_history: dict | None

    # Policy output
    applicable_policies: list[str]
    allowed_actions: list[str]

    # Resolution output
    resolution_action: str
    resolution_details: dict
    requires_human_review: bool
    human_review_reason: str | None

    # Response output
    customer_response: str
    internal_notes: str

    # Tracing — append-only via Annotated reducer
    trace_log: Annotated[list[dict], operator.add]

    # Status
    status: str
```

**Step 4: Run test to verify it passes**

```bash
pytest tests/test_models.py::test_ticket_state_can_be_constructed -v
```
Expected: PASS

**Step 5: Write test for API schemas**

Append to `tests/test_models.py`:

```python
from agentdesk.models.schemas import TicketRequest, TicketResponse, HumanReviewRequest


def test_ticket_request_validation():
    req = TicketRequest(customer_id="C001", message="Where is my order #ORD-123?")
    assert req.customer_id == "C001"


def test_human_review_request_validation():
    req = HumanReviewRequest(action="approve")
    assert req.action == "approve"


def test_human_review_reject_with_reason():
    req = HumanReviewRequest(action="modify", modified_response="We apologize...")
    assert req.modified_response == "We apologize..."
```

**Step 6: Run test to verify it fails**

```bash
pytest tests/test_models.py::test_ticket_request_validation -v
```
Expected: FAIL

**Step 7: Write schemas.py**

Create `agentdesk/models/schemas.py`:

```python
from __future__ import annotations

from typing import Literal

from pydantic import BaseModel


class TicketRequest(BaseModel):
    customer_id: str
    message: str


class TicketResponse(BaseModel):
    ticket_id: str
    status: str
    category: str | None = None
    urgency: str | None = None
    resolution_action: str | None = None
    customer_response: str | None = None
    internal_notes: str | None = None


class TicketListResponse(BaseModel):
    tickets: list[TicketResponse]


class TraceResponse(BaseModel):
    ticket_id: str
    trace_log: list[dict]


class HumanReviewRequest(BaseModel):
    action: Literal["approve", "reject", "modify"]
    modified_response: str | None = None


class HumanReviewResponse(BaseModel):
    ticket_id: str
    status: str
```

**Step 8: Run all model tests**

```bash
pytest tests/test_models.py -v
```
Expected: All PASS

**Step 9: Commit**

```bash
git add agentdesk/models/ tests/test_models.py
git commit -m "feat: add TicketState and API Pydantic schemas"
```

---

### Task 3: Mock E-Commerce Store

**Files:**
- Create: `agentdesk/store/mock_data.py`
- Create: `agentdesk/store/store.py`
- Create: `agentdesk/store/policies.json`

**Step 1: Write test for store**

Create `tests/test_store.py`:

```python
from agentdesk.store.store import MockStore


def test_get_customer():
    store = MockStore()
    customer = store.get_customer("C001")
    assert customer is not None
    assert customer["customer_id"] == "C001"
    assert customer["tier"] in ("standard", "premium", "vip")


def test_get_customer_not_found():
    store = MockStore()
    assert store.get_customer("NONEXISTENT") is None


def test_get_order():
    store = MockStore()
    order = store.get_order("ORD-001")
    assert order is not None
    assert order["order_id"] == "ORD-001"
    assert "items" in order


def test_get_orders_by_customer():
    store = MockStore()
    orders = store.get_orders_by_customer("C001")
    assert len(orders) >= 1
    assert all(o["customer_id"] == "C001" for o in orders)


def test_get_product():
    store = MockStore()
    product = store.get_product("P001")
    assert product is not None
    assert "price" in product


def test_get_policies():
    store = MockStore()
    policies = store.get_policies()
    assert "auto_refund_limit" in policies
    assert "return_window_days" in policies


def test_process_refund():
    store = MockStore()
    result = store.process_refund("ORD-001", 25.00, "Customer request")
    assert result["success"] is True
    assert result["refund_amount"] == 25.00


def test_create_replacement_order():
    store = MockStore()
    result = store.create_replacement_order("ORD-001")
    assert result["success"] is True
    assert "replacement_order_id" in result
```

**Step 2: Run test to verify it fails**

```bash
pytest tests/test_store.py -v
```
Expected: FAIL

**Step 3: Write policies.json**

Create `agentdesk/store/policies.json`:

```json
{
    "auto_refund_limit": 50.00,
    "return_window_days": 30,
    "vip_refund_limit": 200.00,
    "premium_refund_limit": 100.00,
    "requires_human_review_above": 100.00,
    "free_replacement_eligible_tiers": ["premium", "vip"],
    "max_replacements_per_order": 1,
    "escalation_required_categories": ["complaint"],
    "auto_resolve_categories": ["product_question"]
}
```

**Step 4: Write mock_data.py**

Create `agentdesk/store/mock_data.py`:

```python
CUSTOMERS = [
    {
        "customer_id": "C001",
        "name": "Alice Johnson",
        "email": "alice@example.com",
        "tier": "premium",
        "account_age_days": 730,
    },
    {
        "customer_id": "C002",
        "name": "Bob Smith",
        "email": "bob@example.com",
        "tier": "standard",
        "account_age_days": 90,
    },
    {
        "customer_id": "C003",
        "name": "Carol Williams",
        "email": "carol@example.com",
        "tier": "vip",
        "account_age_days": 1460,
    },
    {
        "customer_id": "C004",
        "name": "Dave Brown",
        "email": "dave@example.com",
        "tier": "standard",
        "account_age_days": 30,
    },
]

PRODUCTS = [
    {
        "product_id": "P001",
        "name": "Wireless Headphones",
        "category": "Electronics",
        "price": 79.99,
        "in_stock": True,
        "return_eligible": True,
    },
    {
        "product_id": "P002",
        "name": "Running Shoes",
        "category": "Footwear",
        "price": 129.99,
        "in_stock": True,
        "return_eligible": True,
    },
    {
        "product_id": "P003",
        "name": "Coffee Maker",
        "category": "Kitchen",
        "price": 49.99,
        "in_stock": False,
        "return_eligible": True,
    },
    {
        "product_id": "P004",
        "name": "Custom Engraved Watch",
        "category": "Jewelry",
        "price": 299.99,
        "in_stock": True,
        "return_eligible": False,
    },
    {
        "product_id": "P005",
        "name": "Phone Case",
        "category": "Accessories",
        "price": 19.99,
        "in_stock": True,
        "return_eligible": True,
    },
]

ORDERS = [
    {
        "order_id": "ORD-001",
        "customer_id": "C001",
        "items": [
            {"product_id": "P001", "name": "Wireless Headphones", "quantity": 1, "price": 79.99},
        ],
        "total": 79.99,
        "status": "delivered",
        "order_date": "2026-01-15",
        "delivery_date": "2026-01-20",
        "payment_method": "credit_card",
        "shipping_address": "123 Main St, Springfield, IL",
    },
    {
        "order_id": "ORD-002",
        "customer_id": "C001",
        "items": [
            {"product_id": "P002", "name": "Running Shoes", "quantity": 1, "price": 129.99},
        ],
        "total": 129.99,
        "status": "shipped",
        "order_date": "2026-02-10",
        "delivery_date": None,
        "payment_method": "credit_card",
        "shipping_address": "123 Main St, Springfield, IL",
    },
    {
        "order_id": "ORD-003",
        "customer_id": "C002",
        "items": [
            {"product_id": "P003", "name": "Coffee Maker", "quantity": 1, "price": 49.99},
            {"product_id": "P005", "name": "Phone Case", "quantity": 2, "price": 19.99},
        ],
        "total": 89.97,
        "status": "delivered",
        "order_date": "2026-01-28",
        "delivery_date": "2026-02-02",
        "payment_method": "paypal",
        "shipping_address": "456 Oak Ave, Portland, OR",
    },
    {
        "order_id": "ORD-004",
        "customer_id": "C003",
        "items": [
            {"product_id": "P004", "name": "Custom Engraved Watch", "quantity": 1, "price": 299.99},
        ],
        "total": 299.99,
        "status": "delivered",
        "order_date": "2026-01-05",
        "delivery_date": "2026-01-12",
        "payment_method": "credit_card",
        "shipping_address": "789 Pine Rd, Austin, TX",
    },
    {
        "order_id": "ORD-005",
        "customer_id": "C004",
        "items": [
            {"product_id": "P005", "name": "Phone Case", "quantity": 1, "price": 19.99},
        ],
        "total": 19.99,
        "status": "processing",
        "order_date": "2026-02-16",
        "delivery_date": None,
        "payment_method": "debit_card",
        "shipping_address": "321 Elm St, Denver, CO",
    },
]
```

**Step 5: Write store.py**

Create `agentdesk/store/store.py`:

```python
from __future__ import annotations

import json
import uuid
from pathlib import Path

from agentdesk.store.mock_data import CUSTOMERS, ORDERS, PRODUCTS


class MockStore:
    """In-memory e-commerce store backed by mock data."""

    def __init__(self) -> None:
        self._customers = {c["customer_id"]: c for c in CUSTOMERS}
        self._orders = {o["order_id"]: o for o in ORDERS}
        self._products = {p["product_id"]: p for p in PRODUCTS}
        self._refunds: list[dict] = []
        self._replacement_orders: list[dict] = []

        policies_path = Path(__file__).parent / "policies.json"
        with open(policies_path) as f:
            self._policies = json.load(f)

    def get_customer(self, customer_id: str) -> dict | None:
        return self._customers.get(customer_id)

    def get_order(self, order_id: str) -> dict | None:
        return self._orders.get(order_id)

    def get_orders_by_customer(self, customer_id: str) -> list[dict]:
        return [o for o in self._orders.values() if o["customer_id"] == customer_id]

    def get_product(self, product_id: str) -> dict | None:
        return self._products.get(product_id)

    def get_policies(self) -> dict:
        return self._policies

    def process_refund(self, order_id: str, amount: float, reason: str) -> dict:
        refund = {
            "refund_id": f"REF-{uuid.uuid4().hex[:6].upper()}",
            "order_id": order_id,
            "refund_amount": amount,
            "reason": reason,
            "status": "processed",
        }
        self._refunds.append(refund)
        return {"success": True, **refund}

    def create_replacement_order(self, original_order_id: str) -> dict:
        original = self._orders.get(original_order_id)
        if not original:
            return {"success": False, "error": "Original order not found"}

        replacement_id = f"ORD-R{uuid.uuid4().hex[:4].upper()}"
        replacement = {
            **original,
            "order_id": replacement_id,
            "status": "processing",
            "original_order_id": original_order_id,
        }
        self._orders[replacement_id] = replacement
        self._replacement_orders.append(replacement)
        return {"success": True, "replacement_order_id": replacement_id}

    def update_order_status(self, order_id: str, status: str) -> dict:
        order = self._orders.get(order_id)
        if not order:
            return {"success": False, "error": "Order not found"}
        order["status"] = status
        return {"success": True, "order_id": order_id, "new_status": status}
```

**Step 6: Run store tests**

```bash
pytest tests/test_store.py -v
```
Expected: All PASS

**Step 7: Commit**

```bash
git add agentdesk/store/ tests/test_store.py
git commit -m "feat: add mock e-commerce store with seed data and policies"
```

---

### Task 4: Configurable LLM Provider

**Files:**
- Create: `agentdesk/llm/provider.py`

**Step 1: Write test**

Create `tests/test_llm_provider.py`:

```python
import os
from unittest.mock import patch

from agentdesk.llm.provider import get_llm


@patch.dict(os.environ, {"LLM_PROVIDER": "openai", "OPENAI_API_KEY": "sk-test"})
def test_get_llm_openai():
    llm = get_llm()
    assert llm is not None
    assert "openai" in type(llm).__module__.lower()


@patch.dict(os.environ, {"LLM_PROVIDER": "anthropic", "ANTHROPIC_API_KEY": "sk-ant-test"})
def test_get_llm_anthropic():
    llm = get_llm()
    assert llm is not None
    assert "anthropic" in type(llm).__module__.lower()


def test_get_llm_invalid_provider():
    import pytest
    with patch.dict(os.environ, {"LLM_PROVIDER": "invalid"}):
        with pytest.raises(ValueError, match="Unsupported LLM provider"):
            get_llm()
```

**Step 2: Run test to verify it fails**

```bash
pytest tests/test_llm_provider.py -v
```
Expected: FAIL

**Step 3: Write provider.py**

Create `agentdesk/llm/provider.py`:

```python
from __future__ import annotations

import os

from dotenv import load_dotenv
from langchain_core.language_models import BaseChatModel

load_dotenv()


def get_llm(provider: str | None = None, model: str | None = None) -> BaseChatModel:
    """Return a configured LLM based on environment or explicit args."""
    provider = provider or os.getenv("LLM_PROVIDER", "openai")

    if provider == "openai":
        from langchain_openai import ChatOpenAI

        return ChatOpenAI(model=model or "gpt-4o-mini", temperature=0)

    if provider == "anthropic":
        from langchain_anthropic import ChatAnthropic

        return ChatAnthropic(model=model or "claude-sonnet-4-5-20250929", temperature=0)

    if provider == "ollama":
        from langchain_ollama import ChatOllama

        return ChatOllama(
            model=model or os.getenv("OLLAMA_MODEL", "llama3.1"),
            base_url=os.getenv("OLLAMA_BASE_URL", "http://localhost:11434"),
            temperature=0,
        )

    raise ValueError(f"Unsupported LLM provider: {provider}")
```

**Step 4: Run tests**

```bash
pytest tests/test_llm_provider.py -v
```
Expected: All PASS

**Step 5: Commit**

```bash
git add agentdesk/llm/ tests/test_llm_provider.py
git commit -m "feat: add configurable LLM provider (OpenAI/Anthropic/Ollama)"
```

---

### Task 5: Tracing Module

**Files:**
- Create: `agentdesk/tracing/tracer.py`

**Step 1: Write test**

Create `tests/test_tracer.py`:

```python
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
```

**Step 2: Run test to verify it fails**

```bash
pytest tests/test_tracer.py -v
```
Expected: FAIL

**Step 3: Write tracer.py**

Create `agentdesk/tracing/tracer.py`:

```python
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
```

**Step 4: Run test**

```bash
pytest tests/test_tracer.py -v
```
Expected: PASS

**Step 5: Commit**

```bash
git add agentdesk/tracing/ tests/test_tracer.py
git commit -m "feat: add trace entry helper and optional LangSmith setup"
```

---

### Task 6: Triage Agent

**Files:**
- Create: `agentdesk/agents/triage.py`
- Create: `tests/test_triage.py`

**Step 1: Write test**

Create `tests/test_triage.py`:

```python
from unittest.mock import MagicMock, patch

from agentdesk.agents.triage import triage_node
from agentdesk.models.state import TicketState


def _make_state(message: str) -> TicketState:
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
```

**Step 2: Run test to verify it fails**

```bash
pytest tests/test_triage.py -v
```
Expected: FAIL

**Step 3: Write triage.py**

Create `agentdesk/agents/triage.py`:

```python
from __future__ import annotations

from typing import Literal

from langchain_core.language_models import BaseChatModel
from langchain_core.messages import HumanMessage, SystemMessage
from pydantic import BaseModel, Field

from agentdesk.llm.provider import get_llm
from agentdesk.models.state import TicketState
from agentdesk.tracing.tracer import create_trace_entry

TRIAGE_SYSTEM_PROMPT = """\
You are a customer support triage agent for an e-commerce company.

Classify the customer message into exactly one category and urgency level.
Extract any relevant entity IDs (order IDs, product IDs) from the message.

Categories:
- order_issue: Questions about order status, delivery, shipping
- return_request: Customer wants to return or exchange a product
- product_question: Questions about product features, availability, specs
- billing: Payment issues, charges, invoices
- complaint: General dissatisfaction, negative experience

Urgency levels:
- low: General inquiries, no time pressure
- medium: Needs attention but not urgent
- high: Customer is frustrated or issue is time-sensitive
- critical: Potential legal issue, VIP escalation, or service outage
"""


class TriageOutput(BaseModel):
    category: Literal[
        "order_issue", "return_request", "product_question", "billing", "complaint"
    ] = Field(description="The ticket category")
    urgency: Literal["low", "medium", "high", "critical"] = Field(
        description="The urgency level"
    )
    extracted_entities: dict = Field(
        default_factory=dict,
        description="Extracted entity IDs, e.g. {'order_id': 'ORD-001', 'product_id': 'P001'}",
    )


def triage_node(state: TicketState, *, llm: BaseChatModel | None = None) -> dict:
    """Classify and extract entities from the customer message."""
    llm = llm or get_llm()
    structured_llm = llm.with_structured_output(TriageOutput)

    result = structured_llm.invoke([
        SystemMessage(content=TRIAGE_SYSTEM_PROMPT),
        HumanMessage(content=state["customer_message"]),
    ])

    trace = create_trace_entry(
        agent="triage",
        input_summary=state["customer_message"][:100],
        output_summary=f"category={result.category}, urgency={result.urgency}",
        confidence=None,
    )

    return {
        "category": result.category,
        "urgency": result.urgency,
        "extracted_entities": result.extracted_entities,
        "trace_log": [trace],
    }
```

**Step 4: Run tests**

```bash
pytest tests/test_triage.py -v
```
Expected: All PASS

**Step 5: Commit**

```bash
git add agentdesk/agents/triage.py tests/test_triage.py
git commit -m "feat: add triage agent with structured classification"
```

---

### Task 7: Order Lookup Agent

**Files:**
- Create: `agentdesk/agents/order_lookup.py`
- Create: `tests/test_order_lookup.py`

**Step 1: Write test**

Create `tests/test_order_lookup.py`:

```python
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
```

**Step 2: Run test to verify it fails**

```bash
pytest tests/test_order_lookup.py -v
```
Expected: FAIL

**Step 3: Write order_lookup.py**

Create `agentdesk/agents/order_lookup.py`:

```python
from __future__ import annotations

from agentdesk.models.state import TicketState
from agentdesk.store.store import MockStore
from agentdesk.tracing.tracer import create_trace_entry


def order_lookup_node(state: TicketState, *, store: MockStore | None = None) -> dict:
    """Look up order details and customer history from the store."""
    store = store or MockStore()

    entities = state["extracted_entities"]
    order_id = entities.get("order_id")
    customer_id = state["customer_id"]

    # Look up order
    order_details = None
    if order_id:
        order_details = store.get_order(order_id)

    # If no order found by ID, get most recent order for this customer
    if order_details is None:
        orders = store.get_orders_by_customer(customer_id)
        if orders:
            order_details = orders[-1]  # most recent

    # Look up customer
    customer = store.get_customer(customer_id)
    customer_history = None
    if customer:
        orders = store.get_orders_by_customer(customer_id)
        customer_history = {
            **customer,
            "total_orders": len(orders),
            "recent_orders": [o["order_id"] for o in orders[-3:]],
        }

    trace = create_trace_entry(
        agent="order_lookup",
        input_summary=f"order_id={order_id}, customer_id={customer_id}",
        output_summary=f"order_found={order_details is not None}, customer_found={customer_history is not None}",
    )

    return {
        "order_details": order_details,
        "customer_history": customer_history,
        "trace_log": [trace],
    }
```

**Step 4: Run tests**

```bash
pytest tests/test_order_lookup.py -v
```
Expected: All PASS

**Step 5: Commit**

```bash
git add agentdesk/agents/order_lookup.py tests/test_order_lookup.py
git commit -m "feat: add order lookup agent with customer history"
```

---

### Task 8: Policy Agent

**Files:**
- Create: `agentdesk/agents/policy.py`
- Create: `tests/test_policy.py`

**Step 1: Write test**

Create `tests/test_policy.py`:

```python
from unittest.mock import MagicMock

from agentdesk.agents.policy import policy_node


def _make_state(category: str, tier: str, order_total: float) -> dict:
    return {
        "ticket_id": "T001",
        "customer_id": "C001",
        "customer_message": "test",
        "category": category,
        "urgency": "medium",
        "extracted_entities": {},
        "order_details": {"order_id": "ORD-001", "total": order_total, "status": "delivered",
                          "order_date": "2026-02-01", "items": []},
        "customer_history": {"tier": tier, "total_orders": 5},
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


def test_policy_return_request_standard_tier():
    mock_llm = MagicMock()
    mock_structured = MagicMock()
    mock_llm.with_structured_output.return_value = mock_structured

    mock_structured.invoke.return_value = MagicMock(
        applicable_policies=["30-day return window", "Auto-refund up to $50"],
        allowed_actions=["refund", "replacement"],
    )

    state = _make_state("return_request", "standard", 45.00)
    result = policy_node(state, llm=mock_llm)

    assert len(result["applicable_policies"]) > 0
    assert len(result["allowed_actions"]) > 0
    assert len(result["trace_log"]) == 1
    assert result["trace_log"][0]["agent"] == "policy"


def test_policy_product_question():
    mock_llm = MagicMock()
    mock_structured = MagicMock()
    mock_llm.with_structured_output.return_value = mock_structured

    mock_structured.invoke.return_value = MagicMock(
        applicable_policies=["Auto-resolve product questions"],
        allowed_actions=["info_only"],
    )

    state = _make_state("product_question", "standard", 0)
    result = policy_node(state, llm=mock_llm)

    assert "info_only" in result["allowed_actions"]
```

**Step 2: Run test to verify it fails**

```bash
pytest tests/test_policy.py -v
```
Expected: FAIL

**Step 3: Write policy.py**

Create `agentdesk/agents/policy.py`:

```python
from __future__ import annotations

from langchain_core.language_models import BaseChatModel
from langchain_core.messages import HumanMessage, SystemMessage
from pydantic import BaseModel, Field

from agentdesk.llm.provider import get_llm
from agentdesk.models.state import TicketState
from agentdesk.store.store import MockStore
from agentdesk.tracing.tracer import create_trace_entry

POLICY_SYSTEM_PROMPT = """\
You are a policy evaluation agent for an e-commerce company.

Given the ticket category, order details, and customer tier, determine which policies apply
and what actions the system is allowed to take.

Policy Rules:
{policies}

Customer tier: {tier}
Order total: ${order_total}
Order status: {order_status}
Category: {category}

Return the applicable policy names and the list of allowed actions.

Possible actions: refund, replacement, escalate, info_only, cancel_order, update_shipping
"""


class PolicyOutput(BaseModel):
    applicable_policies: list[str] = Field(description="List of policy rules that apply")
    allowed_actions: list[str] = Field(description="Actions the system is allowed to take")


def policy_node(state: TicketState, *, llm: BaseChatModel | None = None, store: MockStore | None = None) -> dict:
    """Evaluate policies and determine allowed actions."""
    llm = llm or get_llm()
    store = store or MockStore()

    policies = store.get_policies()
    order = state["order_details"] or {}
    customer = state["customer_history"] or {}

    prompt = POLICY_SYSTEM_PROMPT.format(
        policies=policies,
        tier=customer.get("tier", "standard"),
        order_total=order.get("total", 0),
        order_status=order.get("status", "unknown"),
        category=state["category"],
    )

    structured_llm = llm.with_structured_output(PolicyOutput)
    result = structured_llm.invoke([
        SystemMessage(content=prompt),
        HumanMessage(content=f"Evaluate policies for this {state['category']} ticket."),
    ])

    trace = create_trace_entry(
        agent="policy",
        input_summary=f"category={state['category']}, tier={customer.get('tier', 'unknown')}",
        output_summary=f"policies={result.applicable_policies}, actions={result.allowed_actions}",
    )

    return {
        "applicable_policies": result.applicable_policies,
        "allowed_actions": result.allowed_actions,
        "trace_log": [trace],
    }
```

**Step 4: Run tests**

```bash
pytest tests/test_policy.py -v
```
Expected: All PASS

**Step 5: Commit**

```bash
git add agentdesk/agents/policy.py tests/test_policy.py
git commit -m "feat: add policy agent with structured policy evaluation"
```

---

### Task 9: Resolution Agent (Subgraph)

**Files:**
- Create: `agentdesk/agents/resolution.py`
- Create: `tests/test_resolution.py`

**Step 1: Write test**

Create `tests/test_resolution.py`:

```python
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
```

**Step 2: Run test to verify it fails**

```bash
pytest tests/test_resolution.py -v
```
Expected: FAIL

**Step 3: Write resolution.py**

Create `agentdesk/agents/resolution.py`:

```python
from __future__ import annotations

from typing import Literal

from langchain_core.language_models import BaseChatModel
from langchain_core.messages import HumanMessage, SystemMessage
from langgraph.graph import END, START, StateGraph
from langgraph.types import interrupt
from pydantic import BaseModel, Field

from agentdesk.llm.provider import get_llm
from agentdesk.models.state import TicketState
from agentdesk.store.store import MockStore
from agentdesk.tracing.tracer import create_trace_entry

DECIDE_SYSTEM_PROMPT = """\
You are a resolution agent for an e-commerce company.

Given the ticket context, decide the best resolution action.
Only choose actions from the allowed_actions list.

Ticket category: {category}
Customer message: {message}
Order details: {order_details}
Customer tier: {tier}
Allowed actions: {allowed_actions}
Applicable policies: {policies}

Choose the single best action and explain why.
If the action is a refund, specify the refund amount.
"""


class ResolutionDecision(BaseModel):
    action: str = Field(description="The resolution action to take")
    reason: str = Field(description="Why this action was chosen")
    refund_amount: float | None = Field(default=None, description="Refund amount if applicable")


def decide_node(state: TicketState, *, llm: BaseChatModel | None = None) -> dict:
    """Decide the best resolution action."""
    llm = llm or get_llm()
    order = state["order_details"] or {}
    customer = state["customer_history"] or {}

    prompt = DECIDE_SYSTEM_PROMPT.format(
        category=state["category"],
        message=state["customer_message"],
        order_details=order,
        tier=customer.get("tier", "standard"),
        allowed_actions=state["allowed_actions"],
        policies=state["applicable_policies"],
    )

    structured_llm = llm.with_structured_output(ResolutionDecision)
    result = structured_llm.invoke([
        SystemMessage(content=prompt),
        HumanMessage(content="Decide the resolution."),
    ])

    details = {"reason": result.reason}
    if result.refund_amount is not None:
        details["refund_amount"] = result.refund_amount

    trace = create_trace_entry(
        agent="resolution_decide",
        input_summary=f"category={state['category']}, allowed={state['allowed_actions']}",
        output_summary=f"action={result.action}, reason={result.reason}",
    )

    return {
        "resolution_action": result.action,
        "resolution_details": details,
        "trace_log": [trace],
    }


def threshold_check_node(state: TicketState, *, store: MockStore | None = None) -> dict:
    """Check if the resolution action is within auto-approval thresholds."""
    store = store or MockStore()
    policies = store.get_policies()
    customer = state["customer_history"] or {}
    tier = customer.get("tier", "standard")
    action = state["resolution_action"]

    requires_review = False
    reason = None

    if action == "refund":
        amount = state["resolution_details"].get("refund_amount", 0)
        limit = policies.get(f"{tier}_refund_limit", policies["auto_refund_limit"])
        if amount > limit:
            requires_review = True
            reason = f"Refund ${amount:.2f} exceeds {tier} auto-approval limit of ${limit:.2f}"

    elif action == "replacement":
        if tier not in policies.get("free_replacement_eligible_tiers", []):
            requires_review = True
            reason = f"Customer tier '{tier}' not eligible for free replacement"

    elif action == "escalate":
        requires_review = True
        reason = "Agent recommended manual escalation"

    trace = create_trace_entry(
        agent="resolution_threshold",
        input_summary=f"action={action}, tier={tier}",
        output_summary=f"requires_review={requires_review}, reason={reason}",
    )

    return {
        "requires_human_review": requires_review,
        "human_review_reason": reason,
        "trace_log": [trace],
    }


def execute_node(state: TicketState, *, store: MockStore | None = None) -> dict:
    """Execute the resolution action (refund, replacement, etc.)."""
    store = store or MockStore()
    action = state["resolution_action"]
    details = dict(state["resolution_details"])
    order = state["order_details"] or {}
    order_id = order.get("order_id", "")

    if action == "refund":
        result = store.process_refund(
            order_id,
            details.get("refund_amount", 0),
            details.get("reason", "Customer request"),
        )
        details.update(result)

    elif action == "replacement":
        result = store.create_replacement_order(order_id)
        details.update(result)

    elif action == "cancel_order":
        result = store.update_order_status(order_id, "cancelled")
        details.update(result)

    trace = create_trace_entry(
        agent="resolution_execute",
        input_summary=f"action={action}, order={order_id}",
        output_summary=f"executed={action}, details={details}",
    )

    return {
        "resolution_details": details,
        "status": "resolved",
        "trace_log": [trace],
    }


def escalate_node(state: TicketState) -> dict:
    """Pause for human review via LangGraph interrupt."""
    review_payload = {
        "ticket_id": state["ticket_id"],
        "customer_message": state["customer_message"],
        "proposed_action": state["resolution_action"],
        "resolution_details": state["resolution_details"],
        "reason": state["human_review_reason"],
    }

    human_decision = interrupt(review_payload)

    trace = create_trace_entry(
        agent="resolution_escalate",
        input_summary=f"reason={state['human_review_reason']}",
        output_summary=f"human_decision={human_decision}",
    )

    if human_decision.get("action") == "approve":
        return {
            "status": "resolved",
            "trace_log": [trace],
        }
    elif human_decision.get("action") == "modify":
        return {
            "customer_response": human_decision.get("modified_response", ""),
            "status": "resolved",
            "trace_log": [trace],
        }
    else:
        return {
            "status": "escalated",
            "trace_log": [trace],
        }


def _route_after_threshold(state: TicketState) -> str:
    if state["requires_human_review"]:
        return "escalate"
    return "execute"


def build_resolution_subgraph() -> StateGraph:
    """Build and return the resolution subgraph (uncompiled)."""
    builder = StateGraph(TicketState)

    builder.add_node("decide", decide_node)
    builder.add_node("threshold_check", threshold_check_node)
    builder.add_node("execute", execute_node)
    builder.add_node("escalate", escalate_node)

    builder.add_edge(START, "decide")
    builder.add_edge("decide", "threshold_check")
    builder.add_conditional_edges(
        "threshold_check",
        _route_after_threshold,
        {"execute": "execute", "escalate": "escalate"},
    )
    builder.add_edge("execute", END)
    builder.add_edge("escalate", END)

    return builder
```

**Step 4: Run tests**

```bash
pytest tests/test_resolution.py -v
```
Expected: All PASS

**Step 5: Commit**

```bash
git add agentdesk/agents/resolution.py tests/test_resolution.py
git commit -m "feat: add resolution agent subgraph with threshold-based escalation"
```

---

### Task 10: Response Agent

**Files:**
- Create: `agentdesk/agents/response.py`
- Create: `tests/test_response.py`

**Step 1: Write test**

Create `tests/test_response.py`:

```python
from unittest.mock import MagicMock

from agentdesk.agents.response import response_node


def _make_state(tier: str = "standard", urgency: str = "low") -> dict:
    return {
        "ticket_id": "T001",
        "customer_id": "C001",
        "customer_message": "Where is my order ORD-001?",
        "category": "order_issue",
        "urgency": urgency,
        "extracted_entities": {"order_id": "ORD-001"},
        "order_details": {"order_id": "ORD-001", "status": "shipped", "total": 79.99},
        "customer_history": {"tier": tier, "name": "Alice", "total_orders": 5},
        "applicable_policies": [],
        "allowed_actions": ["info_only"],
        "resolution_action": "info_only",
        "resolution_details": {"reason": "Order is in transit"},
        "requires_human_review": False,
        "human_review_reason": None,
        "customer_response": "",
        "internal_notes": "",
        "trace_log": [],
        "status": "resolved",
    }


def test_response_generates_customer_message():
    mock_llm = MagicMock()
    mock_structured = MagicMock()
    mock_llm.with_structured_output.return_value = mock_structured
    mock_structured.invoke.return_value = MagicMock(
        customer_response="Your order ORD-001 is currently shipped and on its way.",
        internal_notes="Customer inquired about order status. No action needed.",
    )

    state = _make_state()
    result = response_node(state, llm=mock_llm)

    assert result["customer_response"] != ""
    assert result["internal_notes"] != ""
    assert len(result["trace_log"]) == 1
    assert result["trace_log"][0]["agent"] == "response"
```

**Step 2: Run test to verify it fails**

```bash
pytest tests/test_response.py -v
```
Expected: FAIL

**Step 3: Write response.py**

Create `agentdesk/agents/response.py`:

```python
from __future__ import annotations

from langchain_core.language_models import BaseChatModel
from langchain_core.messages import HumanMessage, SystemMessage
from pydantic import BaseModel, Field

from agentdesk.llm.provider import get_llm
from agentdesk.models.state import TicketState
from agentdesk.tracing.tracer import create_trace_entry

RESPONSE_SYSTEM_PROMPT = """\
You are a customer support response writer for an e-commerce company.

Write a professional, empathetic, and concise response to the customer.
Also write brief internal notes summarizing the ticket for the support team.

Context:
- Customer name: {customer_name}
- Customer tier: {tier}
- Urgency: {urgency}
- Category: {category}
- Original message: {message}
- Order details: {order_details}
- Resolution action: {resolution_action}
- Resolution details: {resolution_details}

Tone guidelines:
- Always be empathetic and professional
- For VIP customers: use personalized, premium tone
- For high/critical urgency: acknowledge frustration, prioritize reassurance
- Keep responses concise but thorough
- Include specific details (order IDs, dates, amounts) when relevant
"""


class ResponseOutput(BaseModel):
    customer_response: str = Field(description="The customer-facing response message")
    internal_notes: str = Field(description="Internal notes for the support team")


def response_node(state: TicketState, *, llm: BaseChatModel | None = None) -> dict:
    """Generate the customer-facing response and internal notes."""
    llm = llm or get_llm()
    customer = state["customer_history"] or {}
    order = state["order_details"] or {}

    prompt = RESPONSE_SYSTEM_PROMPT.format(
        customer_name=customer.get("name", "Customer"),
        tier=customer.get("tier", "standard"),
        urgency=state["urgency"],
        category=state["category"],
        message=state["customer_message"],
        order_details=order,
        resolution_action=state["resolution_action"],
        resolution_details=state["resolution_details"],
    )

    structured_llm = llm.with_structured_output(ResponseOutput)
    result = structured_llm.invoke([
        SystemMessage(content=prompt),
        HumanMessage(content="Write the response."),
    ])

    trace = create_trace_entry(
        agent="response",
        input_summary=f"action={state['resolution_action']}, tier={customer.get('tier')}",
        output_summary=f"response_length={len(result.customer_response)}",
    )

    return {
        "customer_response": result.customer_response,
        "internal_notes": result.internal_notes,
        "trace_log": [trace],
    }
```

**Step 4: Run tests**

```bash
pytest tests/test_response.py -v
```
Expected: PASS

**Step 5: Commit**

```bash
git add agentdesk/agents/response.py tests/test_response.py
git commit -m "feat: add response agent with tone-aware message generation"
```

---

### Task 11: Supervisor Agent & Full Graph

**Files:**
- Create: `agentdesk/agents/supervisor.py`
- Create: `tests/test_graph.py`

**Step 1: Write test**

Create `tests/test_graph.py`:

```python
from unittest.mock import MagicMock, patch

from agentdesk.agents.supervisor import build_graph, supervisor_node


def test_supervisor_routes_to_triage_first():
    mock_llm = MagicMock()
    mock_structured = MagicMock()
    mock_llm.with_structured_output.return_value = mock_structured
    mock_structured.invoke.return_value = MagicMock(next_agent="triage")

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


def test_build_graph_compiles():
    graph = build_graph()
    assert graph is not None
```

**Step 2: Run test to verify it fails**

```bash
pytest tests/test_graph.py -v
```
Expected: FAIL

**Step 3: Write supervisor.py**

Create `agentdesk/agents/supervisor.py`:

```python
from __future__ import annotations

from typing import Literal

from langchain_core.language_models import BaseChatModel
from langchain_core.messages import HumanMessage, SystemMessage
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.graph import END, START, StateGraph
from langgraph.types import Command
from pydantic import BaseModel, Field

from agentdesk.agents.order_lookup import order_lookup_node
from agentdesk.agents.policy import policy_node
from agentdesk.agents.resolution import build_resolution_subgraph
from agentdesk.agents.response import response_node
from agentdesk.agents.triage import triage_node
from agentdesk.llm.provider import get_llm
from agentdesk.models.state import TicketState
from agentdesk.tracing.tracer import create_trace_entry

SUPERVISOR_SYSTEM_PROMPT = """\
You are a supervisor agent orchestrating a customer support workflow.

Based on the current ticket state, decide which agent should handle the ticket next.

Available agents:
- triage: Classify the ticket (use when category is empty)
- order_lookup: Look up order details (use when order info is needed for the category)
- policy: Evaluate policies (use after order lookup for action-required categories)
- resolution: Decide and execute resolution (use after policy evaluation)
- response: Generate customer response (use when resolution is complete or for simple info requests)
- done: Ticket is fully handled, end the workflow

Current state:
- Category: {category}
- Urgency: {urgency}
- Has order details: {has_order}
- Has policies evaluated: {has_policies}
- Resolution action: {resolution_action}
- Has customer response: {has_response}
- Status: {status}

Rules:
1. Always start with triage if category is empty
2. For product_question: triage → response (skip order/policy/resolution)
3. For order_issue, return_request, billing: triage → order_lookup → policy → resolution → response
4. For complaint: triage → order_lookup → resolution (escalate) → response
5. After response is generated, choose done
6. If status is "resolved" or "escalated" and response exists, choose done
"""


class SupervisorDecision(BaseModel):
    next_agent: Literal[
        "triage", "order_lookup", "policy", "resolution", "response", "done"
    ] = Field(description="The next agent to invoke")
    reasoning: str = Field(description="Brief reasoning for the routing decision")


def supervisor_node(state: TicketState, *, llm: BaseChatModel | None = None) -> dict:
    """Decide which agent to invoke next."""
    llm = llm or get_llm()

    prompt = SUPERVISOR_SYSTEM_PROMPT.format(
        category=state["category"] or "(not yet classified)",
        urgency=state["urgency"] or "(not yet classified)",
        has_order=state["order_details"] is not None,
        has_policies=len(state["applicable_policies"]) > 0,
        resolution_action=state["resolution_action"] or "(none)",
        has_response=bool(state["customer_response"]),
        status=state["status"],
    )

    structured_llm = llm.with_structured_output(SupervisorDecision)
    decision = structured_llm.invoke([
        SystemMessage(content=prompt),
        HumanMessage(content=f"Customer message: {state['customer_message']}"),
    ])

    trace = create_trace_entry(
        agent="supervisor",
        input_summary=f"category={state['category']}, status={state['status']}",
        output_summary=f"next={decision.next_agent}, reason={decision.reasoning}",
    )

    return {
        "trace_log": [trace],
        "next_agent": decision.next_agent,
    }


def _route_from_supervisor(state: dict) -> str:
    next_agent = state.get("next_agent", "done")
    if next_agent == "done":
        return END
    return next_agent


def build_graph(checkpointer=None):
    """Build and compile the full AgentDesk supervisor graph."""

    # We need next_agent in the state for routing — extend TicketState
    class GraphState(TicketState, total=False):
        next_agent: str

    resolution_subgraph = build_resolution_subgraph().compile()

    builder = StateGraph(GraphState)

    # Add nodes
    builder.add_node("supervisor", supervisor_node)
    builder.add_node("triage", triage_node)
    builder.add_node("order_lookup", order_lookup_node)
    builder.add_node("policy", policy_node)
    builder.add_node("resolution", resolution_subgraph)
    builder.add_node("response", response_node)

    # Start → Supervisor
    builder.add_edge(START, "supervisor")

    # Supervisor routes to agents
    builder.add_conditional_edges(
        "supervisor",
        _route_from_supervisor,
        {
            "triage": "triage",
            "order_lookup": "order_lookup",
            "policy": "policy",
            "resolution": "resolution",
            "response": "response",
            END: END,
        },
    )

    # All agents route back to supervisor
    builder.add_edge("triage", "supervisor")
    builder.add_edge("order_lookup", "supervisor")
    builder.add_edge("policy", "supervisor")
    builder.add_edge("resolution", "supervisor")
    builder.add_edge("response", "supervisor")

    if checkpointer is None:
        checkpointer = InMemorySaver()

    return builder.compile(checkpointer=checkpointer)
```

**Step 4: Run tests**

```bash
pytest tests/test_graph.py -v
```
Expected: All PASS

**Step 5: Commit**

```bash
git add agentdesk/agents/supervisor.py tests/test_graph.py
git commit -m "feat: add supervisor agent and compile full LangGraph workflow"
```

---

### Task 12: FastAPI Application & Routes

**Files:**
- Create: `agentdesk/main.py`
- Create: `agentdesk/api/routes.py`
- Create: `tests/test_api.py`

**Step 1: Write test**

Create `tests/test_api.py`:

```python
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
```

**Step 2: Run test to verify it fails**

```bash
pytest tests/test_api.py -v
```
Expected: FAIL

**Step 3: Write routes.py**

Create `agentdesk/api/routes.py`:

```python
from __future__ import annotations

import uuid

from fastapi import APIRouter, HTTPException
from langgraph.types import Command

from agentdesk.agents.supervisor import build_graph
from agentdesk.models.schemas import (
    HumanReviewRequest,
    HumanReviewResponse,
    TicketListResponse,
    TicketRequest,
    TicketResponse,
    TraceResponse,
)

router = APIRouter()

# In-memory ticket store and graph instance
_tickets: dict[str, dict] = {}
_graph = None


def get_graph():
    global _graph
    if _graph is None:
        _graph = build_graph()
    return _graph


def _initial_state(ticket_id: str, request: TicketRequest) -> dict:
    return {
        "ticket_id": ticket_id,
        "customer_id": request.customer_id,
        "customer_message": request.message,
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


@router.post("/tickets", response_model=TicketResponse)
def create_ticket(request: TicketRequest):
    ticket_id = f"T-{uuid.uuid4().hex[:8].upper()}"
    config = {"configurable": {"thread_id": ticket_id}}

    graph = get_graph()
    initial_state = _initial_state(ticket_id, request)

    result = graph.invoke(initial_state, config=config)

    _tickets[ticket_id] = {
        "config": config,
        "result": result,
    }

    return TicketResponse(
        ticket_id=ticket_id,
        status=result.get("status", "processing"),
        category=result.get("category"),
        urgency=result.get("urgency"),
        resolution_action=result.get("resolution_action"),
        customer_response=result.get("customer_response"),
        internal_notes=result.get("internal_notes"),
    )


@router.get("/tickets", response_model=TicketListResponse)
def list_tickets(status: str | None = None, category: str | None = None):
    tickets = []
    for tid, data in _tickets.items():
        result = data["result"]
        if status and result.get("status") != status:
            continue
        if category and result.get("category") != category:
            continue
        tickets.append(
            TicketResponse(
                ticket_id=tid,
                status=result.get("status", "unknown"),
                category=result.get("category"),
                urgency=result.get("urgency"),
                resolution_action=result.get("resolution_action"),
                customer_response=result.get("customer_response"),
                internal_notes=result.get("internal_notes"),
            )
        )
    return TicketListResponse(tickets=tickets)


@router.get("/tickets/{ticket_id}", response_model=TicketResponse)
def get_ticket(ticket_id: str):
    if ticket_id not in _tickets:
        raise HTTPException(status_code=404, detail="Ticket not found")

    result = _tickets[ticket_id]["result"]
    return TicketResponse(
        ticket_id=ticket_id,
        status=result.get("status", "unknown"),
        category=result.get("category"),
        urgency=result.get("urgency"),
        resolution_action=result.get("resolution_action"),
        customer_response=result.get("customer_response"),
        internal_notes=result.get("internal_notes"),
    )


@router.get("/tickets/{ticket_id}/trace", response_model=TraceResponse)
def get_ticket_trace(ticket_id: str):
    if ticket_id not in _tickets:
        raise HTTPException(status_code=404, detail="Ticket not found")

    result = _tickets[ticket_id]["result"]
    return TraceResponse(
        ticket_id=ticket_id,
        trace_log=result.get("trace_log", []),
    )


@router.post("/tickets/{ticket_id}/review", response_model=HumanReviewResponse)
def review_ticket(ticket_id: str, review: HumanReviewRequest):
    if ticket_id not in _tickets:
        raise HTTPException(status_code=404, detail="Ticket not found")

    ticket_data = _tickets[ticket_id]
    config = ticket_data["config"]

    graph = get_graph()

    resume_value = {"action": review.action}
    if review.modified_response:
        resume_value["modified_response"] = review.modified_response

    result = graph.invoke(Command(resume=resume_value), config=config)

    ticket_data["result"] = result

    return HumanReviewResponse(
        ticket_id=ticket_id,
        status=result.get("status", "unknown"),
    )
```

**Step 4: Write main.py**

Create `agentdesk/main.py`:

```python
from fastapi import FastAPI

from agentdesk.api.routes import router
from agentdesk.tracing.tracer import setup_langsmith_tracing

setup_langsmith_tracing()

app = FastAPI(
    title="AgentDesk",
    description="Agentic e-commerce customer support system",
    version="0.1.0",
)

app.include_router(router)


@app.get("/health")
def health():
    return {"status": "ok", "service": "agentdesk"}
```

**Step 5: Run tests**

```bash
pytest tests/test_api.py -v
```
Expected: All PASS

**Step 6: Commit**

```bash
git add agentdesk/main.py agentdesk/api/routes.py tests/test_api.py
git commit -m "feat: add FastAPI app with ticket CRUD and human review endpoints"
```

---

### Task 13: Integration Test (End-to-End)

**Files:**
- Create: `tests/test_integration.py`

**Step 1: Write integration test**

Create `tests/test_integration.py`:

```python
"""End-to-end integration tests using mocked LLM responses.

These tests verify the full graph flow — supervisor routing through all agents —
without making real LLM calls.
"""
from unittest.mock import MagicMock, patch

from agentdesk.agents.supervisor import build_graph


def _mock_llm_factory():
    """Create a mock LLM that returns appropriate structured outputs based on the prompt."""
    mock_llm = MagicMock()

    call_count = {"n": 0}

    def mock_with_structured_output(schema):
        mock_structured = MagicMock()

        def mock_invoke(messages):
            call_count["n"] += 1
            schema_name = schema.__name__

            if schema_name == "SupervisorDecision":
                # Supervisor routing sequence
                n = call_count["n"]
                if n == 1:
                    return MagicMock(next_agent="triage", reasoning="Start with triage")
                elif n == 3:
                    return MagicMock(next_agent="order_lookup", reasoning="Need order details")
                elif n == 4:
                    return MagicMock(next_agent="policy", reasoning="Check policies")
                elif n == 6:
                    return MagicMock(next_agent="resolution", reasoning="Apply resolution")
                elif n == 9:
                    return MagicMock(next_agent="response", reasoning="Generate response")
                else:
                    return MagicMock(next_agent="done", reasoning="Complete")

            elif schema_name == "TriageOutput":
                return MagicMock(
                    category="return_request",
                    urgency="medium",
                    extracted_entities={"order_id": "ORD-001"},
                )

            elif schema_name == "PolicyOutput":
                return MagicMock(
                    applicable_policies=["30-day return window", "Auto-refund up to $100 for premium"],
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
                    customer_response="We've processed your refund of $40.00 for order ORD-001.",
                    internal_notes="Refund processed automatically within premium tier limits.",
                )

            return MagicMock()

        mock_structured.invoke = mock_invoke
        return mock_structured

    mock_llm.with_structured_output = mock_with_structured_output
    return mock_llm


@patch("agentdesk.agents.triage.get_llm")
@patch("agentdesk.agents.policy.get_llm")
@patch("agentdesk.agents.resolution.get_llm")
@patch("agentdesk.agents.response.get_llm")
@patch("agentdesk.agents.supervisor.get_llm")
def test_full_return_request_flow(
    mock_sup_llm, mock_res_llm, mock_resp_llm, mock_pol_llm, mock_tri_llm
):
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

    # Verify the full flow completed
    assert result["category"] == "return_request"
    assert result["urgency"] == "medium"
    assert result["resolution_action"] == "refund"
    assert result["customer_response"] != ""
    assert result["status"] == "resolved"

    # Verify trace log captured all agents
    agents_in_trace = [entry["agent"] for entry in result["trace_log"]]
    assert "supervisor" in agents_in_trace
    assert "triage" in agents_in_trace
    assert "order_lookup" in agents_in_trace
    assert "response" in agents_in_trace
```

**Step 2: Run integration test**

```bash
pytest tests/test_integration.py -v
```
Expected: PASS (may need adjustment to mock call counts — tweak the supervisor call sequence if needed)

**Step 3: Run full test suite**

```bash
pytest tests/ -v
```
Expected: All PASS

**Step 4: Commit**

```bash
git add tests/test_integration.py
git commit -m "feat: add end-to-end integration test with mocked LLM flow"
```

---

### Task 14: Final Polish

**Step 1: Verify all tests pass**

```bash
pytest tests/ -v --tb=short
```
Expected: All PASS

**Step 2: Test the server starts**

```bash
cd /Users/shrikantvarma/Code/Learn/AgenticSystems
uvicorn agentdesk.main:app --port 8000 &
curl http://localhost:8000/health
# Expected: {"status":"ok","service":"agentdesk"}
kill %1
```

**Step 3: Final commit with any fixes**

```bash
git add -A
git commit -m "chore: final polish and verify all tests pass"
```
