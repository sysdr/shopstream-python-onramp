"""Print the seconds between two Docker timestamps (RFC 3339 with nanoseconds)."""
import re
import sys
from datetime import datetime


def parse(ts):
    ts = re.sub(r"(\.\d{6})\d*", r"\1", ts.strip()).replace("Z", "+00:00")
    return datetime.fromisoformat(ts)


print(f"{(parse(sys.argv[2]) - parse(sys.argv[1])).total_seconds():.2f}")
