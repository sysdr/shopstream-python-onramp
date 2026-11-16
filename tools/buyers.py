"""N buyers try to buy the same product at the same moment."""
import threading
import uuid

import api


def new_product(stock):
    sku = f"SKU-{uuid.uuid4().int % 900000 + 100000}"
    s, p = api.call("POST", "/products", {"sku": sku, "name": "Limited sneaker drop", "price": "180.00", "stock": stock})
    assert s == 201, p
    return sku, p["id"]


def rush(sku, buyers, mode):
    codes = []
    gate = threading.Barrier(buyers)

    def buy(i):
        gate.wait()
        codes.append(api.call("POST", f"/orders?mode={mode}", {"sku": sku, "qty": 1, "customer": f"buyer-{i}"}, timeout=30)[0])

    threads = [threading.Thread(target=buy, args=(i,)) for i in range(buyers)]
    [t.start() for t in threads]
    [t.join() for t in threads]
    return codes


def run(mode, stock=10, buyers=50):
    sku, pid = new_product(stock)
    codes = rush(sku, buyers, mode)
    sales = api.call("GET", f"/products/{pid}/sales")[1]
    accepted = codes.count(201)
    return {"mode": mode, "stock": stock, "buyers": buyers, "accepted": accepted, "rejected": codes.count(409),
            "errors": len(codes) - accepted - codes.count(409), "stock_left": sales["stock"], "orders": sales["orders"],
            "oversold": max(0, sales["sold"] - stock)}
