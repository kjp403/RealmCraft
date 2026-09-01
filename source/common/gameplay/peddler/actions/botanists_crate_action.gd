extends PeddlerAction
## Botanist's Skilling Crate: a bundle of mid-to-high tier Herblore ingredients,
## unnoted, straight into the bag.
##
## CAPACITY IS CHECKED FIRST, for the whole bundle at once, before a single item
## is granted and before the crate is consumed. Checking per entry would measure
## each one against the same free squares and pass a bag with room for only the
## first — and Inventory.add_item is uncapped, so the rest would quietly grow the
## bag past MAX_SLOTS. Summing slots_needed across distinct ids is exact.

## The pool, as registry slugs with an amount band. Mid-to-high tier only: the
## crate is a 60,000-gold shortcut past the grind for herbs a herbalist actually
## bottlenecks on, not a way to buy the low-level ones they walk over.
const POOL: Array[Dictionary] = [
	{"slug": &"grimshade", "min": 14, "max": 26},
	{"slug": &"sunwort", "min": 14, "max": 26},
	{"slug": &"frostpetal", "min": 12, "max": 22},
	{"slug": &"moonbloom", "min": 10, "max": 18},
	{"slug": &"starblossom", "min": 8, "max": 14},
	{"slug": &"bloodcap", "min": 8, "max": 14},
	{"slug": &"blightspore", "min": 8, "max": 14},
	{"slug": &"venom_sac", "min": 6, "max": 12},
	{"slug": &"fairy_dust", "min": 5, "max": 10},
	{"slug": &"ember_ash", "min": 6, "max": 12},
]
## Distinct entries one crate pays out.
const PICKS: int = 4


func apply(player: Player, _instance: ServerInstance) -> Dictionary:
	var resource: PlayerResource = player.player_resource
	if resource == null:
		return {"ok": false, "reason": "no_player"}

	var rolled: Array = _roll()
	if rolled.is_empty():
		# Every slug failed to resolve — a stale items index, not an empty crate.
		# Name it and leave the crate in the bag.
		return {"ok": false, "reason": "no_pool"}

	var inventory: Dictionary = resource.inventory
	var bag_count: int = resource.inventory_bags
	var needed: int = 0
	for entry: Dictionary in rolled:
		needed += Inventory.slots_needed(
			inventory, int(entry["id"]), int(entry["amount"]), false, -1
		)
	if needed > Inventory.total_free_slots(inventory, bag_count):
		return {
			"ok": false,
			"reason": "inventory_full",
			"needed": needed,
			"free": Inventory.total_free_slots(inventory, bag_count),
		}

	var active_bag: int = resource.active_inventory_bag
	var granted: Array = []
	for entry: Dictionary in rolled:
		Inventory.add_item(
			inventory, int(entry["id"]), int(entry["amount"]),
			false, active_bag, bag_count
		)
		granted.append({
			"id": int(entry["id"]),
			"amount": int(entry["amount"]),
			"name": str(entry["name"]),
		})

	return {
		"ok": true,
		"granted": granted,
		"message": "The crate is packed with %d kinds of herb." % granted.size(),
	}


## [constant PICKS] distinct pool entries resolved against the live registry.
## An entry whose slug no longer resolves is skipped, so retiring one herb
## shrinks the crate rather than breaking it.
static func _roll() -> Array:
	var candidates: Array = POOL.duplicate()
	candidates.shuffle()
	var out: Array = []
	for entry: Dictionary in candidates:
		if out.size() >= PICKS:
			break
		var item_id: int = ContentRegistryHub.id_from_slug(&"items", entry["slug"])
		if item_id <= 0:
			continue
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
		if item == null:
			continue
		out.append({
			"id": item_id,
			"amount": randi_range(int(entry["min"]), int(entry["max"])),
			"name": String(item.item_name),
		})
	return out
