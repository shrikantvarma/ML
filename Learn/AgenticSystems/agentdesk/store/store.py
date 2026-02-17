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
