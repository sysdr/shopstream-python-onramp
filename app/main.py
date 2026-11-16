"""ShopStream API, Day 6: production settings.

Orders never oversell and are priced by a tested pricing module. Migrations run once before the workers start
(see the Dockerfile CMD), demo endpoints are off unless ALLOW_DEMO_ENDPOINTS=1, and /health/ready checks the database.

Every query passes user input as a parameter (%s), never by building the SQL string.
The /products/search-unsafe endpoint exists only to show what goes wrong if you do;
it is switched on by ALLOW_DEMO_ENDPOINTS=1 and removed before production (Day 6).
"""
from contextlib import asynccontextmanager
from decimal import Decimal

import json
import logging
import sys
import time

import psycopg
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field

from app import migrate, pricing
from app.config import ALLOW_DEMO_ENDPOINTS, RUN_MIGRATIONS_ON_START
from app.db import pool


@asynccontextmanager
async def lifespan(app):
    if RUN_MIGRATIONS_ON_START:
        migrate.migrate()
    pool.open(wait=True)
    yield
    pool.close()


app = FastAPI(title="ShopStream API", version="1.0.0", lifespan=lifespan)

access = logging.getLogger("shopstream.access")
access.addHandler(logging.StreamHandler(sys.stdout))
access.setLevel(logging.INFO)
access.propagate = False


@app.middleware("http")
async def access_log(request, call_next):
    """One JSON line per request: easy to search, and every log tool can parse it."""
    t0 = time.perf_counter()
    response = await call_next(request)
    access.info(json.dumps({"ts": round(time.time(), 3), "method": request.method, "path": request.url.path,
                            "status": response.status_code, "ms": round((time.perf_counter() - t0) * 1000, 1)}))
    return response


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
    """Liveness: the process answers."""
    return {"status": "ok"}


@app.get("/health/ready")
def ready():
    """Readiness: the process can serve real requests, so the database answers too."""
    try:
        with pool.connection(timeout=2) as conn:
            conn.execute("SELECT 1")
    except Exception:
        raise HTTPException(status_code=503, detail="database unavailable")
    return {"status": "ready", "version": app.version}


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
