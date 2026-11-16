# Implementation guide — Day 6: Put it online

Time: 25–35 minutes. Needs **Docker** (Docker Desktop, or Docker Engine with the Compose plugin) and about 2 GB of free memory. Nothing else: Python, Postgres and the test tools run inside containers.

## Get the code

Download **start.sh** and **stop.sh** from the Scripts tab, or clone the course repo:

```bash
git clone https://github.com/sysdr/shopstream-python-onramp.git
cd shopstream-python-onramp/lessons/lesson-6
```

`start.sh` writes the complete project for Day 6 into `./shopstream-api`, so you can start at any lesson. On Windows, run it from Git Bash or WSL.

## What start.sh does

1. Checks that Docker and Docker Compose are available and the engine is running.
2. Writes the project into `./shopstream-api` and generates a random database password into `.env`.
3. Builds the image and starts Postgres 16 and the API (plus an optional public tunnel) (`docker compose up -d`; the first build downloads about 200 MB).
4. Waits for the API to answer, then runs the 17 tests inside the tools container.
5. Writes `verify.sh`, runs it, then runs the demo.

## What's new in the code

| File | What it does |
|---|---|
| `gunicorn.conf.py` | 2 uvicorn workers (WEB_CONCURRENCY), timeouts, errors to stdout |
| `Dockerfile` | CMD: check config, migrate once, then exec gunicorn; health check on /health/ready |
| `app/main.py` | /health/ready checks the database; JSON access log middleware; demo endpoints off |
| `compose.yaml` | DB password from .env (required); `tunnel` service (cloudflared quick tunnel, profile public) |
| `.env (generated)` | A random database password; kept next to start.sh as .env.keep; ignored by git and Docker |

## Run it

```bash
bash start.sh
```

When it finishes, open:

| What | Where |
|---|---|
| API | http://localhost:8201/products |
| Interactive docs | http://localhost:8201/docs |
| Readiness | http://localhost:8201/health/ready |
| Public URL | printed by the demo (changes every run) |

## Expected output

Timings depend on your machine; the shape should look like this (Docker Desktop, 8 CPUs):

```text
== Verify
[VERIFY] GET /health/ready -> 200 {'status': 'ready', 'version': '1.0.0'}
[VERIFY] demo endpoints in production: search-unsafe -> 404, orders?mode=naive -> 404
[VERIFY] a real order still works -> 201 total 14.13
[VERIFY] api runs as uid 10001 with 3 gunicorn processes (1 manager + 2 workers)
[VERIFY] database password comes from .env (55 bytes, not in compose.yaml, ignored by git and Docker)
[VERIFY] JSON access log lines for /health/ready: 3
[VERIFY] public URL: tunnel not running (optional: docker compose --profile public up -d tunnel)
PASS  Lesson 6 complete. Your completion code: SHOP0-ONLINE-9T5H

== Demo
Starting a Cloudflare quick tunnel (no account; the URL changes every time) ...
Public URL: https://stylus-brokers-subscription-offices.trycloudflare.com
Latency for GET /products/{id}, 20 requests each:
   local (inside Docker)    20/20 ok   p50    3.9 ms   p95    6.1 ms
   public URL               20/20 ok   p50  204.2 ms   p95  414.2 ms
Open https://stylus-brokers-subscription-offices.trycloudflare.com/docs on your phone. Stop sharing with: docker compose -p shopstream-api stop tunnel

Restart the API container, as a deploy would, and check nothing was lost:
   orders before: 1, after: 1; ready again after about 4 s
   During those seconds requests fail: one container can't restart without a gap (Step 1 adds a load balancer).
```

## Try it yourself

```bash
cd shopstream-api && docker compose -p shopstream-api logs tunnel | grep trycloudflare   # your public URL
```

```bash
cd shopstream-api && docker compose -p shopstream-api logs --no-log-prefix api | tail -3   # JSON access log
```

```bash
cd shopstream-api && docker compose -p shopstream-api stop tunnel   # stop sharing
```

## Verify and get your completion code

```bash
bash verify.sh
```

Checks readiness, that demo endpoints return 404, a real order works, the API runs as a non-root user with at least 2 workers, the password comes from .env, requests appear in the JSON access log, and (if the tunnel runs) the public URL answers. On success it prints:

```text
PASS  Lesson 6 complete. Your completion code: SHOP0-ONLINE-9T5H
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
| No public URL | The tunnel needs outbound access to Cloudflare; corporate networks often block it. Everything else still works |
