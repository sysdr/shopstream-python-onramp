"""Day 6 checks: production settings are on and the demo-only endpoints are off."""
import api

if not api.wait_healthy(path="/health/ready"):
    api.fail("the API did not report ready")
s, r = api.call("GET", "/health/ready")
print(f"[VERIFY] GET /health/ready -> {s} {r}")
unsafe = api.call("GET", "/products/search-unsafe?q=x")[0]
naive = api.call("POST", "/orders?mode=naive", {"sku": "SKU-1001", "qty": 1, "customer": "verify"})[0]
print(f"[VERIFY] demo endpoints in production: search-unsafe -> {unsafe}, orders?mode=naive -> {naive}")
if unsafe != 404 or naive != 404:
    api.fail("demo endpoints must be off in production")
s, o = api.call("POST", "/orders", {"sku": "SKU-1002", "qty": 1, "customer": "verify", "discount_code": "SAVE10"})
print(f"[VERIFY] a real order still works -> {s} total {o.get('total') if isinstance(o, dict) else o}")
if s != 201:
    api.fail("orders should work in production")
