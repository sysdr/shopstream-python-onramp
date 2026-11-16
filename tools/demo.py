"""Day 4 demo: how often would the buggy pricing code have charged the wrong amount?"""
import sys
from decimal import Decimal

sys.path.insert(0, "/srv")
sys.path.insert(0, "/srv/tools/bugs")
from app import pricing  # noqa: E402
import pricing_buggy  # noqa: E402

print("Every price from 1.00 to 199.99 (19,900 prices), quoted by both modules:")
print("code     wrong totals   share   largest error")
for code in (None, "SAVE10", "FLAT5"):
    wrong, worst = 0, (None, Decimal(0))
    for cents in range(100, 20000):
        price = Decimal(cents) / 100
        good, bad = pricing.quote([(price, 1)], code)["total"], pricing_buggy.quote([(price, 1)], code)["total"]
        if good != bad:
            wrong += 1
            if abs(bad - good) > abs(worst[1]):
                worst = (price, bad - good)
    print(f"{code or '(none)':8} {wrong:12,} {100 * wrong / 19900:6.1f}%   {worst[1]:+} (item at {worst[0]:.2f})")
print("\nThree of them, side by side:")
for price, code in [(Decimal("6.00"), None), (Decimal("1.15"), "SAVE10"), (Decimal("24.99"), "FLAT5")]:
    g, b = pricing.quote([(price, 1)], code)["total"], pricing_buggy.quote([(price, 1)], code)["total"]
    print(f"   {price:>6} {code or '-':6}  correct {g:>6}   buggy {Decimal(b).quantize(Decimal('0.01')):>6}")
print("The two failing tests above name these bugs before a customer ever sees them.")
