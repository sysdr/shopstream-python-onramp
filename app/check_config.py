"""Fail fast, with one clear line, instead of a 40-line traceback ten seconds later.

Runs before the web server starts (see CMD in the Dockerfile).
"""
import sys
import time
from urllib.parse import urlparse

import psycopg

from app.config import DATABASE_URL


def main(attempts=15):
    if not DATABASE_URL:
        print("[config] DATABASE_URL is not set. Example: postgresql://user:password@db:5432/shopstream", file=sys.stderr)
        return 2
    host = urlparse(DATABASE_URL).hostname
    for i in range(attempts):
        try:
            psycopg.connect(DATABASE_URL, connect_timeout=2).close()
            print(f"[config] database at {host} reachable")
            return 0
        except psycopg.OperationalError as e:
            last = str(e).strip().splitlines()[0]
            time.sleep(1)
    hint = " Inside a container, localhost is the container itself: use the database service name (db)." if host in ("localhost", "127.0.0.1") else ""
    print(f"[config] cannot reach the database at {host} after {attempts} tries: {last}.{hint}", file=sys.stderr)
    return 3


if __name__ == "__main__":
    sys.exit(main(int(sys.argv[1]) if len(sys.argv) > 1 else 15))
