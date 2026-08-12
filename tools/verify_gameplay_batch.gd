extends SceneTree
## Verifies the data-driven half of the gameplay fix batch: bar recipe coal costs,
## bone drops/icon/stacking, the mastery level-1 floor, and that each building's
## zone banner resolves to its OWN instance.
##   godot --headless --path . -s tools/verify_gameplay_batch.gd
##
## The two input fixes in this batch (attack breaking a gather loop; a target lock
## released on death) live in LocalPlayer/CombatTargetController and need a running
## client with a hostile in the world — they are NOT covered here.
##
## Checks report through _expect rather than assert: under `-s` a failed assert
## prints but does NOT halt, so an assert-only tool happily prints PASS after a
## real failure. Failures are counted and turned into a non-zero exit code.

const TYPES_DIR: String = "res://source/common/gameplay/characters/npc/types"
const BONE_PATH: String = "res://source/common/gameplay/items/materials/bone.tres"
const BUILDING_DIR: String = "res://source/common/gameplay/maps/instance/instance_collection/building"
## The practice target is not a hostile: it can't fight back and grants no xp.
const NOT_HOSTILE: PackedStringArray = ["training_dummy.tres"]

var _failures: int = 0


func _initialize() -> void:
	_check_bar_recipes()
	_check_bone_item()
	_check_bone_drops()
	_check_mastery_floor()
	_check_zone_banners()

	if _failures > 0:
		printerr("GAMEPLAY_BATCH_VERIFY_FAIL — %d check(s) failed" % _failures)
		quit(1)
		return
	print("GAMEPLAY_BATCH_VERIFY_PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_failures += 1
		printerr("FAIL %s" % message)
	return condition


## Mithril/adamant/runite bars smelt with 2/3/4 coal on top of one ore.
func _check_bar_recipes() -> void:
	var furnace: CraftingStationResource = load(
		"res://source/common/gameplay/crafting/resources/furnace.tres"
	)
	if not _expect(furnace != null, "furnace.tres failed to load"):
		return
	var expected: Dictionary = {"Mithril Bar": 2, "Adamant Bar": 3, "Runite Bar": 4}
	var seen: Dictionary = {}
	for recipe: CraftingRecipe in furnace.recipes:
		var out_name: String = String(recipe.output_item.item_name)
		if not expected.has(out_name):
			continue
		var coal: int = 0
		var ore: int = 0
		for ing: CraftIngredient in recipe.ingredients:
			if String(ing.item.item_name).to_lower().contains("coal"):
				coal += ing.amount
			else:
				ore += ing.amount
		_expect(coal == int(expected[out_name]),
			"%s wants %d coal, found %d" % [out_name, int(expected[out_name]), coal])
		_expect(ore == 1, "%s should take exactly 1 ore, found %d" % [out_name, ore])
		seen[out_name] = true
		print("OK recipe %s: 1 ore + %d coal" % [out_name, coal])
	_expect(seen.size() == expected.size(), "missing bar recipes (found %d of %d)" % [
		seen.size(), expected.size()])


func _check_bone_item() -> void:
	var bone: Item = load(BONE_PATH)
	if not _expect(bone != null, "bone.tres failed to load"):
		return
	_expect(bone.stack_limit == 100, "bone stack_limit is %d, want 100" % bone.stack_limit)
	_expect(bone.is_stackable(), "bone must stack")
	_expect(
		Inventory.stack_limit_for(bone, false) == 100,
		"bone bag stack should stay 100"
	)
	_expect(
		Inventory.stack_limit_for(bone, true) == 100,
		"bone bank stack should stay 100 (already above 50)"
	)
	var ore: Item = load("res://source/common/gameplay/items/materials/metals/iron_ore.tres")
	if _expect(ore != null, "iron_ore.tres failed to load"):
		_expect(ore.stack_limit == 10, "iron ore bag stack is %d, want 10" % ore.stack_limit)
		_expect(
			Inventory.stack_limit_for(ore, false) == 10,
			"iron ore inventory stack must stay 10"
		)
		_expect(
			Inventory.stack_limit_for(ore, true) == 50,
			"iron ore bank stack must be 50"
		)
	if not _expect(bone.item_icon != null, "bone has no icon"):
		return
	# Item.item_icon defaults to a leaf sprite, so an item that never assigns one
	# silently ships the leaf — which is exactly how bones looked in the bag.
	var icon_path: String = bone.item_icon.resource_path
	_expect(icon_path.contains("bone"),
		"bone icon is '%s' — expected a bone sprite (the leaf is Item's default)" % icon_path)
	print("OK bone: icon=%s stack=%d" % [icon_path.get_file(), bone.stack_limit])


## Every hostile enemy type drops exactly 1 bone, guaranteed.
func _check_bone_drops() -> void:
	var checked: int = 0
	for path: String in _find_tres(TYPES_DIR):
		if NOT_HOSTILE.has(path.get_file()):
			continue
		var res: EnemyTypeResource = load(path)
		if not _expect(res != null, "failed to load %s" % path):
			continue
		var bone_drops: int = 0
		for drop: LootDrop in res.loot:
			if not _expect(drop != null, "%s has an empty loot slot" % path.get_file()):
				continue
			if drop.item == null or drop.item.resource_path != BONE_PATH:
				continue
			bone_drops += 1
			_expect(is_equal_approx(drop.chance, 1.0),
				"%s drops bone at %.2f, want 1.0" % [path.get_file(), drop.chance])
			_expect(drop.min_amount == 1 and drop.max_amount == 1,
				"%s drops %d-%d bones, want exactly 1" % [
					path.get_file(), drop.min_amount, drop.max_amount])
		_expect(bone_drops == 1,
			"%s has %d bone drops, want exactly 1" % [path.get_file(), bone_drops])
		checked += 1
	print("OK bone drops: %d hostile types, all 1x @ 100%%" % checked)


## A never-practiced mastery reads as level 1, not 0 — gear gated at mastery 1
## was showing as unmet on a fresh character.
func _check_mastery_floor() -> void:
	var fresh: PlayerResource = PlayerResource.new()
	for category: StringName in [&"sword", &"bow", &"wand", &"hammer", &"book"]:
		var level: int = fresh.mastery_level_of(category)
		_expect(level == 1, "unpractised %s mastery reads %d, want 1" % [category, level])
	_expect(fresh.masteries.is_empty(),
		"mastery_level_of must not create entries (spawns stubs on every poll)")
	print("OK mastery floor: unpractised categories read Lv 1, no stub entries")


## Buildings are all authored as <building>/inside_map.tscn, so a banner index
## keyed by file STEM collapsed them into one entry and the Guild Hall respawn
## point announced itself as "Slayer House". Assert every show_discovery instance
## resolves to a distinct map. Mirrors ZoneDiscovery._map_key_of rather than
## calling it: that script pulls in client-only autoloads and won't compile here.
func _check_zone_banners() -> void:
	var guild: InstanceResource = load(BUILDING_DIR.path_join("guild_house.tres"))
	var slayer: InstanceResource = load(BUILDING_DIR.path_join("slayer_house.tres"))
	if not _expect(guild != null and slayer != null, "building instances failed to load"):
		return
	_expect(guild.zone_title == "Guild Hall",
		"respawn point is titled '%s', want 'Guild Hall'" % guild.zone_title)
	_expect(slayer.zone_title == "Slayer House",
		"Turael's house is titled '%s', want 'Slayer House'" % slayer.zone_title)

	var guild_key: String = _resolve_map(guild.map_path)
	var slayer_key: String = _resolve_map(slayer.map_path)
	_expect(guild_key != slayer_key and not guild_key.is_empty(),
		"both buildings key to '%s' — the banner index still collides" % guild_key)
	_expect(guild_key.get_file() == slayer_key.get_file(),
		"expected the shared '%s' stem this guards against" % guild_key.get_file())

	# And the collision must not exist anywhere else in the collection.
	var by_key: Dictionary = {}
	var by_stem: Dictionary = {}
	var stem_clashes: int = 0
	for path: String in _find_tres(BUILDING_DIR.get_base_dir()):
		var res: InstanceResource = load(path) as InstanceResource
		if res == null or not res.show_discovery:
			continue
		var key: String = _resolve_map(res.map_path)
		if key.is_empty():
			continue
		_expect(not by_key.has(key), "two banner zones share map '%s'" % key)
		by_key[key] = true
		var stem: String = key.get_file().get_basename()
		if by_stem.has(stem):
			stem_clashes += 1
		by_stem[stem] = true
	print("OK zone banners: %d zones, all distinct by map path (%d would have clashed by stem)" % [
		by_key.size(), stem_clashes])


func _resolve_map(map_path: String) -> String:
	if map_path.begins_with("uid://"):
		var uid: int = ResourceUID.text_to_id(map_path)
		if uid == ResourceUID.INVALID_ID or not ResourceUID.has_id(uid):
			return ""
		return ResourceUID.get_id_path(uid)
	return map_path


func _find_tres(dir_path: String) -> PackedStringArray:
	var found: PackedStringArray = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var full: String = dir_path.path_join(entry)
		if dir.current_is_dir():
			found.append_array(_find_tres(full))
		elif entry.ends_with(".tres"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return found
