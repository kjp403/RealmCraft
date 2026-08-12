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
## Loot table — each entry rolls independently (chance + amount range).
@export var loot: Array[LootDrop] = []
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
## [code]{ "chest", "gold", "items" }[/code]. Guarantees ≥1 resource stack when
## the table has any valid drops (so T1/T2 never open gold-only).
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
			Inventory.add_item(resource.inventory, Economy.gold_id(), gold)

	var items: Array = []
	for drop: LootDrop in loot:
		if drop == null or drop.item == null:
			continue
		if randf() <= drop.chance:
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

	if items.is_empty():
		var candidates: Array[LootDrop] = []
		for drop: LootDrop in loot:
			if drop != null and drop.item != null and int(drop.item.get_meta(&"id", 0)) > 0:
				candidates.append(drop)
		if not candidates.is_empty():
			_grant_drop(resource, candidates[randi() % candidates.size()], items)

	return {
		"chest": display_name,
		"gold": gold,
		"items": items,
		"pending": PendingChestLoot.to_payload(resource.pending_chest_loot),
		"free_slots": Inventory.free_slots(resource.inventory),
	}


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
