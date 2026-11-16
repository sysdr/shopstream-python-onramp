# Day 6: Put it online

Your API works on your laptop. Today it runs the way a production service does — several worker processes, a database password that isn't in the code, health checks a load balancer can use, one JSON log line per request, the demo-only endpoints switched off — and then you put it on the internet with a public https URL you can open on your phone. No cloud account needed.

## What you build

- **gunicorn with 2 uvicorn workers** (`gunicorn.conf.py`, `WEB_CONCURRENCY`). One process per CPU core is the usual start; if a worker crashes, the manager starts a new one.
- **Migrations run once before the workers start** (`python -m app.migrate` in the container's command), so two workers never race to change the schema.
- **`/health` and `/health/ready`**: liveness (the process answers) and readiness (it can reach the database). The Docker health check uses readiness.
- **Secrets from `.env`**: `start.sh` generates a random 24-character database password into `.env`, which is listed in `.gitignore` and `.dockerignore`. `compose.yaml` refuses to start without it (`${DB_PASSWORD:?...}`).
- **A JSON access log**: one line per request with method, path, status and milliseconds.
- **Demo endpoints off**: the string-built search from Day 2 and the naive orders from Day 3 now return 404.
- **A Cloudflare quick tunnel** (`cloudflared`, compose profile `public`): a temporary `https://<random>.trycloudflare.com` URL that forwards to your API.

## The production command

```dockerfile
CMD ["sh", "-c", "python -m app.check_config && python -m app.migrate && exec gunicorn -c gunicorn.conf.py app.main:app"]
```

Check configuration, migrate, then `exec` the server so it becomes PID 1 and receives the stop signal from Docker directly — that's what lets it finish in-flight requests on shutdown.

## What we measured

Verify on Docker Desktop:

```text
GET /health/ready -> 200 {'status': 'ready', 'version': '1.0.0'}
demo endpoints in production: search-unsafe -> 404, orders?mode=naive -> 404
api runs as uid 10001 with 3 gunicorn processes (1 manager + 2 workers)
database password comes from .env (not in compose.yaml, ignored by git and Docker)
```

Through the tunnel, 20 requests each for `GET /products/{id}`:

| From | Succeeded | p50 | p95 |
|---|---|---|---|
| Local (inside Docker) | 20/20 | 3.9 ms | 6.1 ms |
| Public URL (the internet, via Cloudflare) | 20/20 | 204 ms | 414 ms |

The public path is about 50 times slower than the local one, and none of it is your code: it's the network round trip to Cloudflare's edge and back. That's why latency budgets are set from the user's side, and why caches and CDNs sit close to users.

Restarting the API container, as a deploy would: the orders were still there (data lives in the `pgdata` volume), and the API was ready again after about **4 seconds**. During those seconds requests fail. One container can't be replaced without a gap — running two behind a load balancer and replacing them one at a time is exactly where Step 1 of the path, *Scale ShopStream*, begins.

## Production checklist

| Item | Where |
|---|---|
| Several workers, restart on crash | gunicorn |
| Readiness separate from liveness | `/health/ready` |
| Secrets outside the code and image | `.env`, `.gitignore`, `.dockerignore` |
| Non-root, minimal image | Day 5 Dockerfile |
| Structured logs | JSON access log |
| Debug and demo code off | `ALLOW_DEMO_ENDPOINTS` unset |
| Schema changes before traffic | migrate in the start command |

## Try it

Run these from the `shopstream-api` folder that `start.sh` created, while the lesson is running.

```bash
docker compose -p shopstream-api logs tunnel | grep trycloudflare      # your public URL
docker compose -p shopstream-api logs --no-log-prefix api | tail -3     # JSON access log
docker compose -p shopstream-api stop tunnel                            # stop sharing
```

The quick-tunnel URL is public: anyone with it can call your API while it runs. Stop the tunnel when you're done.

## Say it in an interview

**Q: What's the difference between liveness and readiness?**
A: Liveness says the process is alive (restart it if not). Readiness says it can serve traffic right now, including its dependencies (stop sending it traffic if not, but don't restart it).

**Q: Where do secrets go?**
A: In the environment at run time, from a secret store or an untracked file — never in the code, the image or the repository. Rotate them, and use a different one per environment.

**Q: Why run migrations as a separate step?**
A: So they run once per deploy, before new code that needs them serves traffic, instead of every worker or instance racing to apply them.

## Recap

- gunicorn with 2 workers, migrations once, readiness checks, JSON logs, secrets from `.env`, demo endpoints off.
- Measured: local p50 3.9 ms; through the public tunnel p50 204 ms.
- A restart kept all data and took about 4 s, with requests failing meanwhile: the next step is two instances behind a load balancer.

## Challenge (10 minutes)

Set `WEB_CONCURRENCY=4` in `.env`, restart, and check how many gunicorn processes run. Does the local p50 change for one request at a time?

<details class="sdc-hint"><summary>Hint 1</summary>Edit `shopstream-api/.env`, then `docker compose -p shopstream-api up -d api`.</details>

<details class="sdc-hint"><summary>Hint 2</summary>Count processes with the same command verify uses, or run `bash ../verify.sh`.</details>

<details class="sdc-hint"><summary>Hint 3</summary>One request at a time never needs more than one worker; extra workers help only under concurrent load — try the Day 3 buyers with 50 threads.</details>
