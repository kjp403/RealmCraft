class_name ShopResource
extends Resource
## Editor-authored shop definition. Attach one to an NPC's ShopInteraction —
## either inline (a sub-resource on the NPC) or a shared .tres dragged into the
## interaction's `shop` field. The server resolves the shop from the merchant
## NPC's giver_key() (its NPCResource filename slug) via Map.shops, the same way
## quests resolve their giver; the client renders the catalog from the resource
## carried in the menu arg, so no registry id, Generate step, or index is needed.

@export var shop_name: String
## Default currency the whole shop trades in (e.g. event tokens for a fair
## stall). Leave empty for gold. A per-entry [member ShopEntry.currency_item]
## overrides this for that one item.
@export var currency_item: Item
@export var entries: Array[ShopEntry]
## What this vendor TAKES from the player — barter bundles OR gold buy-backs
## ("give 1 Bone Sword, receive 4 gold" is just a trade whose payout is gold).
## Specialty rates; items listed here prefer this over flat [member Item.vendor_value].
@export var accepted_trades: Array[ShopTrade]
## When true, the Sell tab also lists any owned item with [member Item.vendor_value] > 0
## (gatherable junk-sell). Specialty [member accepted_trades] still take priority for
## matching item ids. Default on so general merchants accept materials.
@export var buys_vendor_priced: bool = true
## Potions no longer have a vendor buyback rate. They are a PLAYER good now:
## stocked only by the dungeon vendor, and worth so little to an NPC (every
## potion's vendor_value is capped at 100g) that the Trading Post is the only
## sane place to sell one. Everything sells for a flat [member Item.vendor_value].


## Capabilities are DERIVED from the data (no parallel enum to contradict it —
## a stale `trades` flag once silently made six shops refuse selling).
func allows_buying() -> bool:
	return entries != null and not entries.is_empty()


## True if this vendor takes anything from the player (drives the Sell tab).
## Defensive against shops authored before the accepted_trades field existed
## (where it can deserialize as null).
func has_trades() -> bool:
	var has_specialty: bool = accepted_trades != null and not accepted_trades.is_empty()
	return has_specialty or buys_vendor_priced


## Gold paid per unit when this vendor buys [param item]: its flat
## [member Item.vendor_value], whatever this shop charges for the same thing.
## Pricing a buyback off the shop's own sell price is what let a potion the
## dungeon vendor lists at 1,000g pay 500g back — the exact NPC round-trip the
## Trading Post exists to replace.
func buyback_gold(item: Item) -> int:
	if item == null or item.is_currency:
		return 0
	if int(item.get_meta(&"id", 0)) <= 0:
		return 0
	return maxi(0, item.vendor_value)


## True when the Sell tab / shop.sell.item may take [param item] for gold.
## General merchants buy any vendor-priced junk; specialty vendors take nothing.
func can_vendor_buy(item: Item) -> bool:
	return buys_vendor_priced and buyback_gold(item) > 0


## { "price": int, "currency_id": int } for one item, or {} if not sold here.
## currency_id resolves entry → shop → gold (first non-null wins).
func entry_for(item_id: int) -> Dictionary:
	if entries == null:
		return {}
	for entry: ShopEntry in entries:
		if entry and entry.item and int(entry.item.get_meta(&"id", 0)) == item_id:
			return {"price": entry.price, "currency_id": _resolve_currency_id(entry.currency_item)}
	return {}


## The currency id to charge for [param entry_currency]: the per-entry currency
## if set, else the shop's default currency, else gold.
func _resolve_currency_id(entry_currency: Item) -> int:
	if entry_currency != null:
		return int(entry_currency.get_meta(&"id", 0))
	if currency_item != null:
		return int(currency_item.get_meta(&"id", 0))
	return Economy.gold_id()


## The shop's display currency id (default for the UI's balance + price chips).
func display_currency_id() -> int:
	if currency_item != null:
		return int(currency_item.get_meta(&"id", 0))
	return Economy.gold_id()
