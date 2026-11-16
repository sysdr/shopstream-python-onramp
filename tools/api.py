"""Small HTTP helpers for the demo and the checks (standard library only)."""
import json
import os
import sys
import time
import urllib.error
import urllib.request

API = os.environ.get("API_URL", "http://api:8000")
DATABASE_URL = os.environ.get("DATABASE_URL", "")
from urllib.parse import quote  # noqa: E402


def call(method, path, body=None, timeout=10, base=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request((base or API) + path, data=data, method=method, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, raw.decode(errors="replace")


def wait_healthy(timeout=60, path="/health"):
    end = time.time() + timeout
    while time.time() < end:
        try:
            if call("GET", path, timeout=2)[0] == 200:
                return True
        except OSError:
            pass
        time.sleep(0.5)
    return False


def pct(values, p):
    v = sorted(values)
    import math
    return v[min(len(v) - 1, max(0, math.ceil(p / 100 * len(v)) - 1))]


def fail(msg):
    print(f"[FAIL] {msg}")
    sys.exit(1)
