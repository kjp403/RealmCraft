extends PeddlerAction
## Mystery Seed: plant it, watch it shoot up, harvest it on the spot.
##
## Grants raw gatherables straight into the bag as real stacks — logs and herbs a
## woodcutter or herbalist would otherwise have to walk out and cut. The pool is
## deliberately RAW materials only: a seed that could pay out bars or potions
## would be a crafting bypass rather than a gathering top-up.
##
## The bloom is a replicated prop, not a client-side burst on the user, so the
## people standing around the cart see the thing sprout too. It despawns itself.


## Candidate payouts, as registry slugs with an amount band. Weighted by nothing —
## a flat pick across the pool, then a flat amount inside the band. Two DIFFERENT
## slugs are drawn per seed (see [method apply]), which is what makes a seed read
## as a small harvest rather than as one lumpy stack.
const POOL: Array[Dictionary] = [
	{"slug": &"logs", "min": 12, "max": 24},
	{"slug": &"oak_log", "min": 10, "max": 20},
	{"slug": &"willow_log", "min": 8, "max": 16},
	{"slug": &"maple_log", "min": 6, "max": 12},
	{"slug": &"yew_log", "min": 4, "max": 8},
	{"slug": &"healing_herb", "min": 10, "max": 20},
	{"slug": &"grimshade", "min": 6, "max": 12},
	{"slug": &"sunwort", "min": 6, "max": 12},
	{"slug": &"frostpetal", "min": 4, "max": 10},
	{"slug": &"moonbloom", "min": 3, "max": 8},
]
## How many distinct entries one seed pays out. Space for all of them is checked
## before anything is planted, so a full bag refuses the use rather than eating
## the seed and dropping the crop.
const PICKS: int = 2


func apply(player: Player, instance: ServerInstance) -> Dictionary:
	var resource: PlayerResource = player.player_resource
	if resource == null:
		return {"ok": false, "reason": "no_player"}

	var rolled: Array = _roll()
	if rolled.is_empty():
		# Every slug in POOL failed to resolve — the items index is stale rather
		# than the seed being empty. Name it, don't eat the seed.
		return {"ok": false, "reason": "no_pool"}

	var inventory: Dictionary = resource.inventory
	var active_bag: int = resource.active_inventory_bag
	var bag_count: int = resource.inventory_bags
	# Space is checked for the WHOLE harvest at once. Asking can_add per entry
	# would measure each one against the same free squares and pass a bag that
	# only has room for the first — and add_item is uncapped, so the second would
	# quietly grow the bag past MAX_SLOTS. The picks are distinct item ids, so
	# summing slots_needed is exact.
	var needed: int = 0
	for entry: Dictionary in rolled:
		needed += Inventory.slots_needed(
			inventory, int(entry["id"]), int(entry["amount"]), false, -1
		)
	if needed > Inventory.total_free_slots(inventory, bag_count):
		return {"ok": false, "reason": "inventory_full"}

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

	MysterySeedBloom.plant(instance, player.global_position)
	return {
		"ok": true,
		"granted": granted,
		"message": "The seed bursts into growth.",
	}


## [PICKS] distinct pool entries, resolved to live registry ids. Entries whose
## slug no longer resolves are skipped, so retiring one herb shrinks the seed
## rather than breaking it.
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
