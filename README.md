# Python Backend Basics: Build the ShopStream API

Source code for the free course **[Python Backend Basics: Build the ShopStream API](https://systemdrd.com/courses/python-backend-basics-build-the-shopstream-api/)** on systemdrd.com — step 0 of the free ShopStream path.

Six lessons take you from a first FastAPI endpoint to a production-ready service with a public URL. Every lesson builds something, breaks it on purpose and measures the result: SQL injection against a string-built query, 50 buyers racing for 10 items, a float-based pricing bug, a 1.7 GB Docker image, and a deploy with a database password that isn't in the code.

- **Docker with Compose** is all you need. Python 3.12, FastAPI, Postgres 16, pytest and the tools run in containers.
- The numbers in the notes come from real runs of these scripts.

## Lessons

Each lesson folder is self-contained: `start.sh` writes the complete project up to that day into `./shopstream-api`, builds and starts it, runs the tests, verifies it and runs a measured demo. `README.md` is the implementation guide, `NOTES.md` the lesson notes, `diagrams/` the diagrams.

| Day | Lesson | What you measure |
|---|---|---|
| 1 | [Your first API in 20 minutes](lessons/lesson-1) | p50 2.2 ms; invalid input rejected with every bad field named |
| 2 | [Store it in Postgres](lessons/lesson-2) | string-built search leaks every row; an index makes a lookup 170x faster |
| 3 | [Orders without overselling](lessons/lesson-3) | 50 buyers, 10 items: naive oversells 40, atomic UPDATE 0 |
| 4 | [Tests that catch real bugs](lessons/lesson-4) | 17 tests, 89% coverage; the buggy pricing gets 2,407 FLAT5 totals wrong |
| 5 | [Package it with Docker](lessons/lesson-5) | 1,694 MB as root versus 236 MB as a non-root user |
| 6 | [Put it online](lessons/lesson-6) | 2 workers, readiness, secrets in .env; a public URL at p50 204 ms |

## Quick start

```bash
git clone https://github.com/sysdr/shopstream-python-onramp.git
cd shopstream-python-onramp/lessons/lesson-1
bash start.sh     # build, start, tests, verify, demo
bash stop.sh
```

API: http://localhost:8201/products, interactive docs: http://localhost:8201/docs. `bash test_all.sh` runs all six lessons (about 8 minutes).

## The finished project

The repository root holds the final code (Day 6). Run it with:

```bash
printf 'DB_PASSWORD=%s\n' "$(LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c 24)" > .env
docker compose -p shopstream-api up -d --build
docker compose -p shopstream-api run --rm -T -w /srv tools python -m pytest -q
docker compose -p shopstream-api --profile public up -d tunnel   # optional public URL
docker compose -p shopstream-api down
```

| Path | Role |
|---|---|
| `app/main.py` | FastAPI app: products, search, orders, quotes, health and readiness, JSON access log |
| `app/pricing.py` | Decimal pricing with discount codes and tax |
| `app/migrate.py`, `migrations/` | versioned SQL migrations |
| `app/check_config.py`, `app/config.py` | configuration from the environment, fail fast |
| `Dockerfile`, `gunicorn.conf.py`, `compose.yaml` | multi-stage image, production server, stack |
| `tests/` | 17 tests (unit and API against a throwaway database) |
| `tools/` | demos, checks, the buggy pricing module for Day 4 |

## License

MIT
