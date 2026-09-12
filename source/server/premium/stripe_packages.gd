class_name StripePackages
## The Ark Coin storefront, and the ONLY authority on how many coins a payment is
## worth.
##
## COINS ARE DERIVED FROM THE AMOUNT STRIPE SAYS WAS PAID, never from anything
## the buyer or the page could influence. A webhook body is attacker-shaped input
## until its signature is checked, and even a genuine one carries metadata that
## originated in a URL. `amount_total` is what Stripe actually captured, in the
## smallest currency unit, so mapping that to coins here means the worst a
## tampered link can do is charge the wrong price - never mint coins for free.
##
## An amount that is not in this table is deliberately worth ZERO coins. A
## payment for an unrecognised amount is a misconfigured Payment Link or a
## currency mismatch, and the safe failure is "credit nothing and shout" rather
## than "guess".

const CURRENCY: String = "usd"

## amount_total (cents) -> Ark Coins.
const BY_AMOUNT_CENTS: Dictionary = {
	249: 250,
	499: 500,
	999: 1000,
	2499: 2500,
}

## Display order for the storefront. Kept beside the price map so a package can
## never appear on the page without the webhook knowing what it is worth.
const ORDER: Array[int] = [249, 499, 999, 2499]


## Coins for a captured amount, or 0 when the amount is not one of ours.
static func coins_for_cents(amount_total: int) -> int:
	return int(BY_AMOUNT_CENTS.get(amount_total, 0))


## Rows for the storefront page: cents, coins, and a formatted price.
static func storefront() -> Array:
	var out: Array = []
	for cents: int in ORDER:
		out.append({
			"cents": cents,
			"coins": int(BY_AMOUNT_CENTS[cents]),
			"price": price_label(cents),
		})
	return out


static func price_label(cents: int) -> String:
	return "$%d.%02d" % [cents / 100, cents % 100]


## True when the currency on the session is the one the table is priced in.
## 2499 JPY is not $24.99, and crediting 2500 coins for it would be a gift.
static func currency_ok(currency: String) -> bool:
	return currency.strip_edges().to_lower() == CURRENCY
