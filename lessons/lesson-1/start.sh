#!/usr/bin/env bash
# ShopStream API — Day 1: Your first API in 20 minutes
# Writes the project into ./shopstream-api, builds it and starts it with Docker Compose,
# runs the tests, writes verify.sh, verifies, then runs the demo. Stop with: bash stop.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$ROOT/shopstream-api"
export COMPOSE_PROJECT_NAME=shopstream-api
cd "$ROOT"
say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
command -v docker >/dev/null || { echo "[ERROR] docker not found. Install Docker Desktop (Windows/macOS) or Docker Engine (Linux)."; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "[ERROR] 'docker compose' not available. Update Docker."; exit 1; }
docker info >/dev/null 2>&1 || { echo "[ERROR] the Docker engine is not running. Start Docker Desktop and try again."; exit 1; }

say "Writing the project into ./shopstream-api"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/."
cat > "$PROJECT_DIR/Dockerfile" <<'SHOPSTREAM_EOF'
FROM python:3.12-slim
WORKDIR /srv
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/ app/
COPY tests/ tests/
COPY tools/ tools/
ENV PYTHONUNBUFFERED=1
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/."
cat > "$PROJECT_DIR/compose.yaml" <<'SHOPSTREAM_EOF'
# ShopStream API, Day 1: one FastAPI service. No bind mounts: the code is built into the image.
services:
  api:
    build: .
    image: shopstream-api:day1
    ports: ["8201:8000"]
  tools:
    image: shopstream-api:day1
    profiles: ["tools"]
    working_dir: /srv/tools
    depends_on: [api]
    command: ["python", "-c", "print('tools')"]
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/."
cat > "$PROJECT_DIR/requirements.txt" <<'SHOPSTREAM_EOF'
fastapi==0.115.6
uvicorn==0.34.0
httpx==0.28.1
pytest==8.3.4
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/app"
cat > "$PROJECT_DIR/app/__init__.py" <<'SHOPSTREAM_EOF'

SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/app"
cat > "$PROJECT_DIR/app/main.py" <<'SHOPSTREAM_EOF'
"""ShopStream API, Day 1: a product catalog served by FastAPI.

The products live in a Python dict for now (Day 2 moves them to Postgres).
FastAPI turns the type hints into request validation and into the docs at /docs.
"""
from decimal import Decimal

from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field

app = FastAPI(title="ShopStream API", version="0.1.0")


class ProductIn(BaseModel):
    sku: str = Field(pattern=r"^SKU-[0-9]{1,6}$", examples=["SKU-1001"])
    name: str = Field(min_length=1, max_length=120)
    price: Decimal = Field(gt=0, max_digits=8, decimal_places=2)
    stock: int = Field(ge=0)


class Product(ProductIn):
    id: int


PRODUCTS: dict[int, Product] = {}


def seed():
    PRODUCTS.clear()
    for i, (name, price, stock) in enumerate([
        ("Trail running shoes", "89.00", 25), ("Merino socks", "14.50", 120), ("Rain jacket", "129.99", 12),
        ("Water bottle", "19.99", 60), ("Head torch", "34.00", 40)], start=1):
        PRODUCTS[i] = Product(id=i, sku=f"SKU-{1000 + i}", name=name, price=Decimal(price), stock=stock)


seed()


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/products", response_model=list[Product])
def list_products(limit: int = Query(20, ge=1, le=100), offset: int = Query(0, ge=0)):
    items = sorted(PRODUCTS.values(), key=lambda p: p.id)
    return items[offset:offset + limit]


@app.get("/products/{product_id}", response_model=Product)
def get_product(product_id: int):
    if product_id not in PRODUCTS:
        raise HTTPException(status_code=404, detail="product not found")
    return PRODUCTS[product_id]


@app.post("/products", response_model=Product, status_code=201)
def create_product(body: ProductIn):
    if any(p.sku == body.sku for p in PRODUCTS.values()):
        raise HTTPException(status_code=409, detail=f"{body.sku} already exists")
    new_id = max(PRODUCTS, default=0) + 1
    PRODUCTS[new_id] = Product(id=new_id, **body.model_dump())
    return PRODUCTS[new_id]
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/tests"
cat > "$PROJECT_DIR/tests/__init__.py" <<'SHOPSTREAM_EOF'

SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/tests"
cat > "$PROJECT_DIR/tests/test_api.py" <<'SHOPSTREAM_EOF'
from fastapi.testclient import TestClient

from app.main import app, seed

client = TestClient(app)


def setup_function():
    seed()


def test_list_products():
    r = client.get("/products")
    assert r.status_code == 200
    assert [p["sku"] for p in r.json()][:2] == ["SKU-1001", "SKU-1002"]


def test_create_and_get():
    r = client.post("/products", json={"sku": "SKU-2001", "name": "Gaiters", "price": "24.00", "stock": 8})
    assert r.status_code == 201
    pid = r.json()["id"]
    assert client.get(f"/products/{pid}").json()["name"] == "Gaiters"


def test_validation_and_errors():
    assert client.post("/products", json={"sku": "bad", "name": "x", "price": "-5", "stock": 1}).status_code == 422
    assert client.post("/products", json={"sku": "SKU-1001", "name": "dup", "price": "1.00", "stock": 1}).status_code == 409
    assert client.get("/products/999").status_code == 404
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/tools"
cat > "$PROJECT_DIR/tools/api.py" <<'SHOPSTREAM_EOF'
"""Small HTTP helpers for the demo and the checks (standard library only)."""
import json
import os
import sys
import time
import urllib.error
import urllib.request

API = os.environ.get("API_URL", "http://api:8000")


def call(method, path, body=None, timeout=10, base=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request((base or API) + path, data=data, method=method, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, raw.decode(errors="replace")


def wait_healthy(timeout=60, path="/health"):
    end = time.time() + timeout
    while time.time() < end:
        try:
            if call("GET", path, timeout=2)[0] == 200:
                return True
        except OSError:
            pass
        time.sleep(0.5)
    return False


def pct(values, p):
    v = sorted(values)
    import math
    return v[min(len(v) - 1, max(0, math.ceil(p / 100 * len(v)) - 1))]


def fail(msg):
    print(f"[FAIL] {msg}")
    sys.exit(1)
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/tools"
cat > "$PROJECT_DIR/tools/checks.py" <<'SHOPSTREAM_EOF'
"""Day 1 checks: the API lists, creates and validates products."""
import uuid

import api

if not api.wait_healthy():
    api.fail("the API did not answer /health")
s, items = api.call("GET", "/products")
print(f"[VERIFY] GET /products -> {s}, {len(items)} products")
if s != 200 or len(items) < 5:
    api.fail("GET /products should return the 5 seeded products")
sku = f"SKU-{uuid.uuid4().int % 900000 + 100000}"
s, p = api.call("POST", "/products", {"sku": sku, "name": "Verify item", "price": "9.99", "stock": 3})
print(f"[VERIFY] POST /products -> {s} id={p.get('id') if isinstance(p, dict) else p}")
if s != 201 or api.call("GET", f"/products/{p['id']}")[1]["sku"] != sku:
    api.fail("a created product should be readable at /products/{id}")
s, err = api.call("POST", "/products", {"sku": "nope", "name": "", "price": "-1", "stock": -2})
fields = sorted({e["loc"][-1] for e in err["detail"]}) if s == 422 else []
print(f"[VERIFY] invalid product -> {s}, rejected fields {fields}")
if s != 422 or fields != ["name", "price", "sku", "stock"]:
    api.fail("an invalid product should be rejected with 422 naming every bad field")
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/tools"
cat > "$PROJECT_DIR/tools/demo.py" <<'SHOPSTREAM_EOF'
"""Day 1 demo: the first request, a burst of requests, and what validation buys you."""
import json
import time

import api

t0 = time.perf_counter()
ok = api.wait_healthy()
s, items = api.call("GET", "/products?limit=3")
print(f"1) First request: GET /products?limit=3 -> {s} in {(time.perf_counter() - t0) * 1000:.0f} ms (including waiting for start-up)")
for p in items:
    print(f"   {p['id']}  {p['sku']}  {p['name']:22} {p['price']:>7}  stock {p['stock']}")

lat = []
for i in range(200):
    t = time.perf_counter(); api.call("GET", f"/products/{i % 5 + 1}"); lat.append((time.perf_counter() - t) * 1000)
print(f"\n2) 200 more requests, one at a time: p50 {api.pct(lat, 50):.1f} ms, p99 {api.pct(lat, 99):.1f} ms")

print("\n3) A bad request never reaches your code:")
bad = {"sku": "shoe", "name": "", "price": "-5", "stock": 3}
s, err = api.call("POST", "/products", bad)
print(f"   POST /products {json.dumps(bad)} -> {s}")
for e in err["detail"]:
    print(f"   - {e['loc'][-1]}: {e['msg']}")
s, p = api.call("POST", "/products", {"sku": "SKU-1006", "name": "Trekking poles", "price": "59.00", "stock": 15})
print(f"   A good one -> {s}, id {p['id'] if s == 201 else p}")
s, p = api.call("POST", "/products", {"sku": "SKU-1006", "name": "Trekking poles", "price": "59.00", "stock": 15})
print(f"   The same SKU again -> {s} {p['detail']}")
print("\nOpen http://localhost:8201/docs for the interactive API docs FastAPI generated.")
SHOPSTREAM_EOF

cd "$PROJECT_DIR"
say "Build the image and start the stack"
docker compose --profile public down --remove-orphans -v >/dev/null 2>&1 || true
docker compose --profile tools build -q
docker compose up -d 2>&1 | grep -v -E '^ *(#|=>)' | tail -12
docker compose run --rm -T tools python -c "import api,sys; sys.exit(0 if api.wait_healthy(120) else 1)" || { echo "[ERROR] the API did not become healthy:"; docker compose logs --tail 40 api; exit 1; }
echo "[INFO] stack is up: $(docker compose ps --services --status running | tr '\n' ' ')"
say "Tests"
TESTS="$(docker compose run --rm -T -w /srv tools python -m pytest -q -p no:cacheprovider 2>&1)" || { echo "$TESTS" | tail -40; echo "[ERROR] tests failed"; exit 1; }
echo "$TESTS" | tail -3

cat > "$ROOT/verify.sh" <<'VERIFY_EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)/shopstream-api"
export COMPOSE_PROJECT_NAME=shopstream-api
OUT="$(docker compose run --rm -T tools python checks.py)" || { echo "$OUT"; exit 1; }
echo "$OUT"
echo "PASS  Lesson 1 complete. Your completion code: SHOP0-FIRSTAPI-5N2K"
VERIFY_EOF
chmod +x "$ROOT/verify.sh"

say "Verify"
bash "$ROOT/verify.sh"

say "Demo"
docker compose run --rm -T tools python demo.py

say "Done"
echo "API: http://localhost:8201/products    Interactive docs: http://localhost:8201/docs"
echo "Run bash verify.sh for your completion code, bash stop.sh when you are finished."
