class_name PeddlerLedger
## The per-account daily purchase allowance: ONE of each stocked good, per
## character, per UTC day.
##
## The ledger lives on [member PlayerResource.daily_peddler_purchases] (a
## stock_id -> true set) next to [member PlayerResource.peddler_purchase_day],
## the UTC date it was written for. Rollover is LAZY: nothing runs at midnight,
## the day is simply compared on every read and a stale ledger is cleared in
## place. That is the same shape [DailyQuestManager] uses, and it is what makes
## the reset correct for a character who was offline across the boundary — a
## scheduled sweep would only ever reach players who happened to be online.
##
## Keyed by the stock id, not by an item registry id, so retiring an item from
## the catalog cannot resurrect somebody's spent allowance.


## Clear [param resource]'s ledger if it was written for a different UTC day.
## Returns true if it rolled over. Safe (and cheap) to call on every read.
static func roll_over(resource: PlayerResource, date: String) -> bool:
	if resource == null:
		return false
	if resource.peddler_purchase_day == date:
		return false
	resource.peddler_purchase_day = date
	resource.daily_peddler_purchases = {}
	return true


## True when [param resource] has already bought [param stock_id] today.
static func has_bought(resource: PlayerResource, stock_id: String, date: String) -> bool:
	if resource == null:
		return false
	roll_over(resource, date)
	return bool(resource.daily_peddler_purchases.get(stock_id, false))


## Record a purchase. Call only once the gold has actually moved — a recorded
## purchase the player did not receive is an allowance burned for nothing.
static func record(resource: PlayerResource, stock_id: String, date: String) -> void:
	if resource == null:
		return
	roll_over(resource, date)
	resource.daily_peddler_purchases[stock_id] = true


## The stock ids [param resource] has spent today, for the shop window's
## SOLD OUT states.
static func bought_today(resource: PlayerResource, date: String) -> Array:
	if resource == null:
		return []
	roll_over(resource, date)
	return resource.daily_peddler_purchases.keys()


## Wire shape for persistence: {"day": String, "bought": {id: true}}.
static func save_state(resource: PlayerResource) -> Dictionary:
	if resource == null:
		return {}
	return {
		"day": resource.peddler_purchase_day,
		"bought": resource.daily_peddler_purchases,
	}


## Read back [method save_state]. A ledger from an older day is dropped on load
## rather than carried in and cleared later — so a character who logs in on a new
## day is never momentarily holding yesterday's spent allowance.
static func load_state(resource: PlayerResource, raw: Variant, date: String) -> void:
	if resource == null:
		return
	resource.peddler_purchase_day = date
	resource.daily_peddler_purchases = {}
	if raw is not Dictionary:
		return
	var data: Dictionary = raw as Dictionary
	if str(data.get("day", "")) != date:
		return
	var bought: Variant = data.get("bought", {})
	if bought is not Dictionary:
		return
	for key: Variant in bought as Dictionary:
		if bool((bought as Dictionary)[key]):
			resource.daily_peddler_purchases[str(key)] = true
