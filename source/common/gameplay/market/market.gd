class_name Market
## Shared rules for the player-run Trading Post (the Guild Hall market stalls).
##
## HOW IT WORKS
## Every character may run ONE store. Listing a stack ESCROWS it: the stack leaves
## the seller's bag and the `market_listings` row becomes its only home, so a stall
## keeps selling while its owner is offline and nothing can be listed twice.
##
## Payouts NEVER go straight into a bag — a sale mails the gold to the seller and
## the goods to the buyer (see MarketStore). Mail is the delivery channel precisely
## because it cannot fail on a full inventory, which is the one way a trade like
## this could otherwise eat an item.
##
## Server rules live here (not in a handler) so the client can grey out an
## unsellable item / an over-cap price before it ever sends the request, and the
## server can re-check the exact same predicate.

## Stalls a single store may have listed at once. Keeps `market.browse` payloads
## well inside the WebSocket buffer and stops one player wallpapering the board.
const MAX_LISTINGS_PER_STORE: int = 20
## Hard ceiling on a single unit price. Well below int64 overflow on
## unit_price * amount * (a stack), so a crafted request can't wrap negative.
const MAX_UNIT_PRICE: int = 100_000_000
## Cap on one buy request, mirroring shop.buy.item's MAX_BUY_AMOUNT.
const MAX_BUY_AMOUNT: int = 9999
## Longest store name a player can set.
const MAX_STORE_NAME_LENGTH: int = 24
## Listings returned by one browse/search request.
const MAX_BROWSE_LISTINGS: int = 300
## Sales shown on the board's ticker, and per item in a listing's price history.
const MAX_RECENT_TRADES: int = 30
const MAX_ITEM_TRADES: int = 12
## Window the rolling low / avg / high on each row is computed over. Long enough
## for a thin market to have data, short enough that the number still describes
## what things go for TODAY.
const PRICE_WINDOW_MS: int = 24 * 60 * 60 * 1000

## Listing lifecycle. A partial buy just decrements `amount`; the row only leaves
## ACTIVE when it empties (SOLD) or the seller pulls it (PULLED).
enum State { ACTIVE, SOLD, PULLED }


## Can this item be put on a market stall?
##
## EVERYTHING is listable except two categories, by design (owner call): quest
## items, which are bound to their owner's story and would break quest state if
## they changed hands, and currency, which is what buyers PAY with rather than
## goods you can price in gold. There is no per-item allow-list to keep in sync —
## a new item is tradeable the day it ships.
static func is_listable(item: Item) -> bool:
	if item == null:
		return false
	if item.is_currency:
		return false
	if item is QuestItem:
		return false
	return item.inventory_tab() != Item.InventoryTab.QUEST


## Why an item can't be listed, for the UI. Empty string = it can.
static func listing_block_reason(item: Item) -> String:
	if item == null:
		return "Unknown item."
	if item.is_currency:
		return "Currency can't be listed — it's what buyers pay with."
	if item is QuestItem or item.inventory_tab() == Item.InventoryTab.QUEST:
		return "Quest items are bound to you and can't be traded."
	return ""


## Trims a player-typed store name to something safe to render. Empty input falls
## back to a name derived from the owner.
static func sanitize_store_name(raw: String, owner_name: String) -> String:
	var name: String = raw.strip_edges()
	# Strip BBCode openers so a store name can't inject markup into the browse list.
	name = name.replace("[", "(").replace("]", ")")
	if name.length() > MAX_STORE_NAME_LENGTH:
		name = name.substr(0, MAX_STORE_NAME_LENGTH).strip_edges()
	if name.is_empty():
		name = "%s's Stall" % owner_name
	return name
