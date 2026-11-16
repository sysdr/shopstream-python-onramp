"""Unit tests for app/pricing.py: no database, no HTTP, they run in milliseconds."""
from decimal import Decimal as D

import pytest

from app import pricing


def test_no_code():
    q = pricing.quote([(D("19.99"), 1)])
    assert q == {"subtotal": D("19.99"), "discount": D("0.00"), "tax": D("1.65"), "total": D("21.64")}


def test_cents_add_up_exactly():
    # 0.10 + 0.20 is 0.30000000000000004 in floats; ten of them must still be exactly 3.00
    q = pricing.quote([(D("0.10"), 10), (D("0.20"), 10)])
    assert q["subtotal"] == D("3.00")


def test_half_cent_rounds_up():
    # 8.25% of 6.00 is exactly 0.495: money rounds half up to 0.50
    q = pricing.quote([(D("6.00"), 1)])
    assert (q["tax"], q["total"]) == (D("0.50"), D("6.50"))


def test_save10():
    q = pricing.quote([(D("89.00"), 1)], "SAVE10")
    assert (q["discount"], q["total"]) == (D("8.90"), D("86.71"))


@pytest.mark.parametrize("price,expected_discount", [(D("24.99"), D("0.00")), (D("25.00"), D("5.00"))])
def test_flat5_needs_a_25_minimum(price, expected_discount):
    assert pricing.quote([(price, 1)], "FLAT5")["discount"] == expected_discount


def test_unknown_code_is_rejected():
    with pytest.raises(pricing.UnknownCode):
        pricing.quote([(D("10.00"), 1)], "FREE100")


def test_total_is_subtotal_minus_discount_plus_tax():
    for lines, code in [([(D("14.50"), 3)], None), ([(D("129.99"), 2)], "SAVE10"), ([(D("34.00"), 1)], "FLAT5")]:
        q = pricing.quote(lines, code)
        assert q["total"] == q["subtotal"] - q["discount"] + q["tax"]
