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

    order_details = None
    if order_id:
        order_details = store.get_order(order_id)

    if order_details is None:
        orders = store.get_orders_by_customer(customer_id)
        if orders:
            order_details = orders[-1]

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
