"""Find the quick tunnel's public URL in its logs (passed as argv[1]) and compare latency: local vs public."""
import sys
import time

import api

url = sys.argv[1].rstrip("/") if len(sys.argv) > 1 else ""
if not url:
    print("[WARN] no public URL: the tunnel did not start (it needs outbound internet to Cloudflare)")
    sys.exit(0)


def timed(base, n=20):
    lat, ok = [], 0
    for i in range(n):
        t = time.perf_counter()
        try:
            s, _ = api.call("GET", f"/products/{i % 5 + 1}", base=base, timeout=15)
            ok += s == 200
        except OSError:
            pass
        lat.append((time.perf_counter() - t) * 1000)
    return ok, api.pct(lat, 50), api.pct(lat, 95)


for _ in range(30):  # a new quick tunnel takes a few seconds to answer
    try:
        if api.call("GET", "/health/ready", base=url, timeout=10)[0] == 200:
            break
    except OSError:
        pass
    time.sleep(2)
for label, base in [("local (inside Docker)", api.API), ("public URL", url)]:
    ok, p50, p95 = timed(base)
    print(f"   {label:24} {ok}/20 ok   p50 {p50:6.1f} ms   p95 {p95:6.1f} ms")
