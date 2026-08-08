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
