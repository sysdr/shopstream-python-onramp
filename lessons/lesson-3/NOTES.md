# Day 3: Orders without overselling

A limited sneaker drop: 10 pairs, and 50 people press "Buy" in the same second. If your code reads the stock, checks it in Python and then writes it back, you will sell far more than 10 pairs. Today you watch that happen and fix it with one SQL statement.

## What you build

- An `orders` table (migration 003) and **`POST /orders`** `{"sku", "qty", "customer"}`.
- **`GET /products/{id}/sales`**: stock left, units sold and number of orders.
- Two ways to take stock, switchable for the demo with `?mode=`:

```python
# naive (DON'T): read, decide in Python, write
row = conn.execute("SELECT id, stock FROM products WHERE sku = %s", (sku,)).fetchone()
if row["stock"] < qty:
    raise SoldOut()
time.sleep(0.05)   # real work happens here: a coupon check, a call to payments
conn.execute("UPDATE products SET stock = %s WHERE id = %s", (row["stock"] - qty, row["id"]))

# atomic: the database checks and takes the stock in one statement
row = conn.execute("UPDATE products SET stock = stock - %s WHERE sku = %s AND stock >= %s RETURNING id, stock",
                   (qty, sku, qty)).fetchone()
if not row:
    raise SoldOut()
```

The stock change and the `INSERT INTO orders` run in **one transaction**: they commit together, or a 409 rolls both back.

## Why the naive version oversells

Between the `SELECT` and the `UPDATE` there is a gap. Every request that reads during that gap sees the same stock — 10 — and every one of them decides there's enough. Then they all write "stock = 9". The sleep makes the gap visible, but it exists without it: any real work between read and write (validating a coupon, calling payments) widens it.

The atomic `UPDATE ... WHERE stock >= qty` closes the gap. Postgres locks the row while it updates it; the next request waits, then re-checks `stock >= qty` against the new value. When stock hits 0, the `WHERE` matches nothing and the order is rejected.

## What we measured

50 buyers, released at the same moment by a barrier, product with 10 in stock:

| Mode | Accepted | Rejected | Orders | Stock left | Oversold | Time |
|---|---|---|---|---|---|---|
| naive | 50 | 0 | 50 | **6** | **40** | 366 ms |
| atomic | **10** | 40 | 10 | **0** | **0** | 227 ms |

The naive code sold 50 pairs that don't exist — and the stock column says 6 are left, because the last writes overwrote each other. Customers would get confirmation emails for shoes you'll never ship. The atomic version sold exactly 10, rejected 40 with 409, and was faster, since nobody waited 50 ms holding stale data.

Verify runs 30 buyers against stock 5 and checks exactly 5 succeed, the stock ends at 0, and a rejected order leaves no order row behind.

## Other correct ways

- `SELECT ... FOR UPDATE` locks the row on read, so the next reader waits. Use it when the decision needs several reads.
- A `CHECK (stock >= 0)` constraint (already in migration 001) is a safety net: an oversell attempt fails instead of going negative.
- Serializable isolation detects the conflict and makes you retry.

The single conditional `UPDATE` is the simplest and fastest when one row decides.

## Try it

Run these from the `shopstream-api` folder that `start.sh` created, while the lesson is running.

```bash
curl -s -X POST localhost:8201/orders -H 'Content-Type: application/json' -d '{"sku":"SKU-1003","qty":2,"customer":"ana"}'
curl -s localhost:8201/products/3/sales
docker compose -p shopstream-api run --rm -T tools python demo.py
```

## Say it in an interview

**Q: Two users buy the last item at the same time. How do you make sure only one gets it?**
A: Make the check and the decrement one atomic operation in the database: `UPDATE ... SET stock = stock - 1 WHERE id = ? AND stock >= 1`, and treat zero affected rows as sold out. Or lock the row with `SELECT ... FOR UPDATE` inside a transaction.

**Q: What's a lost update?**
A: Two transactions read the same value, both compute a new one, and the second write overwrites the first, so one change disappears. Here the stock showed 6 after 50 sales.

**Q: Why put the order insert in the same transaction?**
A: So you never have stock taken without an order, or an order without stock taken. Either both commit or neither does.

## Recap

- Read-then-write in application code races; the database must make the decision.
- Measured: naive 50 accepted for 10 items (40 oversold, stock column wrong); atomic exactly 10, 0 oversold.
- One transaction keeps the stock and the order row consistent.
- A `CHECK` constraint is a cheap safety net.

## Challenge (10 minutes)

Rewrite `place_order_naive` with `SELECT ... FOR UPDATE` instead of the atomic `UPDATE`, run the demo and check it no longer oversells.

<details class="sdc-hint"><summary>Hint 1</summary>`SELECT id, stock FROM products WHERE sku = %s FOR UPDATE` — the second request waits until the first commits.</details>

<details class="sdc-hint"><summary>Hint 2</summary>Keep the sleep: with the lock held, the requests now run one after another. How long does the demo take?</details>

<details class="sdc-hint"><summary>Hint 3</summary>50 requests × 50 ms in series is about 2.5 s — the cost of holding a lock while doing slow work.</details>
