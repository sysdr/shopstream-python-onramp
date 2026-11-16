#!/usr/bin/env bash
# ShopStream API — Day 2: Store it in Postgres
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
# ShopStream API, Day 2: FastAPI + Postgres. No bind mounts: the code is built into the image.
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
    image: shopstream-api:day2
    environment:
      DATABASE_URL: postgresql://shop:shop-local-only@db:5432/shopstream
      ALLOW_DEMO_ENDPOINTS: "1"
    depends_on:
      db: {condition: service_healthy}
    ports: ["8201:8000"]
  tools:
    image: shopstream-api:day2
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
"""ShopStream API, Day 2: the catalog now lives in Postgres.

Every query passes user input as a parameter (%s), never by building the SQL string.
The /products/search-unsafe endpoint exists only to show what goes wrong if you do;
it is switched on by ALLOW_DEMO_ENDPOINTS=1 and removed before production (Day 6).
"""
from contextlib import asynccontextmanager
from decimal import Decimal

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


app = FastAPI(title="ShopStream API", version="0.2.0", lifespan=lifespan)


class ProductIn(BaseModel):
    sku: str = Field(pattern=r"^SKU-[0-9]{1,6}$", examples=["SKU-1001"])
    name: str = Field(min_length=1, max_length=120)
    price: Decimal = Field(gt=0, max_digits=8, decimal_places=2)
    stock: int = Field(ge=0)


class Product(ProductIn):
    id: int


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
cat > "$PROJECT_DIR/tools/checks.py" <<'SHOPSTREAM_EOF'
"""Day 2 checks: products persist in Postgres, migrations are recorded, search is parameterised."""
import uuid

import psycopg

import api

if not api.wait_healthy():
    api.fail("the API did not answer /health")
with psycopg.connect(api.DATABASE_URL) as conn:
    versions = [r[0] for r in conn.execute("SELECT version FROM schema_migrations ORDER BY version")]
print(f"[VERIFY] migrations applied: {versions}")
if versions[:2] != ["001_products", "002_products_name_index"]:
    api.fail("both migrations should be recorded in schema_migrations")
sku = f"SKU-{uuid.uuid4().int % 900000 + 100000}"
s, p = api.call("POST", "/products", {"sku": sku, "name": "Verify lantern", "price": "12.00", "stock": 4})
with psycopg.connect(api.DATABASE_URL) as conn:
    row = conn.execute("SELECT name FROM products WHERE sku = %s", (sku,)).fetchone()
print(f"[VERIFY] POST /products -> {s}; row in Postgres: {row[0] if row else None}")
if s != 201 or not row:
    api.fail("a created product should be stored in Postgres")
evil = "zzz' OR 1=1 --"
safe = api.call("GET", "/products/search?q=" + api.quote(evil))[1]
unsafe = api.call("GET", "/products/search-unsafe?q=" + api.quote(evil))[1]
print(f"[VERIFY] injection {evil!r}: safe search returned {len(safe)} rows, unsafe returned {len(unsafe)}")
if safe != [] or len(unsafe) < 5:
    api.fail("the parameterised search should return nothing for an injection attempt")
SHOPSTREAM_EOF
mkdir -p "$PROJECT_DIR/tools"
cat > "$PROJECT_DIR/tools/demo.py" <<'SHOPSTREAM_EOF'
"""Day 2 demo: data that survives a restart, SQL injection, and what an index does to query time."""
import time

import psycopg

import api

api.wait_healthy()
with psycopg.connect(api.DATABASE_URL, autocommit=True) as conn:
    n = conn.execute("SELECT count(*) FROM products").fetchone()[0]
    print(f"1) Products in Postgres: {n}; migrations: {[r[0] for r in conn.execute('SELECT version FROM schema_migrations ORDER BY 1')]}")

print("\n2) SQL injection: the same input to two search endpoints")
for label, q in [("normal", "jacket"), ("injection", "zzz' OR 1=1 --"),
                 ("leak", "zzz%' UNION SELECT 0, current_user, version(), '0', 0 --")]:
    safe = api.call("GET", "/products/search?q=" + api.quote(q))[1]
    unsafe = api.call("GET", "/products/search-unsafe?q=" + api.quote(q))[1]
    print(f"   {label:9} q={q!r}")
    print(f"      parameterised: {len(safe)} rows   string-built: {len(unsafe) if isinstance(unsafe, list) else unsafe} rows")
    if label == "leak" and isinstance(unsafe, list) and unsafe:
        print(f"      string-built leaked: user={unsafe[0]['sku']!r} server={unsafe[0]['name'][:40]!r}")

print("\n3) Query time: find a product by name among 200,000 rows")
with psycopg.connect(api.DATABASE_URL, autocommit=True) as conn:
    if conn.execute("SELECT count(*) FROM products").fetchone()[0] < 200000:
        conn.execute("""INSERT INTO products (sku, name, price, stock)
                        SELECT 'SKU-' || (200000 + g), 'Generated item ' || g, 9.99, 10 FROM generate_series(1, 200000) g
                        ON CONFLICT DO NOTHING""")
        conn.execute("ANALYZE products")
    q = "SELECT id FROM products WHERE lower(name) = lower(%s)"

    def timed(label, setup):
        conn.execute(setup)
        best = []
        for i in range(20):
            t = time.perf_counter(); conn.execute(q, (f"Generated item {1000 + i * 7919 % 199000}",)).fetchall(); best.append((time.perf_counter() - t) * 1000)
        lines = [r[0] for r in conn.execute("EXPLAIN " + q, ("x",)).fetchall()]
        plan = next((x for x in lines if "Scan" in x), lines[0]).replace("->", "").split("  (")[0].strip()
        print(f"   {label:24} p50 {api.pct(best, 50):7.2f} ms   plan: {plan}")
        return api.pct(best, 50)

    slow = timed("without the index", "SET enable_indexscan = off; SET enable_bitmapscan = off")
    fast = timed("with migration 002", "RESET enable_indexscan; RESET enable_bitmapscan")
    print(f"   The index makes this lookup {slow / fast:.0f}x faster.")
    conn.execute("DELETE FROM products WHERE name LIKE 'Generated item %'")
print("\nThe products survive restarts now: docker compose -p shopstream-api restart api, then GET /products.")
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
echo "PASS  Lesson 2 complete. Your completion code: SHOP0-POSTGRES-8J4R"
VERIFY_EOF
chmod +x "$ROOT/verify.sh"

say "Verify"
bash "$ROOT/verify.sh"

say "Demo"
docker compose run --rm -T tools python demo.py

say "Done"
echo "API: http://localhost:8201/products    Interactive docs: http://localhost:8201/docs"
echo "Run bash verify.sh for your completion code, bash stop.sh when you are finished."
