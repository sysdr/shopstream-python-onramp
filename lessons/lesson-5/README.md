# Implementation guide — Day 5: Package it with Docker

Time: 25–35 minutes. Needs **Docker** (Docker Desktop, or Docker Engine with the Compose plugin) and about 2 GB of free memory. Nothing else: Python, Postgres and the test tools run inside containers.

## Get the code

Download **start.sh** and **stop.sh** from the Scripts tab, or clone the course repo:

```bash
git clone https://github.com/sysdr/shopstream-python-onramp.git
cd shopstream-python-onramp/lessons/lesson-5
```

`start.sh` writes the complete project for Day 5 into `./shopstream-api`, so you can start at any lesson. On Windows, run it from Git Bash or WSL.

## What start.sh does

1. Checks that Docker and Docker Compose are available and the engine is running.
2. Writes the project into `./shopstream-api`.
3. Builds the image and starts Postgres 16 (with a data volume) and the API (`docker compose up -d`; the first build downloads about 200 MB; the demo also builds a 1.7 GB naive image once, for comparison).
4. Waits for the API to answer, then runs the 17 tests inside the tools container.
5. Writes `verify.sh`, runs it, then runs the demo.

## What's new in the code

| File | What it does |
|---|---|
| `Dockerfile` | Three stages: deps (virtualenv), runtime (slim, non-root user `shop`, HEALTHCHECK), dev (adds test tools) |
| `Dockerfile.naive` | The common first attempt, built by the demo for comparison |
| `requirements.txt, requirements-dev.txt` | Runtime and test dependencies split, all pinned |
| `.dockerignore` | Keeps .git, caches and .env out of images |
| `app/check_config.py` | Fails fast with one line when DATABASE_URL is missing or the database is unreachable |
| `compose.yaml` | api uses target runtime, tools uses target dev; named volume pgdata |

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
[VERIFY] API in the runtime image answers: quote for SKU-1001 -> 200 total 96.34
[VERIFY] runtime image: 236 MB, runs as user 'shop', health healthy
[VERIFY] pytest is not in the runtime image
[VERIFY] started without DATABASE_URL -> exit 2: [config] DATABASE_URL is not set. Example: postgresql://user:password@db:5432/shopstream
[VERIFY] tests in the dev image: 17 passed, 1 warning in 0.87s
PASS  Lesson 5 complete. Your completion code: SHOP0-DOCKER-4M7X

== Demo
Building the naive image (FROM python:3.12, COPY . ., dev requirements) for comparison; the first time downloads about 1 GB ...

image                              size    layers       user   start-up
shopstream-api:naive            1694 MB         9       root     1.01 s
shopstream-api:day5              236 MB         9       shop     2.32 s

"Works on my machine": the same image, started three ways
1) no DATABASE_URL:
   [config] DATABASE_URL is not set. Example: postgresql://user:password@db:5432/shopstream
2) DATABASE_URL pointing at localhost (works on your laptop, not in a container):
   [config] cannot reach the database at localhost after 3 tries: connection failed: connection to server at "127.0.0.1", port 5432 failed: Connection refused. Inside a container, localhost is the container itself: use the database service name (db).
3) DATABASE_URL pointing at the db service on the compose network:
   [config] database at db reachable
```

## Try it yourself

```bash
docker image ls shopstream-api
```

```bash
docker inspect --format '{{.State.Health.Status}}' $(cd shopstream-api && docker compose -p shopstream-api ps -q api)
```

```bash
docker run --rm shopstream-api:day5   # no DATABASE_URL: one clear line, exit 2
```

## Verify and get your completion code

```bash
bash verify.sh
```

Checks the API answers from the runtime image, the image is under 350 MB, runs as `shop`, reports healthy, has no pytest inside and stops with a clear message without DATABASE_URL; then runs the tests in the dev image. On success it prints:

```text
PASS  Lesson 5 complete. Your completion code: SHOP0-DOCKER-4M7X
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
