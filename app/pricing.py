"""Prices are money: Decimal, never float, and rounded once, to the cent, half up.

quote() is a pure function (no database, no HTTP), which makes it the easiest thing in the app to test.
Rules:
  - SAVE10 takes 10% off the subtotal.
  - FLAT5 takes 5.00 off, only when the subtotal is at least 25.00.
  - Unknown codes are rejected.
  - Sales tax of 8.25% is charged on the discounted subtotal.
"""
from decimal import ROUND_HALF_UP, Decimal

TAX_RATE = Decimal("0.0825")
CENT = Decimal("0.01")
FLAT5_MINIMUM = Decimal("25.00")


class UnknownCode(ValueError):
    pass


def money(x: Decimal) -> Decimal:
    return x.quantize(CENT, rounding=ROUND_HALF_UP)


def discount_for(subtotal: Decimal, code: str | None) -> Decimal:
    if not code:
        return Decimal("0.00")
    if code == "SAVE10":
        return money(subtotal * Decimal("0.10"))
    if code == "FLAT5":
        return Decimal("5.00") if subtotal >= FLAT5_MINIMUM else Decimal("0.00")
    raise UnknownCode(code)


def quote(lines: list[tuple[Decimal, int]], code: str | None = None) -> dict:
    """lines: (unit price, quantity) pairs."""
    subtotal = money(sum((price * qty for price, qty in lines), Decimal("0")))
    discount = discount_for(subtotal, code)
    taxable = subtotal - discount
    tax = money(taxable * TAX_RATE)
    return {"subtotal": subtotal, "discount": discount, "tax": tax, "total": taxable + tax}
