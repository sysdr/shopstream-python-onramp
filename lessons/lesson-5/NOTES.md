# Day 5: Package it with Docker

"It works on my machine" usually means three things: a different Python, a package version nobody pinned, and a setting that only exists on one laptop. Containers fix the first two. Today you fix the third too, and you learn what a Dockerfile costs: the version most people write first produces a 1.7 GB image that runs as root. The one you build today is 236 MB, runs as an unprivileged user, reports its own health, and refuses to start with a clear message when its configuration is wrong.

## What you build

A three-stage `Dockerfile`:

```dockerfile
FROM python:3.12-slim AS deps          # install dependencies into /venv
RUN python -m venv /venv
COPY requirements.txt .
RUN /venv/bin/pip install -r requirements.txt

FROM python:3.12-slim AS runtime       # what gets deployed
COPY --from=deps /venv /venv
COPY app/ app/
COPY migrations/ migrations/
USER shop                              # not root
HEALTHCHECK CMD python -c "...urlopen('http://127.0.0.1:8000/health')..."
CMD ["sh", "-c", "python -m app.check_config && exec uvicorn app.main:app --host 0.0.0.0 --port 8000"]

FROM runtime AS dev                    # tests and tools: runtime + pytest; never deployed
```

Plus:

- **`requirements.txt`** (runtime, pinned) and **`requirements-dev.txt`** (adds pytest, httpx, coverage).
- **`.dockerignore`** so `.git`, caches and `.env` never enter an image.
- **`app/check_config.py`**: runs before the server. No `DATABASE_URL` → exit 2 with one line. Database unreachable after 15 tries → exit 3 with a hint.
- **Compose** uses `target: runtime` for the API and `target: dev` for the tools container, and gives Postgres a named volume so data survives `docker compose down`.

## What we measured

| Image | Size | Runs as | Start-up |
|---|---|---|---|
| Naive: `FROM python:3.12`, `COPY . .`, dev requirements | **1,694 MB** | root | 1.01 s |
| Day 5 runtime stage | **236 MB** | shop (uid 10001) | 2.32 s |

The image is **7× smaller**: the slim base drops compilers and docs you never use at runtime, and the multi-stage build leaves pip's leftovers and the test tools behind. Smaller images pull faster on every deploy and contain fewer packages that can have vulnerabilities. Verify checks that `pytest` isn't in the runtime image at all.

Start-up is about 1.3 seconds slower. That second is `check_config` connecting to the database before the web server starts — a trade we choose on purpose, because the alternative is a container that starts "fine" and fails on its first request.

**"Works on my machine"**, the same image started three ways:

```text
1) no DATABASE_URL:
   [config] DATABASE_URL is not set. Example: postgresql://user:password@db:5432/shopstream
2) DATABASE_URL pointing at localhost:
   [config] cannot reach the database at localhost after 3 tries: ... Connection refused.
   Inside a container, localhost is the container itself: use the database service name (db).
3) DATABASE_URL pointing at db on the compose network:
   [config] database at db reachable
```

Case 2 is the classic: `localhost:5432` works when Python runs on your laptop next to Postgres, and fails in a container, where `localhost` means the container itself. One clear line beats a 40-line traceback ten seconds later.

## Health checks

`HEALTHCHECK` makes Docker call `/health` every 5 seconds. The container's state goes from *starting* to *healthy*, or to *unhealthy* after three failures. Compose, orchestrators and load balancers use that state to decide when to send traffic and when to restart. Verify checks that the API container reports `healthy`.

## Try it

Run these from the `shopstream-api` folder that `start.sh` created, while the lesson is running.

```bash
docker image ls shopstream-api
docker inspect --format '{{.State.Health.Status}}' $(docker compose -p shopstream-api ps -q api)
docker run --rm shopstream-api:day5
docker history shopstream-api:day5
```

## Say it in an interview

**Q: How do you make a Python Docker image small and safe?**
A: A slim base, a multi-stage build that installs dependencies in one stage and copies only the result, pinned versions, a `.dockerignore`, no build or test tools in the final stage, and a non-root user.

**Q: Why shouldn't a container run as root?**
A: If the app is compromised, the attacker gets root inside the container, which makes escaping to the host or abusing mounted volumes much easier. A fixed unprivileged user limits the damage.

**Q: What does "12-factor config" mean for containers?**
A: Configuration comes from the environment, not from files baked into the image, so the same image runs in every environment. Validate it at start-up and fail fast with a clear message.

## Recap

- Three stages: dependencies, a slim runtime, a dev image for tests.
- Measured: 1,694 MB as root versus 236 MB as user `shop`; pytest absent from the runtime image.
- Start-up checks config and the database first: about 1.3 s slower, never a half-working container.
- Inside a container, `localhost` is the container.

## Challenge (10 minutes)

Switch the runtime base to `python:3.12-alpine` and compare the size. Does the image still build and pass verify?

<details class="sdc-hint"><summary>Hint 1</summary>Change both `FROM python:3.12-slim` lines to `python:3.12-alpine` and rebuild with `docker compose -p shopstream-api build api`.</details>

<details class="sdc-hint"><summary>Hint 2</summary>Alpine uses musl instead of glibc; `useradd` doesn't exist there (use `adduser -D -u 10001 shop`).</details>

<details class="sdc-hint"><summary>Hint 3</summary>`psycopg[binary]` wheels for musl exist for recent versions; if a package must compile, the build needs `apk add build-base` in the deps stage only.</details>
