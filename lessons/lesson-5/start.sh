#!/usr/bin/env bash
# ShopStream API — Day 5: Package it with Docker
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
cat > "$PROJECT_DIR/.dockerignore" <<'SHOPSTREAM_EOF'
# Keep the build context small and secrets out of images.
.git
**/__pycache__
**/*.pyc
.pytest_cache
.coverage
.env
*.md
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/."
cat > "$PROJECT_DIR/Dockerfile" <<'SHOPSTREAM_EOF'
# syntax=docker/dockerfile:1
# Stage 1: install dependencies into a virtualenv (build tools stay in this stage).
FROM python:3.12-slim AS deps
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
RUN python -m venv /venv
COPY requirements.txt .
RUN /venv/bin/pip install -r requirements.txt

# Stage 2: the runtime image: slim base, the virtualenv, the code, a non-root user, a health check.
FROM python:3.12-slim AS runtime
ENV PATH=/venv/bin:$PATH PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
RUN useradd --create-home --uid 10001 shop
WORKDIR /srv
COPY --from=deps /venv /venv
COPY app/ app/
COPY migrations/ migrations/
USER shop
EXPOSE 8000
HEALTHCHECK --interval=5s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2).status == 200 else 1)"
CMD ["sh", "-c", "python -m app.check_config && exec uvicorn app.main:app --host 0.0.0.0 --port 8000"]

# Stage 3: tests and tools: the runtime image plus dev dependencies. Never deployed.
FROM runtime AS dev
USER root
COPY requirements-dev.txt requirements.txt ./
RUN pip install --no-cache-dir -r requirements-dev.txt
COPY tests/ tests/
COPY tools/ tools/
RUN chown -R shop /srv
USER shop
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/."
cat > "$PROJECT_DIR/Dockerfile.naive" <<'SHOPSTREAM_EOF'
# The Dockerfile most people write first. It works, which is the problem: nothing tells you what it costs.
FROM python:3.12
COPY . .
RUN pip install -r requirements-dev.txt
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/."
cat > "$PROJECT_DIR/compose.yaml" <<'SHOPSTREAM_EOF'
# ShopStream API, Day 5: a slim runtime image for the API, a separate dev image for tests and tools.
services:
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: shop
      POSTGRES_PASSWORD: shop-local-only
      POSTGRES_DB: shopstream
    volumes: ["pgdata:/var/lib/postgresql/data"]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U shop -d shopstream"]
      interval: 2s
      timeout: 3s
      retries: 30
  api:
    build: {context: ., target: runtime}
    image: shopstream-api:day5
    environment:
      DATABASE_URL: postgresql://shop:shop-local-only@db:5432/shopstream
      ALLOW_DEMO_ENDPOINTS: "1"
    depends_on:
      db: {condition: service_healthy}
    ports: ["8201:8000"]
    restart: unless-stopped
  tools:
    build: {context: ., target: dev}
    image: shopstream-api:day5-dev
    profiles: ["tools"]
    working_dir: /srv/tools
    environment:
      DATABASE_URL: postgresql://shop:shop-local-only@db:5432/shopstream
    depends_on: [api]
    command: ["python", "-c", "print('tools')"]
volumes:
  pgdata:
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/."
cat > "$PROJECT_DIR/requirements-dev.txt" <<'SHOPSTREAM_EOF'
# Only for tests and tools; never installed in the runtime image.
-r requirements.txt
httpx==0.28.1
pytest==8.3.4
pytest-cov==6.0.0
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/."
cat > "$PROJECT_DIR/requirements.txt" <<'SHOPSTREAM_EOF'
# What the API needs to run. Pinned, so every build installs exactly these versions.
fastapi==0.115.6
uvicorn==0.34.0
psycopg[binary]==3.2.3
psycopg-pool==3.2.4
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/app"
cat > "$PROJECT_DIR/app/__init__.py" <<'SHOPSTREAM_EOF'

SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/app"
cat > "$PROJECT_DIR/app/check_config.py" <<'SHOPSTREAM_EOF'
"""Fail fast, with one clear line, instead of a 40-line traceback ten seconds later.

Runs before the web server starts (see CMD in the Dockerfile).
"""
import sys
import time
from urllib.parse import urlparse

import psycopg

from app.config import DATABASE_URL


def main(attempts=15):
    if not DATABASE_URL:
        print("[config] DATABASE_URL is not set. Example: postgresql://user:password@db:5432/shopstream", file=sys.stderr)
        return 2
    host = urlparse(DATABASE_URL).hostname
    for i in range(attempts):
        try:
            psycopg.connect(DATABASE_URL, connect_timeout=2).close()
            print(f"[config] database at {host} reachable")
            return 0
        except psycopg.OperationalError as e:
            last = str(e).strip().splitlines()[0]
            time.sleep(1)
    hint = " Inside a container, localhost is the container itself: use the database service name (db)." if host in ("localhost", "127.0.0.1") else ""
    print(f"[config] cannot reach the database at {host} after {attempts} tries: {last}.{hint}", file=sys.stderr)
    return 3


if __name__ == "__main__":
    sys.exit(main(int(sys.argv[1]) if len(sys.argv) > 1 else 15))
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/app"
cat > "$PROJECT_DIR/app/config.py" <<'SHOPSTREAM_EOF'
"""All configuration comes from environment variables, so the same image runs anywhere."""
import os

DATABASE_URL = os.environ.get("DATABASE_URL", "")
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
"""ShopStream API, Day 4: orders that never oversell, priced by a tested pricing module.

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

from app import migrate, pricing
from app.config import ALLOW_DEMO_ENDPOINTS
from app.db import pool


@asynccontextmanager
async def lifespan(app):
    migrate.migrate()
    pool.open(wait=True)
    yield
    pool.close()


app = FastAPI(title="ShopStream API", version="0.5.0", lifespan=lifespan)


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
    discount_code: str | None = Field(None, max_length=20)


class QuoteLine(BaseModel):
    sku: str = Field(pattern=r"^SKU-[0-9]{1,6}$")
    qty: int = Field(gt=0, le=10)


class QuoteIn(BaseModel):
    lines: list[QuoteLine] = Field(min_length=1, max_length=20)
    discount_code: str | None = Field(None, max_length=20)


class Quote(BaseModel):
    subtotal: Decimal
    discount: Decimal
    tax: Decimal
    total: Decimal


class Order(BaseModel):
    id: int
    sku: str
    qty: int
    stock_left: int
    total: Decimal


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
    row = conn.execute("UPDATE products SET stock = stock - %s WHERE sku = %s AND stock >= %s RETURNING id, stock, price",
                       (body.qty, body.sku, body.qty)).fetchone()
    if not row:
        raise SoldOut()
    return row["id"], row["stock"], row["price"]


def place_order_naive(conn, body: OrderIn):
    """DON'T DO THIS: read, decide in Python, then write. Another request can run between the read and the write."""
    row = conn.execute("SELECT id, stock, price FROM products WHERE sku = %s", (body.sku,)).fetchone()
    if not row or row["stock"] < body.qty:
        raise SoldOut()
    time.sleep(0.05)  # stands in for real work between the read and the write (checking a coupon, calling payments)
    conn.execute("UPDATE products SET stock = %s WHERE id = %s", (row["stock"] - body.qty, row["id"]))
    return row["id"], row["stock"] - body.qty, row["price"]


@app.post("/orders", response_model=Order, status_code=201)
def create_order(body: OrderIn, mode: str = Query("atomic", pattern="^(atomic|naive)$")):
    if mode == "naive" and not ALLOW_DEMO_ENDPOINTS:
        raise HTTPException(status_code=404)
    place = place_order_naive if mode == "naive" else place_order_atomic
    with pool.connection() as conn:          # one transaction: the stock change and the order row commit together
        try:
            product_id, left, price = place(conn, body)
            total = pricing.quote([(price, body.qty)], body.discount_code)["total"]
        except SoldOut:
            raise HTTPException(status_code=409, detail=f"not enough stock for {body.sku}")
        except pricing.UnknownCode:
            raise HTTPException(status_code=422, detail=f"unknown discount code {body.discount_code}")
        oid = conn.execute("INSERT INTO orders (product_id, qty, customer, discount_code, total) VALUES (%s, %s, %s, %s, %s) RETURNING id",
                           (product_id, body.qty, body.customer, body.discount_code, total)).fetchone()["id"]
    return Order(id=oid, sku=body.sku, qty=body.qty, stock_left=left, total=total)


@app.post("/cart/quote", response_model=Quote)
def cart_quote(body: QuoteIn):
    skus = [line.sku for line in body.lines]
    with pool.connection() as conn:
        prices = {r["sku"]: r["price"] for r in conn.execute("SELECT sku, price FROM products WHERE sku = ANY(%s)", (skus,))}
    missing = sorted(set(skus) - set(prices))
    if missing:
        raise HTTPException(status_code=404, detail=f"unknown products: {', '.join(missing)}")
    try:
        return pricing.quote([(prices[line.sku], line.qty) for line in body.lines], body.discount_code)
    except pricing.UnknownCode:
        raise HTTPException(status_code=422, detail=f"unknown discount code {body.discount_code}")


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
mkdir -p "$PROJECT_DIR/app"
cat > "$PROJECT_DIR/app/pricing.py" <<'SHOPSTREAM_EOF'
"""Prices are money: Decimal, never float, and rounded once, to the cent, half up.

quote() is a pure function (no database, no HTTP), which makes it the easiest thing in the app to test.
Rules:
  - SAVE10 takes 10% off the subtotal.
  - FLAT5 takes 5.00 off, only when the subtotal is at least 25.00.
  - Unknown codes are rejected.
  - Sales tax of 8.25% is charged on the discounted subtotal.
"""
from decimal import ROUND_HALF_UP, Decimal

TAX_RATE = Decimal("0.0825")
CENT = Decimal("0.01")
FLAT5_MINIMUM = Decimal("25.00")


class UnknownCode(ValueError):
    pass


def money(x: Decimal) -> Decimal:
    return x.quantize(CENT, rounding=ROUND_HALF_UP)


def discount_for(subtotal: Decimal, code: str | None) -> Decimal:
    if not code:
        return Decimal("0.00")
    if code == "SAVE10":
        return money(subtotal * Decimal("0.10"))
    if code == "FLAT5":
        return Decimal("5.00") if subtotal >= FLAT5_MINIMUM else Decimal("0.00")
    raise UnknownCode(code)


def quote(lines: list[tuple[Decimal, int]], code: str | None = None) -> dict:
    """lines: (unit price, quantity) pairs."""
    subtotal = money(sum((price * qty for price, qty in lines), Decimal("0")))
    discount = discount_for(subtotal, code)
    taxable = subtotal - discount
    tax = money(taxable * TAX_RATE)
    return {"subtotal": subtotal, "discount": discount, "tax": tax, "total": taxable + tax}
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
mkdir -p "$PROJECT_DIR/migrations"
cat > "$PROJECT_DIR/migrations/004_order_totals.sql" <<'SHOPSTREAM_EOF'
ALTER TABLE orders ADD COLUMN discount_code TEXT;
ALTER TABLE orders ADD COLUMN total NUMERIC(10, 2);
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


def test_quote_endpoint_uses_database_prices(client):
    r = client.post("/cart/quote", json={"lines": [{"sku": "SKU-1002", "qty": 2}], "discount_code": "FLAT5"})
    assert r.status_code == 200
    assert r.json() == {"subtotal": "29.00", "discount": "5.00", "tax": "1.98", "total": "25.98"}
    assert client.post("/cart/quote", json={"lines": [{"sku": "SKU-1002", "qty": 1}], "discount_code": "NOPE"}).status_code == 422


def test_order_stores_its_total(client):
    sku, pid = new_product(client, 2)
    r = client.post("/orders", json={"sku": sku, "qty": 1, "customer": "ana", "discount_code": "SAVE10"})
    assert r.status_code == 201 and r.json()["total"] == "48.71"
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/tests"
cat > "$PROJECT_DIR/tests/test_pricing.py" <<'SHOPSTREAM_EOF'
"""Unit tests for app/pricing.py: no database, no HTTP, they run in milliseconds."""
from decimal import Decimal as D

import pytest

from app import pricing


def test_no_code():
    q = pricing.quote([(D("19.99"), 1)])
    assert q == {"subtotal": D("19.99"), "discount": D("0.00"), "tax": D("1.65"), "total": D("21.64")}


def test_cents_add_up_exactly():
    # 0.10 + 0.20 is 0.30000000000000004 in floats; ten of them must still be exactly 3.00
    q = pricing.quote([(D("0.10"), 10), (D("0.20"), 10)])
    assert q["subtotal"] == D("3.00")


def test_half_cent_rounds_up():
    # 8.25% of 6.00 is exactly 0.495: money rounds half up to 0.50
    q = pricing.quote([(D("6.00"), 1)])
    assert (q["tax"], q["total"]) == (D("0.50"), D("6.50"))


def test_save10():
    q = pricing.quote([(D("89.00"), 1)], "SAVE10")
    assert (q["discount"], q["total"]) == (D("8.90"), D("86.71"))


@pytest.mark.parametrize("price,expected_discount", [(D("24.99"), D("0.00")), (D("25.00"), D("5.00"))])
def test_flat5_needs_a_25_minimum(price, expected_discount):
    assert pricing.quote([(price, 1)], "FLAT5")["discount"] == expected_discount


def test_unknown_code_is_rejected():
    with pytest.raises(pricing.UnknownCode):
        pricing.quote([(D("10.00"), 1)], "FREE100")


def test_total_is_subtotal_minus_discount_plus_tax():
    for lines, code in [([(D("14.50"), 3)], None), ([(D("129.99"), 2)], "SAVE10"), ([(D("34.00"), 1)], "FLAT5")]:
        q = pricing.quote(lines, code)
        assert q["total"] == q["subtotal"] - q["discount"] + q["tax"]
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
"""Day 5 checks (inside the network): the API answers and the tests still pass. Image checks run in verify.sh."""
import api

if not api.wait_healthy():
    api.fail("the API did not answer /health")
s, q = api.call("POST", "/cart/quote", {"lines": [{"sku": "SKU-1001", "qty": 1}]})
print(f"[VERIFY] API in the runtime image answers: quote for SKU-1001 -> {s} total {q.get('total') if isinstance(q, dict) else q}")
if s != 200:
    api.fail("the API should answer from the runtime image")
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/tools"
cat > "$PROJECT_DIR/tools/demo.py" <<'SHOPSTREAM_EOF'
"""Day 4 demo: how often would the buggy pricing code have charged the wrong amount?"""
import sys
from decimal import Decimal

sys.path.insert(0, "/srv")
sys.path.insert(0, "/srv/tools/bugs")
from app import pricing  # noqa: E402
import pricing_buggy  # noqa: E402

print("Every price from 1.00 to 199.99 (19,900 prices), quoted by both modules:")
print("code     wrong totals   share   largest error")
for code in (None, "SAVE10", "FLAT5"):
    wrong, worst = 0, (None, Decimal(0))
    for cents in range(100, 20000):
        price = Decimal(cents) / 100
        good, bad = pricing.quote([(price, 1)], code)["total"], pricing_buggy.quote([(price, 1)], code)["total"]
        if good != bad:
            wrong += 1
            if abs(bad - good) > abs(worst[1]):
                worst = (price, bad - good)
    print(f"{code or '(none)':8} {wrong:12,} {100 * wrong / 19900:6.1f}%   {worst[1]:+} (item at {worst[0]:.2f})")
print("\nThree of them, side by side:")
for price, code in [(Decimal("6.00"), None), (Decimal("1.15"), "SAVE10"), (Decimal("24.99"), "FLAT5")]:
    g, b = pricing.quote([(price, 1)], code)["total"], pricing_buggy.quote([(price, 1)], code)["total"]
    print(f"   {price:>6} {code or '-':6}  correct {g:>6}   buggy {Decimal(b).quantize(Decimal('0.01')):>6}")
print("The two failing tests above name these bugs before a customer ever sees them.")
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/tools"
cat > "$PROJECT_DIR/tools/elapsed.py" <<'SHOPSTREAM_EOF'
"""Print the seconds between two Docker timestamps (RFC 3339 with nanoseconds)."""
import re
import sys
from datetime import datetime


def parse(ts):
    ts = re.sub(r"(\.\d{6})\d*", r"\1", ts.strip()).replace("Z", "+00:00")
    return datetime.fromisoformat(ts)


print(f"{(parse(sys.argv[2]) - parse(sys.argv[1])).total_seconds():.2f}")
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/tools"
cat > "$PROJECT_DIR/tools/run_tests.sh" <<'SHOPSTREAM_EOF'
#!/usr/bin/env bash
# Run the suite against the real pricing module, then against tools/bugs/pricing_buggy.py.
# Runs inside a throwaway tools container (docker compose run --rm), so copying the buggy file changes nothing else.
set -u
cd /srv
cd /srv
echo "--- the real app/pricing.py"
python -m pytest -q --cov=app --cov-report=term --cov-fail-under=80 -p no:cacheprovider 2>&1 | grep -E "passed|failed|TOTAL|pricing.py|main.py|Required" | tail -6
GOOD=${PIPESTATUS[0]}
echo "--- tools/bugs/pricing_buggy.py copied over app/pricing.py"
cp tools/bugs/pricing_buggy.py app/pricing.py
python -m pytest -q -p no:cacheprovider tests/test_pricing.py 2>&1 | grep -E "^FAILED|passed|failed" | sed 's/ - .*//' | tail -8
BAD=${PIPESTATUS[0]}
echo "real module: exit $GOOD   buggy module: exit $BAD"
[ "$GOOD" -eq 0 ] && [ "$BAD" -ne 0 ]
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/tools/bugs"
cat > "$PROJECT_DIR/tools/bugs/pricing_buggy.py" <<'SHOPSTREAM_EOF'
"""A plausible first version of app/pricing.py, with two bugs a code review could miss.

  1. Money in floats, rounded with round(): binary floats can't hold 0.1 exactly, and round() rounds half to even.
  2. FLAT5 is applied to every order, ignoring the 25.00 minimum.
The demo copies this file over app/pricing.py inside a throwaway container and runs the same tests.
"""
from decimal import Decimal

TAX_RATE = 0.0825


class UnknownCode(ValueError):
    pass


def money(x) -> Decimal:
    return Decimal(str(round(float(x), 2)))


def discount_for(subtotal, code):
    if not code:
        return 0.0
    if code == "SAVE10":
        return round(subtotal * 0.10, 2)
    if code == "FLAT5":
        return 5.0                       # bug 2: no minimum
    raise UnknownCode(code)


def quote(lines, code=None):
    subtotal = sum(float(price) * qty for price, qty in lines)          # bug 1: floats
    discount = discount_for(subtotal, code)
    tax = round((subtotal - discount) * TAX_RATE, 2)
    return {"subtotal": money(subtotal), "discount": money(discount), "tax": money(tax), "total": money(subtotal - discount + tax)}
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
IMG=shopstream-api:day5
SIZE_MB=$(( $(docker image inspect $IMG --format '{{.Size}}') / 1000000 ))
IMG_USER=$(docker image inspect $IMG --format '{{.Config.User}}')
HEALTH=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$(docker compose ps -q api)")
echo "[VERIFY] runtime image: ${SIZE_MB} MB, runs as user '${IMG_USER}', health ${HEALTH}"
[ "$SIZE_MB" -lt 350 ] || { echo "[FAIL] the runtime image should be under 350 MB"; exit 1; }
[ "$IMG_USER" = "shop" ] || { echo "[FAIL] the runtime image should not run as root"; exit 1; }
[ "$HEALTH" = "healthy" ] || { echo "[FAIL] the api container should report healthy"; exit 1; }
if docker run --rm --entrypoint python $IMG -c "import pytest" >/dev/null 2>&1; then echo "[FAIL] test tools should not be in the runtime image"; exit 1; fi
echo "[VERIFY] pytest is not in the runtime image"
MSG="$(docker run --rm $IMG 2>&1)" && RC=0 || RC=$?
echo "[VERIFY] started without DATABASE_URL -> exit $RC: $MSG"
case "$MSG" in *"DATABASE_URL is not set"*) ;; *) echo "[FAIL] a missing DATABASE_URL should stop the container with a clear message"; exit 1;; esac
TESTS="$(docker compose run --rm -T -w /srv tools python -m pytest -q -p no:cacheprovider 2>&1 | tail -1)"
echo "[VERIFY] tests in the dev image: $TESTS"
case "$TESTS" in *failed*|*error*) exit 1;; esac

echo "PASS  Lesson 5 complete. Your completion code: SHOP0-DOCKER-4M7X"
VERIFY_EOF
chmod +x "$ROOT/verify.sh"

say "Verify"
bash "$ROOT/verify.sh"

say "Demo"
NET="$(docker inspect --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' "$(docker compose ps -q api)")"
URL="postgresql://shop:shop-local-only@db:5432/shopstream"
echo "Building the naive image (FROM python:3.12, COPY . ., dev requirements) for comparison; the first time downloads about 1 GB ..."
docker build -q -f Dockerfile.naive -t shopstream-api:naive . >/dev/null
startup() {  # seconds from container start to "Application startup complete"
  local cid t0 t1
  cid=$(docker run -d --network "$NET" -e DATABASE_URL="$URL" "$1")
  for _ in $(seq 1 120); do docker logs "$cid" 2>&1 | grep -q "Application startup complete" && break; sleep 0.25; done
  t0=$(docker inspect --format '{{.State.StartedAt}}' "$cid")
  t1=$(docker logs -t "$cid" 2>&1 | grep "Application startup complete" | head -1 | cut -d' ' -f1)
  docker rm -f "$cid" >/dev/null
  docker compose run --rm -T tools python elapsed.py "$t0" "$t1"
}
printf '\n%-28s %10s %9s %10s %10s\n' "image" "size" "layers" "user" "start-up"
for img in shopstream-api:naive shopstream-api:day5; do
  size=$(( $(docker image inspect $img --format '{{.Size}}') / 1000000 ))
  layers=$(docker image inspect $img --format '{{len .RootFS.Layers}}')
  user=$(docker image inspect $img --format '{{.Config.User}}'); user=${user:-root}
  printf '%-28s %7s MB %9s %10s %8s s\n' "$img" "$size" "$layers" "$user" "$(startup $img)"
done
echo
echo "\"Works on my machine\": the same image, started three ways"
echo "1) no DATABASE_URL:"
docker run --rm shopstream-api:day5 2>&1 | sed 's/^/   /' || true
echo "2) DATABASE_URL pointing at localhost (works on your laptop, not in a container):"
docker run --rm -e DATABASE_URL=postgresql://shop:shop-local-only@localhost:5432/shopstream shopstream-api:day5 sh -c "python -m app.check_config 3" 2>&1 | sed 's/^/   /' || true
echo "3) DATABASE_URL pointing at the db service on the compose network:"
docker run --rm --network "$NET" -e DATABASE_URL="$URL" shopstream-api:day5 sh -c "python -m app.check_config 3" 2>&1 | sed 's/^/   /' || true


say "Done"
echo "API: http://localhost:8201/products    Interactive docs: http://localhost:8201/docs"
echo "Run bash verify.sh for your completion code, bash stop.sh when you are finished."
