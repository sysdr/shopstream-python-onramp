#!/usr/bin/env bash
# Run the suite against the real pricing module, then against tools/bugs/pricing_buggy.py.
# Runs inside a throwaway tools container (docker compose run --rm), so copying the buggy file changes nothing else.
set -u
cd /srv
cd /srv
echo "--- the real app/pricing.py"
python -m pytest -q --cov=app --cov-report=term --cov-fail-under=80 -p no:cacheprovider 2>&1 | grep -E "passed|failed|TOTAL|pricing.py|main.py|Required" | tail -6
GOOD=${PIPESTATUS[0]}
echo "--- tools/bugs/pricing_buggy.py copied over app/pricing.py"
cp tools/bugs/pricing_buggy.py app/pricing.py
python -m pytest -q -p no:cacheprovider tests/test_pricing.py 2>&1 | grep -E "^FAILED|passed|failed" | sed 's/ - .*//' | tail -8
BAD=${PIPESTATUS[0]}
echo "real module: exit $GOOD   buggy module: exit $BAD"
[ "$GOOD" -eq 0 ] && [ "$BAD" -ne 0 ]
