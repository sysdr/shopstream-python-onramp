# Day 2: Store it in Postgres

Restart yesterday's API and every product you added is gone. Real data lives in a database. Today ShopStream's catalog moves into Postgres, and you meet the two mistakes that hurt beginners most: building SQL from user input, and searching a big table without an index. You'll see both fail, with numbers.

## What you build

- **Postgres 16** in its own container, next to the API.
- **A connection pool** (`psycopg_pool`): up to 20 open connections that requests borrow and return, instead of opening a new one per request.
- **Versioned migrations**: `migrations/001_products.sql`, `002_products_name_index.sql`. `app/migrate.py` applies each file once, in order, inside a transaction, records it in `schema_migrations`, and holds a lock so two instances starting together don't both run it.
- **A safe search** — `GET /products/search?q=` — and, for this lesson only, an unsafe one built with string formatting, so you can watch it break.

## Parameters, not string building

```python
# Safe: the SQL and the value travel separately; the value can never become SQL.
conn.execute("SELECT ... FROM products WHERE name ILIKE %s", (f"%{q}%",))

# DON'T: the value is pasted into the SQL text.
conn.execute(f"SELECT ... FROM products WHERE name ILIKE '%{q}%'")
```

With the second version, a user who types a quote character can end your string and write their own SQL.

## What we measured

**SQL injection**, same input to both endpoints:

| Input | Parameterised | String-built |
|---|---|---|
| `jacket` | 1 row | 1 row |
| `zzz' OR 1=1 --` | 0 rows | **every product** (6) |
| `zzz%' UNION SELECT 0, current_user, version(), '0', 0 --` | 0 rows | **1 row leaking the database user (`shop`) and server version (PostgreSQL 16.16)** |

The second input turns the `WHERE` clause into "always true" and comments out the rest. The third glues a second query onto the first and reads data the endpoint was never meant to return. The parameterised query searched for that exact text and found nothing.

**Query time**, looking up a product by name among 200,000 rows:

| | p50 | Query plan |
|---|---|---|
| Without an index | 40.23 ms | Parallel Seq Scan on products |
| With migration 002's index | 0.24 ms | Index Scan using products_lower_name_idx |

**170 times faster.** Without the index Postgres reads every row; with it, it jumps straight to the match. The demo switches the index off with `SET enable_indexscan = off` to show the "before" on the same data.

## Why migrations

A migration is a numbered SQL file that changes the schema. Because every environment applies the same files in the same order, your laptop, the tests and production end up with the same tables. `schema_migrations` remembers what's applied, so starting the app twice changes nothing the second time.

## Try it

Run these from the `shopstream-api` folder that `start.sh` created, while the lesson is running.

```bash
curl -s 'localhost:8201/products/search?q=sock'
docker compose -p shopstream-api exec db psql -U shop -d shopstream -c 'SELECT * FROM schema_migrations'
docker compose -p shopstream-api restart api && curl -s localhost:8201/products   # still there
```

## Say it in an interview

**Q: How do you prevent SQL injection?**
A: Always pass user input as query parameters (prepared or bound statements), never by concatenating strings. Add least-privilege database users so a mistake can't drop tables, and validate input at the edge.

**Q: What does an index cost?**
A: Disk space and slower writes, because every insert and update must also update the index. Add indexes for the queries you actually run, and check with `EXPLAIN` that they're used.

**Q: Why use a connection pool?**
A: Opening a Postgres connection takes milliseconds and server memory. A pool keeps a bounded set open and reuses them, which caps load on the database and removes connection setup from every request.

## Recap

- Products persist in Postgres; migrations make the schema reproducible.
- Measured: a string-built search returned every row and leaked the DB user and version; the parameterised one returned nothing.
- Measured: an index took a lookup from 40.23 ms to 0.24 ms on 200,000 rows.
- A pool of 20 connections serves all requests.

## Challenge (10 minutes)

Add migration `003_products_created_at.sql` that adds a `created_at` column with a default of `now()`, and return it from `GET /products`.

<details class="sdc-hint"><summary>Hint 1</summary>`ALTER TABLE products ADD COLUMN created_at TIMESTAMPTZ NOT NULL DEFAULT now();`</details>

<details class="sdc-hint"><summary>Hint 2</summary>Add `created_at` to `COLS` in `app/main.py` and `created_at: datetime | None = None` to the `Product` model.</details>

<details class="sdc-hint"><summary>Hint 3</summary>Rebuild with `docker compose -p shopstream-api up -d --build api`; the migration runs at start-up and appears in `schema_migrations`.</details>
