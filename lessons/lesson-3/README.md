# Implementation guide — Day 3: Orders without overselling

Time: 25–35 minutes. Needs **Docker** (Docker Desktop, or Docker Engine with the Compose plugin) and about 2 GB of free memory. Nothing else: Python, Postgres and the test tools run inside containers.

## Get the code

Download **start.sh** and **stop.sh** from the Scripts tab, or clone the course repo:

```bash
git clone https://github.com/sysdr/shopstream-python-onramp.git
cd shopstream-python-onramp/lessons/lesson-3
```

`start.sh` writes the complete project for Day 3 into `./shopstream-api`, so you can start at any lesson. On Windows, run it from Git Bash or WSL.

## What start.sh does

1. Checks that Docker and Docker Compose are available and the engine is running.
2. Writes the project into `./shopstream-api`.
3. Builds the image and starts Postgres 16 and the API (`docker compose up -d`; the first build downloads about 200 MB).
4. Waits for the API to answer, then runs the 7 tests inside the tools container.
5. Writes `verify.sh`, runs it, then runs the demo.

## What's new in the code

| File | What it does |
|---|---|
| `migrations/003_orders.sql` | The orders table |
| `app/main.py` | POST /orders (atomic UPDATE ... WHERE stock >= qty, plus the order row in one transaction); ?mode=naive for the demo; GET /products/{id}/sales |
| `tests/test_orders.py` | Stock is taken, a sold-out order gets 409, 20 concurrent buyers never oversell |
| `tools/buyers.py` | N threads released by a barrier, all buying the same product |

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
[VERIFY] 30 buyers, stock 5: accepted 5, rejected 25, stock left 0, orders 5, oversold 0
[VERIFY] ordering 2 when 1 is left -> 409
PASS  Lesson 3 complete. Your completion code: SHOP0-OVERSELL-3W9D

== Demo
50 buyers press 'Buy' at the same moment for a product with 10 in stock.

mode     accepted  rejected  orders  stock left  oversold  time
naive          50         0      50           6        40    366 ms
atomic         10        40      10           0         0    227 ms

naive: every buyer read 'stock 10', so nearly all of them were sold an item that doesn't exist,
and the last write won, so the stock column doesn't even show how much was sold.
atomic: UPDATE ... SET stock = stock - 1 WHERE stock >= 1 lets the database decide, one row lock at a time.
```

## Try it yourself

```bash
curl -s -X POST localhost:8201/orders -H 'Content-Type: application/json' -d '{"sku":"SKU-1003","qty":2,"customer":"ana"}'
```

```bash
curl -s localhost:8201/products/3/sales
```

```bash
cd shopstream-api && docker compose -p shopstream-api run --rm -T tools python demo.py
```

## Verify and get your completion code

```bash
bash verify.sh
```

Sends 30 simultaneous buyers at a product with 5 in stock and checks exactly 5 orders succeed and the stock ends at 0; then checks a rejected order leaves no order row. On success it prints:

```text
PASS  Lesson 3 complete. Your completion code: SHOP0-OVERSELL-3W9D
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
