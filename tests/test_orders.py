import threading
import uuid


def new_product(client, stock):
    sku = f"SKU-{uuid.uuid4().int % 900000 + 100000}"
    p = client.post("/products", json={"sku": sku, "name": "Limited edition", "price": "50.00", "stock": stock}).json()
    return sku, p["id"]


def test_order_takes_stock(client):
    sku, pid = new_product(client, 3)
    r = client.post("/orders", json={"sku": sku, "qty": 2, "customer": "ana"})
    assert r.status_code == 201 and r.json()["stock_left"] == 1
    assert client.post("/orders", json={"sku": sku, "qty": 2, "customer": "ben"}).status_code == 409
    assert client.get(f"/products/{pid}/sales").json() == {"sku": sku, "stock": 1, "sold": 2, "orders": 1}


def test_concurrent_buyers_never_oversell(client):
    sku, pid = new_product(client, 5)
    codes = []

    def buy(i):
        codes.append(client.post("/orders", json={"sku": sku, "qty": 1, "customer": f"c{i}"}).status_code)

    threads = [threading.Thread(target=buy, args=(i,)) for i in range(20)]
    [t.start() for t in threads]
    [t.join() for t in threads]
    assert codes.count(201) == 5 and codes.count(409) == 15
    s = client.get(f"/products/{pid}/sales").json()
    assert s["stock"] == 0 and s["sold"] == 5


def test_quote_endpoint_uses_database_prices(client):
    r = client.post("/cart/quote", json={"lines": [{"sku": "SKU-1002", "qty": 2}], "discount_code": "FLAT5"})
    assert r.status_code == 200
    assert r.json() == {"subtotal": "29.00", "discount": "5.00", "tax": "1.98", "total": "25.98"}
    assert client.post("/cart/quote", json={"lines": [{"sku": "SKU-1002", "qty": 1}], "discount_code": "NOPE"}).status_code == 422


def test_order_stores_its_total(client):
    sku, pid = new_product(client, 2)
    r = client.post("/orders", json={"sku": sku, "qty": 1, "customer": "ana", "discount_code": "SAVE10"})
    assert r.status_code == 201 and r.json()["total"] == "48.71"
