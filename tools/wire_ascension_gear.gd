@tool
extends SceneTree
## Wire Ascension (mastery 40–90) gear into crafting stations, shops, and dungeon rewards.
## Run after tools/generate_ascension_gear.py and texture import:
##   godot --headless --path . -s tools/wire_ascension_gear.gd

const ANVIL := "res://source/common/gameplay/crafting/resources/anvil.tres"
const WORKBENCH := "res://source/common/gameplay/crafting/resources/workbench.tres"
const FIRE_SHOP := "res://source/common/gameplay/shops/resources/fire_shop.tres"
const ASCENSION_SHOP := "res://source/common/gameplay/shops/resources/ascension_shop.tres"
const ASCENSION_REWARD := "res://source/common/gameplay/dungeon/ascension_reward.tres"

const TIERS: Array[int] = [40, 50, 60, 70, 80, 90]
const MELEE: Dictionary = {
	40: "basilisk", 50: "wyrmguard", 60: "colossus",
	70: "godsteel", 80: "behemoth", 90: "worldbreaker",
}
const ARCHERY: Dictionary = {
	40: "wraithsilk", 50: "nightglass", 60: "tempest",
	70: "skyrender", 80: "eclipse", 90: "starfall",
}
const MAGIC: Dictionary = {
	40: "runewoven", 50: "astral", 60: "voidsilk",
	70: "aetherborn", 80: "empyrean", 90: "primordial",
}
const CRAFT_LVL: Dictionary = {
	40: 55, 50: 62, 60: 70, 70: 78, 80: 88, 90: 96,
}
const XP: Dictionary = {
	40: 170, 50: 210, 60: 260, 70: 320, 80: 400, 90: 500,
}
## Material cures/weaves sit below finished-gear craft gates.
const CURE_LVL: Dictionary = {
	40: 48, 50: 55, 60: 62, 70: 70, 80: 80, 90: 90,
}
const CURE_XP: Dictionary = {
	40: 40, 50: 55, 60: 75, 70: 100, 80: 130, 90: 170,
}


func _init() -> void:
	_patch_anvil()
	_patch_workbench()
	_build_shops()
	_build_reward()
	print("ASCENSION_WIRE_OK")
	quit(0)


func _load_item(path: String) -> Item:
	var res: Resource = ResourceLoader.load(path)
	if res == null or res is not Item:
		push_error("Missing item: %s" % path)
		return null
	return res as Item


func _ing(item: Item, amount: int = 1) -> CraftIngredient:
	var ing := CraftIngredient.new()
	ing.item = item
	ing.amount = amount
	return ing


func _recipe(output: Item, ingredients: Array[CraftIngredient], level: int, xp: int) -> CraftingRecipe:
	var r := CraftingRecipe.new()
	r.output_item = output
	r.ingredients = ingredients
	r.required_level = level
	r.xp_reward = xp
	return r


func _already_has_output(station: CraftingStationResource, output: Item) -> bool:
	for recipe: CraftingRecipe in station.recipes:
		if recipe != null and recipe.output_item == output:
			return true
	return false


func _patch_anvil() -> void:
	var station: CraftingStationResource = ResourceLoader.load(ANVIL) as CraftingStationResource
	var added: int = 0
	for tier: int in TIERS:
		var key: String = String(MELEE[tier])
		var mkey: String = String(MAGIC[tier])
		var akey: String = String(ARCHERY[tier])
		var lvl: int = int(CRAFT_LVL[tier])
		var xp: int = int(XP[tier])
		var ore: Item = _load_item("res://source/common/gameplay/items/materials/metals/%s_ore.tres" % key)
		var gem: Item = _load_item("res://source/common/gameplay/items/materials/gems/%s_gem.tres" % key)
		var cloth: Item = _load_item("res://source/common/gameplay/items/materials/cloth/%s_cloth.tres" % key)
		var more: Item = _load_item("res://source/common/gameplay/items/materials/metals/%s_ore.tres" % mkey)
		var mgem: Item = _load_item("res://source/common/gameplay/items/materials/gems/%s_gem.tres" % mkey)
		var aore_for_bow: Item = _load_item("res://source/common/gameplay/items/materials/leather/%s_leather.tres" % akey)
		var agem: Item = _load_item("res://source/common/gameplay/items/materials/gems/%s_gem.tres" % akey)
		if ore == null or gem == null or cloth == null:
			continue

		# Metal armor
		var pieces: Array[Dictionary] = [
			{"path": "res://source/common/gameplay/items/gears/metal/%s_helmet.tres" % key, "ore": 3, "cloth": 2, "xp": xp},
			{"path": "res://source/common/gameplay/items/gears/metal/%s_chest.tres" % key, "ore": 4, "cloth": 3, "xp": xp + 20},
			{"path": "res://source/common/gameplay/items/gears/metal/%s_boots.tres" % key, "ore": 2, "cloth": 2, "xp": xp - 10},
		]
		for p: Dictionary in pieces:
			var out: Item = _load_item(String(p["path"]))
			if out == null or _already_has_output(station, out):
				continue
			station.recipes.append(_recipe(
				out,
				[_ing(ore, int(p["ore"])), _ing(gem, 1), _ing(cloth, int(p["cloth"]))],
				lvl,
				int(p["xp"])
			))
			added += 1

		# Melee weapons from ore+gem
		var weapons: Array[Dictionary] = [
			{"path": "res://source/common/gameplay/items/weapons/sword/sword_%s.item.tres" % key, "ore": 4, "mat": ore, "g": gem},
			{"path": "res://source/common/gameplay/items/weapons/hammer/hammer_%s.item.tres" % key, "ore": 5, "mat": ore, "g": gem},
			{"path": "res://source/common/gameplay/items/weapons/wand/wand_%s.item.tres" % mkey, "ore": 3, "mat": more, "g": mgem},
			{"path": "res://source/common/gameplay/items/weapons/book/book_%s.item.tres" % mkey, "ore": 3, "mat": more, "g": mgem},
			{"path": "res://source/common/gameplay/items/weapons/bow/%s_bow.item.tres" % akey, "ore": 3, "mat": aore_for_bow, "g": agem},
		]
		for w: Dictionary in weapons:
			var out_w: Item = _load_item(String(w["path"]))
			var mat: Item = w["mat"] as Item
			var g: Item = w["g"] as Item
			if out_w == null or mat == null or g == null or _already_has_output(station, out_w):
				continue
			station.recipes.append(_recipe(
				out_w,
				[_ing(mat, int(w["ore"])), _ing(g, 1)],
				lvl,
				xp + 30
			))
			added += 1

	# Jewelry at anvil (high craft). Heart of the Wild stays on basilisk gems;
	# the other five each use a unique jewelry gem.
	var jewelry_gems: Array[Array] = [
		["heart_of_the_wild", "basilisk_gem"],
		["ember_locket", "ember_gem"],
		["tideglass_amulet", "tideglass_gem"],
		["oathstone", "oath_gem"],
		["reliquary_of_verdance", "verdance_gem"],
		["covenant_cross", "covenant_gem"],
	]
	var gold: Item = _load_item("res://source/common/gameplay/items/materials/metals/gold_bar.tres")
	if gold != null:
		for pair: Array in jewelry_gems:
			var j: Item = _load_item("res://source/common/gameplay/items/gears/jewelry/%s.tres" % String(pair[0]))
			var gem: Item = _load_item("res://source/common/gameplay/items/materials/gems/%s.tres" % String(pair[1]))
			if j == null or gem == null or _already_has_output(station, j):
				continue
			station.recipes.append(_recipe(j, [_ing(gold, 3), _ing(gem, 2)], 60, 220))
			added += 1

	var err: Error = ResourceSaver.save(station, ANVIL)
	print("anvil recipes added: ", added, " save=", error_string(err))


func _patch_workbench() -> void:
	var station: CraftingStationResource = ResourceLoader.load(WORKBENCH) as CraftingStationResource
	var added: int = 0

	# Materials tab: cure Ascension hides → leather, weave fibers → cloth.
	for tier: int in TIERS:
		var akey: String = String(ARCHERY[tier])
		var mkey: String = String(MAGIC[tier])
		var clvl: int = int(CURE_LVL[tier])
		var cxp: int = int(CURE_XP[tier])

		var hide: Item = _load_item("res://source/common/gameplay/items/materials/leather/hide_%s.tres" % akey)
		var leather_out: Item = _load_item("res://source/common/gameplay/items/materials/leather/%s_leather.tres" % akey)
		if hide != null and leather_out != null and not _already_has_output(station, leather_out):
			station.recipes.append(_recipe(leather_out, [_ing(hide, 2)], clvl, cxp))
			added += 1

		var afiber: Item = _load_item("res://source/common/gameplay/items/materials/cloth/fiber_%s.tres" % akey)
		var acloth_out: Item = _load_item("res://source/common/gameplay/items/materials/cloth/%s_cloth.tres" % akey)
		if afiber != null and acloth_out != null and not _already_has_output(station, acloth_out):
			station.recipes.append(_recipe(acloth_out, [_ing(afiber, 2)], clvl, cxp))
			added += 1

		var mfiber: Item = _load_item("res://source/common/gameplay/items/materials/cloth/fiber_%s.tres" % mkey)
		var mcloth_out: Item = _load_item("res://source/common/gameplay/items/materials/cloth/%s_cloth.tres" % mkey)
		if mfiber != null and mcloth_out != null and not _already_has_output(station, mcloth_out):
			station.recipes.append(_recipe(mcloth_out, [_ing(mfiber, 2)], clvl, cxp + 5))
			added += 1

	for tier: int in TIERS:
		var akey: String = String(ARCHERY[tier])
		var mkey: String = String(MAGIC[tier])
		var lvl: int = int(CRAFT_LVL[tier])
		var xp: int = int(XP[tier])
		var leather: Item = _load_item("res://source/common/gameplay/items/materials/leather/%s_leather.tres" % akey)
		var agem: Item = _load_item("res://source/common/gameplay/items/materials/gems/%s_gem.tres" % akey)
		var acloth: Item = _load_item("res://source/common/gameplay/items/materials/cloth/%s_cloth.tres" % akey)
		var mcloth: Item = _load_item("res://source/common/gameplay/items/materials/cloth/%s_cloth.tres" % mkey)
		var mgem: Item = _load_item("res://source/common/gameplay/items/materials/gems/%s_gem.tres" % mkey)
		var more: Item = _load_item("res://source/common/gameplay/items/materials/metals/%s_ore.tres" % mkey)
		if leather == null or mcloth == null:
			continue

		var leather_pieces: Array[Dictionary] = [
			{"path": "res://source/common/gameplay/items/gears/leather/%s_hood.tres" % akey, "l": 3, "c": 2},
			{"path": "res://source/common/gameplay/items/gears/leather/%s_vest.tres" % akey, "l": 4, "c": 3},
			{"path": "res://source/common/gameplay/items/gears/leather/%s_sandals.tres" % akey, "l": 2, "c": 2},
		]
		for p: Dictionary in leather_pieces:
			var out: Item = _load_item(String(p["path"]))
			if out == null or _already_has_output(station, out):
				continue
			station.recipes.append(_recipe(
				out,
				[_ing(leather, int(p["l"])), _ing(agem, 1), _ing(acloth, int(p["c"]))],
				lvl,
				xp
			))
			added += 1

		var cloth_pieces: Array[Dictionary] = [
			{"path": "res://source/common/gameplay/items/gears/cloth/%s_hood.tres" % mkey, "c": 3, "o": 2},
			{"path": "res://source/common/gameplay/items/gears/cloth/%s_robe.tres" % mkey, "c": 5, "o": 3},
			{"path": "res://source/common/gameplay/items/gears/cloth/%s_shoes.tres" % mkey, "c": 3, "o": 2},
		]
		for p2: Dictionary in cloth_pieces:
			var out2: Item = _load_item(String(p2["path"]))
			if out2 == null or _already_has_output(station, out2):
				continue
			station.recipes.append(_recipe(
				out2,
				[_ing(more, int(p2["o"])), _ing(mgem, 1), _ing(mcloth, int(p2["c"]))],
				lvl,
				xp + 10
			))
			added += 1

	var err: Error = ResourceSaver.save(station, WORKBENCH)
	print("workbench recipes added: ", added, " save=", error_string(err))


func _build_shops() -> void:
	var shop := ShopResource.new()
	shop.shop_name = "Ascension Emporium"
	var entries: Array[ShopEntry] = []

	# Sell materials for each tier (entry point for crafting loop)
	for tier: int in TIERS:
		var key: String = String(MELEE[tier])
		var akey: String = String(ARCHERY[tier])
		var mkey: String = String(MAGIC[tier])
		var price_base: int = 80 + (tier - 40) * 25
		for path_price: Array in [
			["res://source/common/gameplay/items/materials/metals/%s_ore.tres" % key, price_base],
			["res://source/common/gameplay/items/materials/gems/%s_gem.tres" % key, price_base + 40],
			["res://source/common/gameplay/items/materials/cloth/%s_cloth.tres" % key, price_base + 20],
			["res://source/common/gameplay/items/materials/leather/hide_%s.tres" % akey, price_base / 2],
			["res://source/common/gameplay/items/materials/leather/%s_leather.tres" % akey, price_base + 30],
			["res://source/common/gameplay/items/materials/gems/%s_gem.tres" % akey, price_base + 40],
			["res://source/common/gameplay/items/materials/cloth/fiber_%s.tres" % akey, price_base / 2],
			["res://source/common/gameplay/items/materials/cloth/%s_cloth.tres" % akey, price_base + 20],
			["res://source/common/gameplay/items/materials/cloth/fiber_%s.tres" % mkey, price_base / 2 + 5],
			["res://source/common/gameplay/items/materials/cloth/%s_cloth.tres" % mkey, price_base + 30],
			["res://source/common/gameplay/items/materials/gems/%s_gem.tres" % mkey, price_base + 40],
			["res://source/common/gameplay/items/materials/metals/%s_ore.tres" % mkey, price_base + 20],
		]:
			var it: Item = _load_item(String(path_price[0]))
			if it == null:
				continue
			var e := ShopEntry.new()
			e.item = it
			e.price = int(path_price[1])
			entries.append(e)

	# Materials only — Ascension finished gear is craft/dungeon, never gold-buyable.
	shop.entries = entries
	shop.set_meta(&"slug", &"ascension_shop")
	var err: Error = ResourceSaver.save(shop, ASCENSION_SHOP)
	print("ascension_shop entries=", entries.size(), " save=", error_string(err))

	# Also stock Forgemaster Helka's fire shop with mid-tier mats (no finished gear).
	var fire: ShopResource = ResourceLoader.load(FIRE_SHOP) as ShopResource
	if fire != null:
		var fire_entries: Array[ShopEntry] = []
		for path: String in [
			"res://source/common/gameplay/items/materials/metals/basilisk_ore.tres",
			"res://source/common/gameplay/items/materials/gems/basilisk_gem.tres",
			"res://source/common/gameplay/items/materials/metals/wyrmguard_ore.tres",
			"res://source/common/gameplay/items/materials/gems/godsteel_gem.tres",
		]:
			var it2: Item = _load_item(path)
			if it2 == null:
				continue
			var fe := ShopEntry.new()
			fe.item = it2
			fe.price = maxi(it2.vendor_value * 5, 500)
			fire_entries.append(fe)
		fire.entries = fire_entries
		fire.shop_name = "The Ashmonger's Hoard"
		var err2: Error = ResourceSaver.save(fire, FIRE_SHOP)
		print("fire_shop entries=", fire_entries.size(), " save=", error_string(err2))

func _build_reward() -> void:
	var reward := DungeonReward.new()
	reward.gold_min = 2500
	reward.gold_max = 6000
	var loot: Array[LootDrop] = []
	# Materials common
	for path_chance: Array in [
		["res://source/common/gameplay/items/materials/metals/basilisk_ore.tres", 0.55, 2, 6],
		["res://source/common/gameplay/items/materials/leather/hide_wraithsilk.tres", 0.5, 2, 5],
		["res://source/common/gameplay/items/materials/cloth/fiber_runewoven.tres", 0.5, 2, 5],
		["res://source/common/gameplay/items/materials/leather/wraithsilk_leather.tres", 0.45, 1, 4],
		["res://source/common/gameplay/items/materials/cloth/runewoven_cloth.tres", 0.45, 1, 4],
		["res://source/common/gameplay/items/materials/gems/basilisk_gem.tres", 0.35, 1, 2],
		["res://source/common/gameplay/items/materials/metals/colossus_ore.tres", 0.25, 1, 3],
		["res://source/common/gameplay/items/materials/leather/hide_tempest.tres", 0.28, 1, 4],
		["res://source/common/gameplay/items/materials/cloth/fiber_voidsilk.tres", 0.28, 1, 4],
		["res://source/common/gameplay/items/materials/leather/tempest_leather.tres", 0.22, 1, 3],
		["res://source/common/gameplay/items/materials/cloth/voidsilk_cloth.tres", 0.22, 1, 3],
		["res://source/common/gameplay/items/materials/gems/godsteel_gem.tres", 0.12, 1, 1],
		["res://source/common/gameplay/items/materials/metals/worldbreaker_ore.tres", 0.06, 1, 2],
		["res://source/common/gameplay/items/materials/leather/hide_starfall.tres", 0.08, 1, 3],
		["res://source/common/gameplay/items/materials/cloth/fiber_primordial.tres", 0.08, 1, 3],
		["res://source/common/gameplay/items/materials/leather/starfall_leather.tres", 0.05, 1, 2],
		["res://source/common/gameplay/items/materials/cloth/primordial_cloth.tres", 0.05, 1, 2],
	]:
		var it: Item = _load_item(String(path_chance[0]))
		if it == null:
			continue
		var d := LootDrop.new()
		d.item = it
		d.chance = float(path_chance[1])
		d.min_amount = int(path_chance[2])
		d.max_amount = int(path_chance[3])
		loot.append(d)

	# Rare finished weapons
	for path_c: Array in [
		["res://source/common/gameplay/items/weapons/sword/sword_basilisk.item.tres", 0.03],
		["res://source/common/gameplay/items/weapons/bow/wraithsilk_bow.item.tres", 0.03],
		["res://source/common/gameplay/items/weapons/wand/wand_runewoven.item.tres", 0.03],
		["res://source/common/gameplay/items/weapons/sword/sword_dawnbreaker.item.tres", 0.015],
		["res://source/common/gameplay/items/weapons/hammer/hammer_riftedge.item.tres", 0.015],
		["res://source/common/gameplay/items/weapons/sword/sword_nightfall.item.tres", 0.008],
		["res://source/common/gameplay/items/weapons/hammer/hammer_kingsbane.item.tres", 0.008],
		["res://source/common/gameplay/items/weapons/sword/sword_worldbreaker.item.tres", 0.004],
		["res://source/common/gameplay/items/gears/jewelry/reliquary_of_verdance.tres", 0.01],
		["res://source/common/gameplay/items/gears/rings/ring_sovereign.tres", 0.01],
	]:
		var w: Item = _load_item(String(path_c[0]))
		if w == null:
			continue
		var dw := LootDrop.new()
		dw.item = w
		dw.chance = float(path_c[1])
		dw.min_amount = 1
		dw.max_amount = 1
		loot.append(dw)

	reward.loot = loot
	var err: Error = ResourceSaver.save(reward, ASCENSION_REWARD)
	print("ascension_reward loot=", loot.size(), " save=", error_string(err))
