#!/usr/bin/env bash
# ShopStream API — Day 3: Orders without overselling
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
COPY migrations/ migrations/
COPY tests/ tests/
COPY tools/ tools/
ENV PYTHONUNBUFFERED=1
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/."
cat > "$PROJECT_DIR/compose.yaml" <<'SHOPSTREAM_EOF'
# ShopStream API, Day 3: FastAPI + Postgres, orders. No bind mounts: the code is built into the image.
services:
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: shop
      POSTGRES_PASSWORD: shop-local-only
      POSTGRES_DB: shopstream
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U shop -d shopstream"]
      interval: 2s
      timeout: 3s
      retries: 30
  api:
    build: .
    image: shopstream-api:day3
    environment:
      DATABASE_URL: postgresql://shop:shop-local-only@db:5432/shopstream
      ALLOW_DEMO_ENDPOINTS: "1"
    depends_on:
      db: {condition: service_healthy}
    ports: ["8201:8000"]
  tools:
    image: shopstream-api:day3
    profiles: ["tools"]
    working_dir: /srv/tools
    environment:
      DATABASE_URL: postgresql://shop:shop-local-only@db:5432/shopstream
    depends_on: [api]
    command: ["python", "-c", "print('tools')"]
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/."
cat > "$PROJECT_DIR/requirements.txt" <<'SHOPSTREAM_EOF'
fastapi==0.115.6
uvicorn==0.34.0
httpx==0.28.1
pytest==8.3.4
psycopg[binary]==3.2.3
psycopg-pool==3.2.4
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/app"
cat > "$PROJECT_DIR/app/__init__.py" <<'SHOPSTREAM_EOF'

SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/app"
cat > "$PROJECT_DIR/app/config.py" <<'SHOPSTREAM_EOF'
import os

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://shop:shop-local-only@localhost:5432/shopstream")
ALLOW_DEMO_ENDPOINTS = os.environ.get("ALLOW_DEMO_ENDPOINTS") == "1"
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/app"
cat > "$PROJECT_DIR/app/db.py" <<'SHOPSTREAM_EOF'
"""One connection pool per process. Every request borrows a connection and gives it back."""
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from app.config import DATABASE_URL

pool = ConnectionPool(DATABASE_URL, min_size=1, max_size=20, open=False, kwargs={"row_factory": dict_row})
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/app"
cat > "$PROJECT_DIR/app/main.py" <<'SHOPSTREAM_EOF'
"""ShopStream API, Day 3: orders that never oversell.

Every query passes user input as a parameter (%s), never by building the SQL string.
The /products/search-unsafe endpoint exists only to show what goes wrong if you do;
it is switched on by ALLOW_DEMO_ENDPOINTS=1 and removed before production (Day 6).
"""
from contextlib import asynccontextmanager
from decimal import Decimal

import time

import psycopg
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field

from app import migrate
from app.config import ALLOW_DEMO_ENDPOINTS
from app.db import pool


@asynccontextmanager
async def lifespan(app):
    migrate.migrate()
    pool.open(wait=True)
    yield
    pool.close()


app = FastAPI(title="ShopStream API", version="0.3.0", lifespan=lifespan)


class ProductIn(BaseModel):
    sku: str = Field(pattern=r"^SKU-[0-9]{1,6}$", examples=["SKU-1001"])
    name: str = Field(min_length=1, max_length=120)
    price: Decimal = Field(gt=0, max_digits=8, decimal_places=2)
    stock: int = Field(ge=0)


class Product(ProductIn):
    id: int


class OrderIn(BaseModel):
    sku: str = Field(pattern=r"^SKU-[0-9]{1,6}$")
    qty: int = Field(gt=0, le=10)
    customer: str = Field(min_length=1, max_length=60)


class Order(BaseModel):
    id: int
    sku: str
    qty: int
    stock_left: int


COLS = "id, sku, name, price, stock"


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/products", response_model=list[Product])
def list_products(limit: int = Query(20, ge=1, le=100), offset: int = Query(0, ge=0)):
    with pool.connection() as conn:
        return conn.execute(f"SELECT {COLS} FROM products ORDER BY id LIMIT %s OFFSET %s", (limit, offset)).fetchall()


@app.get("/products/search", response_model=list[Product])
def search(q: str = Query(min_length=1, max_length=60)):
    with pool.connection() as conn:
        return conn.execute(f"SELECT {COLS} FROM products WHERE name ILIKE %s ORDER BY id LIMIT 50", (f"%{q}%",)).fetchall()


@app.get("/products/search-unsafe")
def search_unsafe(q: str):
    """DON'T DO THIS: the input becomes part of the SQL text."""
    if not ALLOW_DEMO_ENDPOINTS:
        raise HTTPException(status_code=404)
    with pool.connection() as conn:
        rows = conn.execute(f"SELECT id, sku, name, price::text AS price, stock FROM products WHERE name ILIKE '%{q}%' ORDER BY id").fetchall()
    return rows


@app.get("/products/{product_id}", response_model=Product)
def get_product(product_id: int):
    with pool.connection() as conn:
        row = conn.execute(f"SELECT {COLS} FROM products WHERE id = %s", (product_id,)).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="product not found")
    return row


@app.post("/products", response_model=Product, status_code=201)
def create_product(body: ProductIn):
    try:
        with pool.connection() as conn:
            return conn.execute(f"INSERT INTO products (sku, name, price, stock) VALUES (%s, %s, %s, %s) RETURNING {COLS}",
                                (body.sku, body.name, body.price, body.stock)).fetchone()
    except psycopg.errors.UniqueViolation:
        raise HTTPException(status_code=409, detail=f"{body.sku} already exists")


class SoldOut(Exception):
    pass


def place_order_atomic(conn, body: OrderIn):
    """One statement checks and takes the stock, so two buyers can't both get the last item."""
    row = conn.execute("UPDATE products SET stock = stock - %s WHERE sku = %s AND stock >= %s RETURNING id, stock",
                       (body.qty, body.sku, body.qty)).fetchone()
    if not row:
        raise SoldOut()
    return row["id"], row["stock"]


def place_order_naive(conn, body: OrderIn):
    """DON'T DO THIS: read, decide in Python, then write. Another request can run between the read and the write."""
    row = conn.execute("SELECT id, stock FROM products WHERE sku = %s", (body.sku,)).fetchone()
    if not row or row["stock"] < body.qty:
        raise SoldOut()
    time.sleep(0.05)  # stands in for real work between the read and the write (checking a coupon, calling payments)
    conn.execute("UPDATE products SET stock = %s WHERE id = %s", (row["stock"] - body.qty, row["id"]))
    return row["id"], row["stock"] - body.qty


@app.post("/orders", response_model=Order, status_code=201)
def create_order(body: OrderIn, mode: str = Query("atomic", pattern="^(atomic|naive)$")):
    if mode == "naive" and not ALLOW_DEMO_ENDPOINTS:
        raise HTTPException(status_code=404)
    place = place_order_naive if mode == "naive" else place_order_atomic
    with pool.connection() as conn:          # one transaction: the stock change and the order row commit together
        try:
            product_id, left = place(conn, body)
        except SoldOut:
            raise HTTPException(status_code=409, detail=f"not enough stock for {body.sku}")
        oid = conn.execute("INSERT INTO orders (product_id, qty, customer) VALUES (%s, %s, %s) RETURNING id",
                           (product_id, body.qty, body.customer)).fetchone()["id"]
    return Order(id=oid, sku=body.sku, qty=body.qty, stock_left=left)


@app.get("/products/{product_id}/sales")
def sales(product_id: int):
    with pool.connection() as conn:
        row = conn.execute("""SELECT p.sku, p.stock, coalesce(sum(o.qty), 0)::int AS sold, count(o.id)::int AS orders
                              FROM products p LEFT JOIN orders o ON o.product_id = p.id WHERE p.id = %s GROUP BY p.id""",
                           (product_id,)).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="product not found")
    return row
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/app"
cat > "$PROJECT_DIR/app/migrate.py" <<'SHOPSTREAM_EOF'
"""Apply migrations/NNN_*.sql in order, once each, recording them in schema_migrations.

Run on start-up (and by hand with: python -m app.migrate). Each file runs in its own transaction,
so a failing migration leaves the database as it was before that file.
"""
import pathlib
import sys

import psycopg

from app.config import DATABASE_URL

MIGRATIONS = pathlib.Path(__file__).resolve().parent.parent / "migrations"


def migrate(url=None):
    applied_now = []
    with psycopg.connect(url or DATABASE_URL, autocommit=True) as conn:
        conn.execute("CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())")
        conn.execute("SELECT pg_advisory_lock(4242)")  # two instances starting together must not both migrate
        try:
            done = {r[0] for r in conn.execute("SELECT version FROM schema_migrations")}
            for f in sorted(MIGRATIONS.glob("*.sql")):
                if f.stem in done:
                    continue
                with conn.transaction():
                    conn.execute(f.read_text())
                    conn.execute("INSERT INTO schema_migrations (version) VALUES (%s)", (f.stem,))
                applied_now.append(f.stem)
        finally:
            conn.execute("SELECT pg_advisory_unlock(4242)")
    return applied_now


if __name__ == "__main__":
    print("applied:", migrate() or "nothing new")
    sys.exit(0)
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/migrations"
cat > "$PROJECT_DIR/migrations/001_products.sql" <<'SHOPSTREAM_EOF'
CREATE TABLE products (
    id     BIGSERIAL PRIMARY KEY,
    sku    TEXT NOT NULL UNIQUE,
    name   TEXT NOT NULL,
    price  NUMERIC(8, 2) NOT NULL CHECK (price > 0),
    stock  INTEGER NOT NULL CHECK (stock >= 0)
);

INSERT INTO products (sku, name, price, stock) VALUES
    ('SKU-1001', 'Trail running shoes', 89.00, 25),
    ('SKU-1002', 'Merino socks', 14.50, 120),
    ('SKU-1003', 'Rain jacket', 129.99, 12),
    ('SKU-1004', 'Water bottle', 19.99, 60),
    ('SKU-1005', 'Head torch', 34.00, 40);
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/migrations"
cat > "$PROJECT_DIR/migrations/002_products_name_index.sql" <<'SHOPSTREAM_EOF'
-- Searching by name is the most common query; an index on lower(name) serves exact, case-insensitive lookups.
CREATE INDEX products_lower_name_idx ON products (lower(name));
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/migrations"
cat > "$PROJECT_DIR/migrations/003_orders.sql" <<'SHOPSTREAM_EOF'
CREATE TABLE orders (
    id          BIGSERIAL PRIMARY KEY,
    product_id  BIGINT NOT NULL REFERENCES products (id),
    qty         INTEGER NOT NULL CHECK (qty > 0),
    customer    TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX orders_product_idx ON orders (product_id);
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/tests"
cat > "$PROJECT_DIR/tests/__init__.py" <<'SHOPSTREAM_EOF'

SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/tests"
cat > "$PROJECT_DIR/tests/conftest.py" <<'SHOPSTREAM_EOF'
"""Tests run against a throwaway database, shopstream_test, created fresh for each test session."""
import os

import psycopg
import pytest

BASE = os.environ.get("DATABASE_URL", "postgresql://shop:shop-local-only@db:5432/shopstream")
TEST_URL = BASE.rsplit("/", 1)[0] + "/shopstream_test"
os.environ["DATABASE_URL"] = TEST_URL


@pytest.fixture(scope="session", autouse=True)
def test_database():
    with psycopg.connect(BASE, autocommit=True) as conn:
        conn.execute("DROP DATABASE IF EXISTS shopstream_test WITH (FORCE)")
        conn.execute("CREATE DATABASE shopstream_test")
    yield TEST_URL


@pytest.fixture(scope="session")
def client(test_database):
    from fastapi.testclient import TestClient
    from app.main import app
    with TestClient(app) as c:
        yield c
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/tests"
cat > "$PROJECT_DIR/tests/test_api.py" <<'SHOPSTREAM_EOF'
import uuid


def sku():
    return f"SKU-{uuid.uuid4().int % 900000 + 100000}"


def test_list_products(client):
    r = client.get("/products")
    assert r.status_code == 200
    assert [p["sku"] for p in r.json()][:2] == ["SKU-1001", "SKU-1002"]


def test_create_and_get(client):
    r = client.post("/products", json={"sku": sku(), "name": "Gaiters", "price": "24.00", "stock": 8})
    assert r.status_code == 201
    assert client.get(f"/products/{r.json()['id']}").json()["name"] == "Gaiters"


def test_validation_and_errors(client):
    assert client.post("/products", json={"sku": "bad", "name": "x", "price": "-5", "stock": 1}).status_code == 422
    assert client.post("/products", json={"sku": "SKU-1001", "name": "dup", "price": "1.00", "stock": 1}).status_code == 409
    assert client.get("/products/999999").status_code == 404


def test_search_treats_input_as_data(client):
    assert [p["name"] for p in client.get("/products/search", params={"q": "jacket"}).json()] == ["Rain jacket"]
    assert client.get("/products/search", params={"q": "x' OR '1'='1"}).json() == []


def test_migrations_are_recorded_once(test_database):
    from app import migrate
    assert migrate.migrate(test_database) == []  # already applied when the app started
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/tests"
cat > "$PROJECT_DIR/tests/test_orders.py" <<'SHOPSTREAM_EOF'
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
DATABASE_URL = os.environ.get("DATABASE_URL", "")
from urllib.parse import quote  # noqa: E402


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
cat > "$PROJECT_DIR/tools/buyers.py" <<'SHOPSTREAM_EOF'
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
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/tools"
cat > "$PROJECT_DIR/tools/checks.py" <<'SHOPSTREAM_EOF'
"""Day 3 checks: concurrent orders never oversell, and the order and the stock change commit together."""
import api
import buyers

if not api.wait_healthy():
    api.fail("the API did not answer /health")
r = buyers.run("atomic", stock=5, buyers=30)
print(f"[VERIFY] 30 buyers, stock 5: accepted {r['accepted']}, rejected {r['rejected']}, stock left {r['stock_left']}, orders {r['orders']}, oversold {r['oversold']}")
if r["accepted"] != 5 or r["stock_left"] != 0 or r["orders"] != 5 or r["errors"]:
    api.fail("exactly 5 orders should succeed and the stock should end at 0")
sku, pid = buyers.new_product(1)
s, _ = api.call("POST", "/orders", {"sku": sku, "qty": 2, "customer": "x"})
print(f"[VERIFY] ordering 2 when 1 is left -> {s}")
if s != 409 or api.call("GET", f"/products/{pid}/sales")[1]["orders"] != 0:
    api.fail("a rejected order must not leave an order row behind")
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/tools"
cat > "$PROJECT_DIR/tools/demo.py" <<'SHOPSTREAM_EOF'
"""Day 3 demo: 50 buyers, 10 items. Read-then-write versus one atomic UPDATE."""
import time

import api
import buyers

api.wait_healthy()
print("50 buyers press 'Buy' at the same moment for a product with 10 in stock.\n")
print("mode     accepted  rejected  orders  stock left  oversold  time")
for mode in ("naive", "atomic"):
    t = time.perf_counter()
    r = buyers.run(mode, stock=10, buyers=50)
    ms = (time.perf_counter() - t) * 1000
    print(f"{mode:8} {r['accepted']:8} {r['rejected']:9} {r['orders']:7} {r['stock_left']:11} {r['oversold']:9}  {ms:5.0f} ms")
print("\nnaive: every buyer read 'stock 10', so nearly all of them were sold an item that doesn't exist,")
print("and the last write won, so the stock column doesn't even show how much was sold.")
print("atomic: UPDATE ... SET stock = stock - 1 WHERE stock >= 1 lets the database decide, one row lock at a time.")
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
echo "PASS  Lesson 3 complete. Your completion code: SHOP0-OVERSELL-3W9D"
VERIFY_EOF
chmod +x "$ROOT/verify.sh"

say "Verify"
bash "$ROOT/verify.sh"

say "Demo"
docker compose run --rm -T tools python demo.py

say "Done"
echo "API: http://localhost:8201/products    Interactive docs: http://localhost:8201/docs"
echo "Run bash verify.sh for your completion code, bash stop.sh when you are finished."
