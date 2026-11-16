"""A plausible first version of app/pricing.py, with two bugs a code review could miss.

  1. Money in floats, rounded with round(): binary floats can't hold 0.1 exactly, and round() rounds half to even.
  2. FLAT5 is applied to every order, ignoring the 25.00 minimum.
The demo copies this file over app/pricing.py inside a throwaway container and runs the same tests.
"""
from decimal import Decimal

TAX_RATE = 0.0825


class UnknownCode(ValueError):
    pass


def money(x) -> Decimal:
    return Decimal(str(round(float(x), 2)))


def discount_for(subtotal, code):
    if not code:
        return 0.0
    if code == "SAVE10":
        return round(subtotal * 0.10, 2)
    if code == "FLAT5":
        return 5.0                       # bug 2: no minimum
    raise UnknownCode(code)


def quote(lines, code=None):
    subtotal = sum(float(price) * qty for price, qty in lines)          # bug 1: floats
    discount = discount_for(subtotal, code)
    tax = round((subtotal - discount) * TAX_RATE, 2)
    return {"subtotal": money(subtotal), "discount": money(discount), "tax": money(tax), "total": money(subtotal - discount + tax)}
