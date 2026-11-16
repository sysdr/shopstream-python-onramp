"""Production server settings: several worker processes, each running the app with uvicorn."""
import os

bind = "0.0.0.0:8000"
workers = int(os.environ.get("WEB_CONCURRENCY", "2"))
worker_class = "uvicorn.workers.UvicornWorker"
timeout = 30
graceful_timeout = 20
keepalive = 5
accesslog = None  # the app writes its own JSON access log (see access_log in app/main.py)
errorlog = "-"
