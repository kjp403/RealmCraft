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
## Gold shops pay this fraction of their listed buy price when the player sells
## that same item back (health / mana / prayer potions). Fallback is
## [member Item.vendor_value]. Raised from 0.25 -- potions are being pulled from
## chest loot so Farming/Herblore crafting is the intended supply, and 25% back
## wasn't a real money-maker for the players who actually brew them.
const BUYBACK_RATE: float = 0.5


## Capabilities are DERIVED from the data (no parallel enum to contradict it —
## a stale `trades` flag once silently made six shops refuse selling).
func allows_buying() -> bool:
	return entries != null and not entries.is_empty()


## True if this vendor takes anything from the player (drives the Sell tab).
## Defensive against shops authored before the accepted_trades field existed
## (where it can deserialize as null). Gold-stocked buybacks (potions at a
## dungeon shop that otherwise refuses junk) also count.
func has_trades() -> bool:
	var has_specialty: bool = accepted_trades != null and not accepted_trades.is_empty()
	if has_specialty or buys_vendor_priced:
		return true
	if entries == null:
		return false
	for entry: ShopEntry in entries:
		if entry != null and can_vendor_buy(entry.item):
			return true
	return false


## Gold paid per unit when this vendor buys [param item]. Health / mana / prayer
## potions sell for [constant BUYBACK_RATE] of this shop's gold buy price when
## stocked, else their [member Item.vendor_value]. Other goods stay on vendor_value.
func buyback_gold(item: Item) -> int:
	if item == null or item.is_currency:
		return 0
	var item_id: int = int(item.get_meta(&"id", 0))
	if item_id <= 0:
		return 0
	if _is_potion_buyback(item):
		var stock: Dictionary = entry_for(item_id)
		if not stock.is_empty() and int(stock.get("currency_id", 0)) == Economy.gold_id():
			return maxi(1, roundi(float(stock["price"]) * BUYBACK_RATE))
	return maxi(0, item.vendor_value)


## True when the Sell tab / shop.sell.item may take [param item] for gold.
## General merchants buy any vendor-priced junk; specialty shops still buy
## back health / mana potions they stock for gold (Cave Master).
func can_vendor_buy(item: Item) -> bool:
	if buyback_gold(item) <= 0:
		return false
	if buys_vendor_priced:
		return true
	if not _is_potion_buyback(item):
		return false
	var item_id: int = int(item.get_meta(&"id", 0))
	var stock: Dictionary = entry_for(item_id)
	return not stock.is_empty() and int(stock.get("currency_id", 0)) == Economy.gold_id()


static func _is_potion_buyback(item: Item) -> bool:
	var potion: ConsumableItem = item as ConsumableItem
	if potion == null:
		return false
	return potion.cooldown_category == &"health_potion" \
			or potion.cooldown_category == &"mana_potion" \
			or potion.cooldown_category == &"prayer_potion" \
			or potion.cooldown_category == &"potion"


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
