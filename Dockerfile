# syntax=docker/dockerfile:1
# Stage 1: install dependencies into a virtualenv (build tools stay in this stage).
FROM python:3.12-slim AS deps
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
RUN python -m venv /venv
COPY requirements.txt .
RUN /venv/bin/pip install -r requirements.txt

# Stage 2: the runtime image: slim base, the virtualenv, the code, a non-root user, a health check.
FROM python:3.12-slim AS runtime
ENV PATH=/venv/bin:$PATH PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 RUN_MIGRATIONS_ON_START=0
RUN useradd --create-home --uid 10001 shop
WORKDIR /srv
COPY --from=deps /venv /venv
COPY app/ app/
COPY migrations/ migrations/
COPY gunicorn.conf.py .
USER shop
EXPOSE 8000
HEALTHCHECK --interval=5s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health/ready', timeout=2).status == 200 else 1)"
CMD ["sh", "-c", "python -m app.check_config && python -m app.migrate && exec gunicorn -c gunicorn.conf.py app.main:app"]

# Stage 3: tests and tools: the runtime image plus dev dependencies. Never deployed.
FROM runtime AS dev
USER root
ENV RUN_MIGRATIONS_ON_START=1
COPY requirements-dev.txt requirements.txt ./
RUN pip install --no-cache-dir -r requirements-dev.txt
COPY tests/ tests/
COPY tools/ tools/
RUN chown -R shop /srv
USER shop
