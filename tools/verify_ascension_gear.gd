@tool
extends SceneTree
## Verify Ascension gear content is loadable and coherent.
##   godot --headless --path . -s tools/verify_ascension_gear.gd

const TIERS: Array[int] = [40, 50, 60, 70, 80, 90]
const MELEE: Array[String] = ["basilisk", "wyrmguard", "godsteel", "colossus", "behemoth", "worldbreaker"]
const ARCHERY: Array[String] = ["wraithsilk", "nightglass", "tempest", "skyrender", "eclipse", "starfall"]
const MAGIC: Array[String] = ["runewoven", "astral", "voidsilk", "aetherborn", "empyrean", "primordial"]


func _init() -> void:
	var errors: PackedStringArray = []
	var checked: int = 0

	for i: int in TIERS.size():
		var tier: int = TIERS[i]
		var m: String = MELEE[i]
		var a: String = ARCHERY[i]
		var c: String = MAGIC[i]
		for path: String in [
			"res://source/common/gameplay/items/gears/metal/%s_helmet.tres" % m,
			"res://source/common/gameplay/items/gears/metal/%s_chest.tres" % m,
			"res://source/common/gameplay/items/gears/metal/%s_boots.tres" % m,
			"res://source/common/gameplay/items/gears/leather/%s_hood.tres" % a,
			"res://source/common/gameplay/items/gears/leather/%s_vest.tres" % a,
			"res://source/common/gameplay/items/gears/leather/%s_sandals.tres" % a,
			"res://source/common/gameplay/items/gears/cloth/%s_hood.tres" % c,
			"res://source/common/gameplay/items/gears/cloth/%s_robe.tres" % c,
			"res://source/common/gameplay/items/gears/cloth/%s_shoes.tres" % c,
			"res://source/common/gameplay/items/weapons/sword/sword_%s.item.tres" % m,
			"res://source/common/gameplay/items/weapons/hammer/hammer_%s.item.tres" % m,
			"res://source/common/gameplay/items/weapons/bow/%s_bow.item.tres" % a,
			"res://source/common/gameplay/items/weapons/wand/wand_%s.item.tres" % c,
			"res://source/common/gameplay/items/weapons/book/book_%s.item.tres" % c,
		]:
			checked += 1
			var item: Item = ResourceLoader.load(path) as Item
			if item == null:
				errors.append("load fail: %s" % path)
				continue
			if item.get_meta(&"id", -1) == null or int(item.get_meta(&"id", -1)) < 0:
				errors.append("missing id: %s" % path)
			if item.item_icon == null:
				errors.append("missing icon: %s" % path)
			if item is GearItem:
				var g: GearItem = item as GearItem
				if g.required_mastery_level != tier and path.find("special") < 0:
					# armor/weapons for tier should match
					if g.required_mastery_level != tier:
						errors.append("mastery mismatch %s want %d got %d" % [path, tier, g.required_mastery_level])
				if g.base_modifiers.is_empty():
					errors.append("no mods: %s" % path)

	# Jewelry / rings / skilling sample
	for path2: String in [
		"res://source/common/gameplay/items/gears/jewelry/ember_locket.tres",
		"res://source/common/gameplay/items/gears/rings/ring_sovereign.tres",
		"res://source/common/gameplay/items/gears/skilling/skilling_boots_night.tres",
		"res://source/common/gameplay/items/weapons/sword/sword_nightfall.item.tres",
		"res://source/common/gameplay/items/weapons/hammer/hammer_kingsbane.item.tres",
	]:
		checked += 1
		if ResourceLoader.load(path2) == null:
			errors.append("load fail: %s" % path2)

	# Stations / shop / reward
	for path3: String in [
		"res://source/common/gameplay/crafting/resources/anvil.tres",
		"res://source/common/gameplay/crafting/resources/workbench.tres",
		"res://source/common/gameplay/crafting/resources/ascended_workbench.tres",
		"res://source/common/gameplay/shops/resources/ascension_shop.tres",
		"res://source/common/gameplay/dungeon/ascension_reward.tres",
	]:
		checked += 1
		if ResourceLoader.load(path3) == null:
			errors.append("load fail: %s" % path3)

	var anvil: CraftingStationResource = ResourceLoader.load(
		"res://source/common/gameplay/crafting/resources/anvil.tres"
	) as CraftingStationResource
	var wb: CraftingStationResource = ResourceLoader.load(
		"res://source/common/gameplay/crafting/resources/workbench.tres"
	) as CraftingStationResource
	var awb: CraftingStationResource = ResourceLoader.load(
		"res://source/common/gameplay/crafting/resources/ascended_workbench.tres"
	) as CraftingStationResource
	var shop: ShopResource = ResourceLoader.load(
		"res://source/common/gameplay/shops/resources/ascension_shop.tres"
	) as ShopResource

	var basilisk_sword: Item = ResourceLoader.load(
		"res://source/common/gameplay/items/weapons/sword/sword_basilisk.item.tres"
	) as Item
	var found_anvil: bool = false
	if anvil != null and basilisk_sword != null:
		for r: CraftingRecipe in anvil.recipes:
			if r != null and r.output_item == basilisk_sword:
				found_anvil = true
				break
	if not found_anvil:
		errors.append("anvil missing Basilisk Sword recipe")

	var wraith_vest: Item = ResourceLoader.load(
		"res://source/common/gameplay/items/gears/leather/wraithsilk_vest.tres"
	) as Item
	var found_wb: bool = false
	if wb != null and wraith_vest != null:
		for r2: CraftingRecipe in wb.recipes:
			if r2 != null and r2.output_item == wraith_vest:
				found_wb = true
				break
	if not found_wb:
		errors.append("workbench missing Wraithsilk Vest recipe")

	var tempest_hood: Item = ResourceLoader.load(
		"res://source/common/gameplay/items/gears/leather/tempest_hood.tres"
	) as Item
	var found_awb: bool = false
	if awb != null and tempest_hood != null:
		for r3: CraftingRecipe in awb.recipes:
			if r3 != null and r3.output_item == tempest_hood:
				found_awb = true
				break
	if not found_awb:
		errors.append("ascended workbench missing Tempest Hood recipe")
	if awb == null or awb.station_name != "Ascended Workbench":
		errors.append("ascended workbench station_name wrong")
	# Lv.60+ gear must not remain on the normal workbench.
	if wb != null and tempest_hood != null:
		for r4: CraftingRecipe in wb.recipes:
			if r4 != null and r4.output_item == tempest_hood:
				errors.append("normal workbench still has Tempest Hood (belongs on Ascended)")
				break
	if awb != null:
		for r5: CraftingRecipe in awb.recipes:
			if r5 != null and r5.required_level < 60:
				errors.append("ascended workbench has sub-60 recipe lv=%d" % r5.required_level)
				break

	if shop == null or shop.entries.is_empty():
		errors.append("ascension shop empty")

	var dungeon_reward: DungeonReward = ResourceLoader.load(
		"res://source/common/gameplay/dungeon/ascension_reward.tres"
	) as DungeonReward
	if dungeon_reward == null or dungeon_reward.loot.is_empty():
		errors.append("ascension_reward missing loot")
	else:
		var names: PackedStringArray = PackedStringArray()
		for drop: LootDrop in dungeon_reward.loot:
			if drop != null and drop.item != null:
				names.append(str(drop.item.item_name))
		for need: String in [
			"Godsteel Sword", "Godsteel Hammer", "Nightglass Bow", "Tempest Bow",
			"Astral Wand", "Astral Tome", "Voidsilk Wand", "Voidsilk Tome",
			"Wyrmguard Sword", "Wyrmguard Hammer",
			"Godsteel Ore", "Tempest Leather", "Voidsilk Cloth", "Astral Cloth",
			"Wyrmguard Ore", "Nightglass Leather",
		]:
			if need not in names:
				errors.append("ascension_reward missing %s" % need)
		for banned: String in ["Colossus", "Worldbreaker", "Starfall", "Primordial", "Behemoth"]:
			for seen: String in names:
				if seen.find(banned) >= 0:
					errors.append("ascension_reward still has %s" % seen)

	# Stat monotonicity: Worldbreaker sword AD > Basilisk sword AD
	var s40: WeaponItem = ResourceLoader.load(
		"res://source/common/gameplay/items/weapons/sword/sword_basilisk.item.tres"
	) as WeaponItem
	var s90: WeaponItem = ResourceLoader.load(
		"res://source/common/gameplay/items/weapons/sword/sword_worldbreaker.item.tres"
	) as WeaponItem
	if s40 != null and s90 != null:
		var ad40: float = _ad_of(s40)
		var ad90: float = _ad_of(s90)
		if ad90 <= ad40:
			errors.append("stat curve broken: worldbreaker AD %.1f <= basilisk AD %.1f" % [ad90, ad40])
		print("AD curve sword: m40=%.1f m90=%.1f" % [ad40, ad90])

	if errors.is_empty():
		print("VERIFY_ASCENSION_PASS checked=%d anvil_recipes=%d workbench_recipes=%d ascended_recipes=%d shop_entries=%d" % [
			checked,
			anvil.recipes.size() if anvil else 0,
			wb.recipes.size() if wb else 0,
			awb.recipes.size() if awb else 0,
			shop.entries.size() if shop else 0,
		])
		quit(0)
	else:
		for e: String in errors:
			printerr("ERR ", e)
		print("VERIFY_ASCENSION_FAIL count=", errors.size())
		quit(1)


func _ad_of(w: WeaponItem) -> float:
	for m: StatModifier in w.base_modifiers:
		if m != null and m.stat_name == &"ad":
			return float(m.value)
	return 0.0
