# Implementation guide — Day 4: Tests that catch real bugs

Time: 30–40 minutes. Needs **Docker** (Docker Desktop, or Docker Engine with the Compose plugin) and about 2 GB of free memory. Nothing else: Python, Postgres and the test tools run inside containers.

## Get the code

Download **start.sh** and **stop.sh** from the Scripts tab, or clone the course repo:

```bash
git clone https://github.com/sysdr/shopstream-python-onramp.git
cd shopstream-python-onramp/lessons/lesson-4
```

`start.sh` writes the complete project for Day 4 into `./shopstream-api`, so you can start at any lesson. On Windows, run it from Git Bash or WSL.

## What start.sh does

1. Checks that Docker and Docker Compose are available and the engine is running.
2. Writes the project into `./shopstream-api`.
3. Builds the image and starts Postgres 16 and the API (`docker compose up -d`; the first build downloads about 200 MB).
4. Waits for the API to answer, then runs the 17 tests inside the tools container.
5. Writes `verify.sh`, runs it, then runs the demo.

## What's new in the code

| File | What it does |
|---|---|
| `app/pricing.py` | quote(): Decimal money, SAVE10, FLAT5 (minimum 25.00), 8.25% tax, rounded half up once |
| `migrations/004_order_totals.sql` | discount_code and total on orders |
| `app/main.py` | POST /cart/quote; orders store their total |
| `tests/test_pricing.py` | Unit tests at the edges: half a cent, one cent under a threshold |
| `tools/bugs/pricing_buggy.py` | A plausible first version with float maths and a missing minimum |
| `tools/run_tests.sh` | Runs the suite with coverage (minimum 80%), then against the buggy module |

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
[VERIFY] POST /cart/quote 2 x SKU-1002 with FLAT5 -> 200 {"subtotal": "29.00", "discount": "5.00", "tax": "1.98", "total": "25.98"}
[VERIFY]  Container shopstream-api-db-1  Running
[VERIFY]  Container shopstream-api-api-1  Running
[VERIFY]  Container shopstream-api-db-1  Waiting
[VERIFY]  Container shopstream-api-db-1  Healthy
[VERIFY] --- the real app/pricing.py
[VERIFY] app/main.py         126     17    87%
[VERIFY] app/pricing.py       22      0   100%
[VERIFY] TOTAL               179     19    89%
[VERIFY] Required test coverage of 80% reached. Total coverage: 89.39%
[VERIFY] 17 passed, 1 warning in 1.66s
[VERIFY] --- tools/bugs/pricing_buggy.py copied over app/pricing.py
[VERIFY] FAILED tests/test_pricing.py::test_half_cent_rounds_up
[VERIFY] FAILED tests/test_pricing.py::test_flat5_needs_a_25_minimum[price0-expected_discount0]
[VERIFY] 2 failed, 6 passed in 0.10s
[VERIFY] real module: exit 0   buggy module: exit 1
PASS  Lesson 4 complete. Your completion code: SHOP0-TESTS-6B1Q

== Demo
Every price from 1.00 to 199.99 (19,900 prices), quoted by both modules:
code     wrong totals   share   largest error
(none)              8    0.0%   -0.01 (item at 6.00)
SAVE10            464    2.3%   +0.02 (item at 1.15)
FLAT5           2,407   12.1%   -5.42 (item at 1.04)

Three of them, side by side:
     6.00 -       correct   6.50   buggy   6.49
     1.15 SAVE10  correct   1.11   buggy   1.13
    24.99 FLAT5   correct  27.05   buggy  21.64
The two failing tests above name these bugs before a customer ever sees them.
```

## Try it yourself

```bash
cd shopstream-api && docker compose -p shopstream-api run --rm -T -w /srv tools python -m pytest -q
```

```bash
cd shopstream-api && docker compose -p shopstream-api run --rm -T -w /srv tools bash tools/run_tests.sh
```

```bash
curl -s -X POST localhost:8201/cart/quote -H 'Content-Type: application/json' -d '{"lines":[{"sku":"SKU-1002","qty":2}],"discount_code":"FLAT5"}'
```

## Verify and get your completion code

```bash
bash verify.sh
```

Checks a FLAT5 quote is exactly 25.98, the suite passes with at least 80% coverage, and the same tests fail against the buggy pricing module. On success it prints:

```text
PASS  Lesson 4 complete. Your completion code: SHOP0-TESTS-6B1Q
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
