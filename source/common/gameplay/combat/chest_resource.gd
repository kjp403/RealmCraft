class_name ChestResource
extends Resource
## Loot table + presentation for a world Loot Chest (boss drops, admin spawns).
## Opened via [code]chest.open[/code]; grants rolled gold + items straight to the bag.

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
	}


static func _grant_drop(resource: PlayerResource, drop: LootDrop, items: Array) -> void:
	var amount: int = randi_range(drop.min_amount, drop.max_amount)
	if amount <= 0:
		return
	var item_id: int = int(drop.item.get_meta(&"id", 0))
	if item_id <= 0:
		return
	Inventory.add_item(resource.inventory, item_id, amount)
	items.append({
		"id": item_id,
		"amount": amount,
		"name": str(drop.item.item_name),
	})
