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
