# Implementation guide — Day 2: Store it in Postgres

Time: 25–35 minutes. Needs **Docker** (Docker Desktop, or Docker Engine with the Compose plugin) and about 2 GB of free memory. Nothing else: Python, Postgres and the test tools run inside containers.

## Get the code

Download **start.sh** and **stop.sh** from the Scripts tab, or clone the course repo:

```bash
git clone https://github.com/sysdr/shopstream-python-onramp.git
cd shopstream-python-onramp/lessons/lesson-2
```

`start.sh` writes the complete project for Day 2 into `./shopstream-api`, so you can start at any lesson. On Windows, run it from Git Bash or WSL.

## What start.sh does

1. Checks that Docker and Docker Compose are available and the engine is running.
2. Writes the project into `./shopstream-api`.
3. Builds the image and starts Postgres 16 and the API (`docker compose up -d`; the first build downloads about 200 MB).
4. Waits for the API to answer, then runs the 5 tests inside the tools container.
5. Writes `verify.sh`, runs it, then runs the demo.

## What's new in the code

| File | What it does |
|---|---|
| `compose.yaml` | Adds `db` (postgres:16-alpine, health check); the API waits for it |
| `migrations/001_products.sql, 002_products_name_index.sql` | The products table with 5 seed rows; an index on lower(name) |
| `app/migrate.py` | Applies each migration once, in a transaction, under an advisory lock; records it in schema_migrations |
| `app/db.py, app/config.py` | A psycopg connection pool (max 20); DATABASE_URL from the environment |
| `app/main.py` | Every query with %s parameters; GET /products/search; the demo-only /products/search-unsafe |
| `tests/conftest.py` | Creates a fresh `shopstream_test` database for every test run |

## Run it

```bash
bash start.sh
```

When it finishes, open:

| What | Where |
|---|---|
| API | http://localhost:8201/products |
| Interactive docs | http://localhost:8201/docs |

## Expected output

Timings depend on your machine; the shape should look like this (Docker Desktop, 8 CPUs):

```text
== Verify
[VERIFY] migrations applied: ['001_products', '002_products_name_index']
[VERIFY] POST /products -> 201; row in Postgres: Verify lantern
[VERIFY] injection "zzz' OR 1=1 --": safe search returned 0 rows, unsafe returned 6
PASS  Lesson 2 complete. Your completion code: SHOP0-POSTGRES-8J4R

== Demo
1) Products in Postgres: 6; migrations: ['001_products', '002_products_name_index']

2) SQL injection: the same input to two search endpoints
   normal    q='jacket'
      parameterised: 1 rows   string-built: 1 rows
   injection q="zzz' OR 1=1 --"
      parameterised: 0 rows   string-built: 6 rows
   leak      q="zzz%' UNION SELECT 0, current_user, version(), '0', 0 --"
      parameterised: 0 rows   string-built: 1 rows
      string-built leaked: user='shop' server='PostgreSQL 16.16 on x86_64-pc-linux-musl'

3) Query time: find a product by name among 200,000 rows
   without the index        p50   40.23 ms   plan: Parallel Seq Scan on products
   with migration 002       p50    0.24 ms   plan: Index Scan using products_lower_name_idx on products
   The index makes this lookup 170x faster.

The products survive restarts now: docker compose -p shopstream-api restart api, then GET /products.
```

## Try it yourself

```bash
curl -s 'localhost:8201/products/search?q=sock'
```

```bash
cd shopstream-api && docker compose -p shopstream-api exec db psql -U shop -d shopstream -c 'SELECT * FROM schema_migrations'
```

```bash
cd shopstream-api && docker compose -p shopstream-api restart api && curl -s localhost:8201/products   # the data survives
```

## Verify and get your completion code

```bash
bash verify.sh
```

Checks both migrations are recorded, a created product is stored in Postgres, and an injection attempt returns nothing from the parameterised search (and everything from the unsafe one). On success it prints:

```text
PASS  Lesson 2 complete. Your completion code: SHOP0-POSTGRES-8J4R
```

Enter the code below the lesson to mark it complete.

## Stop

```bash
bash stop.sh          # stop the containers
bash stop.sh --wipe   # also delete the database volume
```

The next `start.sh` begins with a fresh database. Images stay cached, so later lessons start faster.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Cannot connect to the Docker daemon` | Start Docker Desktop (or `sudo systemctl start docker`) and run start.sh again |
| `port is already allocated` | Something else uses port 8201: `bash stop.sh`, or stop the other app |
| `the API did not become healthy` | The log lines printed after the error show why; `cd shopstream-api && docker compose -p shopstream-api logs api` |
| Tests fail | The output above the error names the failing test and the assertion |
| `bash\r: No such file or directory` (Windows) | The script got Windows line endings: `git config --global core.autocrlf input`, then clone again |
