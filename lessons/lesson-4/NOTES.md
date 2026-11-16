# Day 4: Tests that catch real bugs

A pricing bug is the worst kind: nothing crashes, nobody gets an error, and every day some customers pay the wrong amount. Today you write ShopStream's pricing rules, test them with pytest, and run the same tests against a plausible first version of the code. The tests catch two real bugs — and a demo counts how many customers each bug would have overcharged or undercharged.

## What you build

- **`app/pricing.py`**: a pure function, `quote(lines, code)`, returning subtotal, discount, tax and total in `Decimal`, rounded once to the cent, half up. Rules: `SAVE10` takes 10% off; `FLAT5` takes 5.00 off orders of at least 25.00; unknown codes are rejected; 8.25% tax on the discounted subtotal.
- **`POST /cart/quote`** and order totals stored with each order (migration 004).
- **17 tests at two levels**: unit tests for pricing (no database, milliseconds) and API tests with FastAPI's `TestClient` against a throwaway Postgres database, `shopstream_test`, created fresh for each run.
- **Coverage** with `pytest-cov`, and a gate: the run fails below 80%.
- **`tools/bugs/pricing_buggy.py`**: the version many people write first — floats and `round()`, and a `FLAT5` that forgets the minimum.

## Tests that pin down the rules

```python
def test_half_cent_rounds_up():
    # 8.25% of 6.00 is exactly 0.495: money rounds half up to 0.50
    q = pricing.quote([(D("6.00"), 1)])
    assert (q["tax"], q["total"]) == (D("0.50"), D("6.50"))


@pytest.mark.parametrize("price,expected_discount", [(D("24.99"), D("0.00")), (D("25.00"), D("5.00"))])
def test_flat5_needs_a_25_minimum(price, expected_discount):
    assert pricing.quote([(price, 1)], "FLAT5")["discount"] == expected_discount
```

Good tests check the edges: exactly half a cent, one cent below a threshold and exactly at it. That's where bugs live.

## What we measured

The real module: **17 passed, coverage 89%** (`pricing.py` 100%, `main.py` 87%).

The buggy module, same tests:

```text
FAILED tests/test_pricing.py::test_half_cent_rounds_up
FAILED tests/test_pricing.py::test_flat5_needs_a_25_minimum[price0-expected_discount0]
2 failed, 6 passed
```

How much would those bugs have cost? The demo quotes every price from 1.00 to 199.99 with both modules:

| Code | Wrong totals (of 19,900) | Share | Largest error |
|---|---|---|---|
| none | 8 | 0.04% | −0.01 |
| SAVE10 | 464 | 2.3% | +0.02 |
| FLAT5 | 2,407 | 12.1% | −5.42 |

The float bug is small and rare: `round()` rounds half to even, and a float can't hold 0.495 exactly, so 6.00 became 6.49 instead of 6.50. A cent here and there — until an auditor or a reconciliation job notices. The missing minimum is big: every order under 25.00 got 5.00 off, and a 1.04 item came out negative.

Six of the eight pricing tests pass against the buggy code. That's the point of testing edges: the happy path looks fine.

## Why a throwaway database

API tests that hit a shared database interfere with each other and with your data. `tests/conftest.py` drops and recreates `shopstream_test` at the start of every run, and the app's migrations build the schema there — so the tests also prove the migrations work from zero.

## Try it

Run these from the `shopstream-api` folder that `start.sh` created, while the lesson is running.

```bash
docker compose -p shopstream-api run --rm -T -w /srv tools python -m pytest -q
docker compose -p shopstream-api run --rm -T -w /srv tools bash tools/run_tests.sh
curl -s -X POST localhost:8201/cart/quote -H 'Content-Type: application/json' -d '{"lines":[{"sku":"SKU-1002","qty":2}],"discount_code":"FLAT5"}'
```

## Say it in an interview

**Q: What makes a test valuable?**
A: It fails when the behaviour is wrong and passes when it's right, independent of implementation details. Tests at boundaries (thresholds, rounding, empty input) catch far more bugs than happy-path tests.

**Q: Unit tests or integration tests?**
A: Both. Pure logic like pricing gets fast unit tests; the API gets integration tests against a real database, because mocks hide SQL and transaction bugs.

**Q: Is 100% coverage the goal?**
A: No. Coverage shows what never runs in tests; it can't show that the assertions are right. A floor (here 80%) stops untested code creeping in; the edge cases are what make tests catch bugs.

## Recap

- Pricing is a pure function in `Decimal`, rounded once, half up.
- 17 tests, 89% coverage, a throwaway Postgres for API tests.
- The buggy module failed 2 tests; across 19,900 prices per code, it got 8, 464 and 2,407 totals wrong.
- Test the edges: half cents and thresholds.

## Challenge (10 minutes)

Add a `BULK` code: 15% off when the cart has 10 or more items. Write the tests first, watch them fail, then implement it.

<details class="sdc-hint"><summary>Hint 1</summary>`discount_for` only sees the subtotal; pass the item count too, or compute it in `quote`.</details>

<details class="sdc-hint"><summary>Hint 2</summary>Test 9 items (no discount), exactly 10 (discount) and a price where 15% lands on half a cent.</details>

<details class="sdc-hint"><summary>Hint 3</summary>Run `python -m pytest -q tests/test_pricing.py` inside the tools container: it takes under a second.</details>
