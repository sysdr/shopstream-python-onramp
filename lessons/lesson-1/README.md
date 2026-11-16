# Implementation guide — Day 1: Your first API in 20 minutes

Time: 20–30 minutes. Needs **Docker** (Docker Desktop, or Docker Engine with the Compose plugin) and about 2 GB of free memory. Nothing else: Python, Postgres and the test tools run inside containers.

## Get the code

Download **start.sh** and **stop.sh** from the Scripts tab, or clone the course repo:

```bash
git clone https://github.com/sysdr/shopstream-python-onramp.git
cd shopstream-python-onramp/lessons/lesson-1
```

`start.sh` writes the complete project for Day 1 into `./shopstream-api`, so you can start at any lesson. On Windows, run it from Git Bash or WSL.

## What start.sh does

1. Checks that Docker and Docker Compose are available and the engine is running.
2. Writes the project into `./shopstream-api`.
3. Builds the image and starts the API (`docker compose up -d`; the first build downloads about 200 MB).
4. Waits for the API to answer, then runs the 3 tests inside the tools container.
5. Writes `verify.sh`, runs it, then runs the demo.

## What's new in the code

| File | What it does |
|---|---|
| `Dockerfile, requirements.txt` | A Python 3.12 slim image with FastAPI, uvicorn and pytest (Day 5 explains every line) |
| `compose.yaml` | The api service on port 8201, and a `tools` container for the demo and checks |
| `app/main.py` | ProductIn / Product models, GET /products, GET /products/{id}, POST /products, /health |
| `tests/test_api.py` | 3 tests with FastAPI's TestClient |
| `tools/api.py, demo.py, checks.py` | HTTP helpers (standard library), the measured demo and the checks verify.sh runs |

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
[VERIFY] GET /products -> 200, 5 products
[VERIFY] POST /products -> 201 id=6
[VERIFY] invalid product -> 422, rejected fields ['name', 'price', 'sku', 'stock']
PASS  Lesson 1 complete. Your completion code: SHOP0-FIRSTAPI-5N2K

== Demo
1) First request: GET /products?limit=3 -> 200 in 18 ms (including waiting for start-up)
   1  SKU-1001  Trail running shoes      89.00  stock 25
   2  SKU-1002  Merino socks             14.50  stock 120
   3  SKU-1003  Rain jacket             129.99  stock 12

2) 200 more requests, one at a time: p50 2.2 ms, p99 4.0 ms

3) A bad request never reaches your code:
   POST /products {"sku": "shoe", "name": "", "price": "-5", "stock": 3} -> 422
   - sku: String should match pattern '^SKU-[0-9]{1,6}$'
   - name: String should have at least 1 character
   - price: Input should be greater than 0
   A good one -> 201, id 7
   The same SKU again -> 409 SKU-1006 already exists

Open http://localhost:8201/docs for the interactive API docs FastAPI generated.
```

## Try it yourself

```bash
curl -s 'localhost:8201/products?limit=2'
```

```bash
curl -s -X POST localhost:8201/products -H 'Content-Type: application/json' -d '{"sku":"SKU-2001","name":"Gaiters","price":"24.00","stock":8}'
```

```bash
open http://localhost:8201/docs   # interactive docs: try POST /products with a negative price
```

## Verify and get your completion code

```bash
bash verify.sh
```

Lists the seeded products, creates one and reads it back, and checks an invalid product is rejected with 422 naming all four bad fields. On success it prints:

```text
PASS  Lesson 1 complete. Your completion code: SHOP0-FIRSTAPI-5N2K
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
