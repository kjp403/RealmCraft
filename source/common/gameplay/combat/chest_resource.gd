class_name ChestResource
extends Resource
## Loot table + presentation for a world Loot Chest (boss drops, admin spawns).
## Opened via [code]chest.open[/code]; gold goes to the pouch, items stage in
## [member PlayerResource.pending_chest_loot] for the claim UI.

## Display name shown in toasts / hover (e.g. "Wood Chest (Silver)").
@export var display_name: String = "Loot Chest"
## Sprite drawn on the world prop.
@export var icon: Texture2D
## Tier label for tooling (1 = silver wood, 2 = gold wood, 3 = ornate).
@export_range(1, 3, 1) var tier: int = 1
## Gold paid on open, rolled uniformly in [gold_min, gold_max]. 0 = no gold.
@export var gold_min: int = 0
@export var gold_max: int = 0
## Loot table. An open draws [member rolls_min]..[member rolls_max] distinct
## entries from this pool — [member LootDrop.chance] is the relative weight of
## being picked, not an independent roll, so a chest grants a few of the table
## rather than most of it.
@export var loot: Array[LootDrop] = []
## Distinct [member loot] entries granted per open, rolled uniformly in
## [rolls_min, rolls_max] and clamped to the number of valid entries.
@export var rolls_min: int = 1
@export var rolls_max: int = 3
## Optional exclusive pool (e.g. rare jewelry). Each entry rolls independently,
## but at most [member exclusive_max] hits are kept — so a chest never grants
## two rings from this pool.
@export var exclusive_loot: Array[LootDrop] = []
## Cap on exclusive_loot hits per open. 1 = at most one jewelry piece.
@export var exclusive_max: int = 1


## Directory of authored chest tables (filename slug → .tres).
const CHESTS_DIR: String = "res://source/common/gameplay/combat/chests/"


## Load a chest table by filename slug (e.g. &"wood_silver_small").
static func load_by_slug(slug: StringName) -> ChestResource:
	if slug == &"":
		return null
	var path: String = CHESTS_DIR + String(slug) + ".tres"
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as ChestResource


## Server: roll gold + loot into [param player]'s bag. Returns
## [code]{ "chest", "gold", "items" }[/code]. Draws a weighted sample of the
## table rather than rolling every entry, so which resources you get varies open
## to open; still guarantees ≥1 resource stack when the table has any valid
## drop (so T1/T2 never open gold-only).
## Opened via [code]chest.open[/code]; gold goes to the pouch, items stage in
## [member PlayerResource.pending_chest_loot] for the claim UI.
func roll_and_grant(player: Player) -> Dictionary:
	if player == null or player.player_resource == null:
		return {}
	var resource: PlayerResource = player.player_resource
	var gold: int = 0
	if gold_max > 0:
		gold = randi_range(gold_min, gold_max)
		if gold > 0 and Economy.gold_id() > 0:
			Inventory.add_item(resource.inventory, Economy.gold_id(), gold, false, resource.active_inventory_bag, resource.inventory_bags)

	var items: Array = []
	var draws: int = randi_range(maxi(1, mini(rolls_min, rolls_max)), maxi(1, rolls_max))
	for drop: LootDrop in _draw_weighted(loot, draws):
		_grant_drop(resource, drop, items)

	# Exclusive pool: independent rolls, then keep at most exclusive_max hits.
	if not exclusive_loot.is_empty():
		var hits: Array = []
		for drop: LootDrop in exclusive_loot:
			if drop == null or drop.item == null:
				continue
			if randf() <= drop.chance:
				hits.append(drop)
		var cap: int = maxi(0, exclusive_max)
		if hits.size() > cap:
			hits.shuffle()
			hits = hits.slice(0, cap)
		for drop: LootDrop in hits:
			_grant_drop(resource, drop, items)

	return {
		"chest": display_name,
		"gold": gold,
		"items": items,
		"pending": PendingChestLoot.to_payload(resource.pending_chest_loot),
		"free_slots": Inventory.total_free_slots(resource.inventory, resource.inventory_bags),
	}


## Pick [param count] distinct entries from [param pool] without replacement,
## weighted by [member LootDrop.chance]. Entries with no item, no registered id,
## or a non-positive chance are skipped; the result is capped at how many valid
## entries exist.
static func _draw_weighted(pool: Array[LootDrop], count: int) -> Array[LootDrop]:
	var candidates: Array[LootDrop] = []
	for drop: LootDrop in pool:
		if drop == null or drop.item == null or drop.chance <= 0.0:
			continue
		if int(drop.item.get_meta(&"id", 0)) <= 0:
			continue
		candidates.append(drop)

	var picks: Array[LootDrop] = []
	var remaining: int = mini(count, candidates.size())
	while remaining > 0:
		var total: float = 0.0
		for drop: LootDrop in candidates:
			total += drop.chance
		var roll: float = randf() * total
		# Float drift can leave roll above the running sum; fall back to the last
		# candidate so a draw never comes up empty.
		var index: int = candidates.size() - 1
		for i: int in candidates.size():
			roll -= candidates[i].chance
			if roll <= 0.0:
				index = i
				break
		picks.append(candidates[index])
		candidates.remove_at(index)
		remaining -= 1
	return picks


## Cooked fish granted from a chest would skip Cooking XP — remap to the raw
## material so bag-chest / world-chest fish stays cookable.
const COOKED_FISH_TO_RAW: Dictionary = {
	&"cooked_shrimp": &"shrimp",
	&"cooked_herring": &"herring",
	&"cooked_cod": &"cod",
	&"cooked_trout": &"trout",
	&"cooked_salmon": &"salmon",
	&"cooked_tuna": &"tuna",
	&"cooked_lobster": &"lobster",
	&"cooked_lionfish": &"lionfish",
	&"cooked_crab": &"crab",
	&"cooked_turtle": &"turtle",
	&"cooked_parrot_fish": &"parrot_fish",
	&"cooked_anglerfish": &"anglerfish",
}


static func _grant_drop(resource: PlayerResource, drop: LootDrop, items: Array) -> void:
	var amount: int = randi_range(drop.min_amount, drop.max_amount)
	if amount <= 0:
		return
	var grant_item: Resource = drop.item
	var slug: StringName = grant_item.get_meta(&"slug", &"") as StringName
	if COOKED_FISH_TO_RAW.has(slug):
		var raw: Resource = ContentRegistryHub.load_by_slug(
			&"items", COOKED_FISH_TO_RAW[slug] as StringName
		)
		if raw != null:
			grant_item = raw
	var item_id: int = int(grant_item.get_meta(&"id", 0))
	if item_id <= 0:
		return
	PendingChestLoot.add(resource.pending_chest_loot, item_id, amount)
	var display_name: String = str((grant_item as Item).item_name) if grant_item is Item else "Item"
	items.append({
		"id": item_id,
		"amount": amount,
		"name": display_name,
	})
