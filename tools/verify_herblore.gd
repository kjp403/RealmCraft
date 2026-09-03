extends Node

## Mira's vial price. Every potion in the game is brewed from one, so this is the
## floor under every potion price on the Trading Post — set to 500 so a brewed
## potion always has real cost behind it.
const VIAL_PRICE: int = 500
## No potion may sell to a vendor for more than this.
const VENDOR_VALUE_CAP: int = 100
const POTION_VENDOR_VALUES: Dictionary = {
	"res://source/common/gameplay/items/consumables/minor_health_potion.tres": 25,
	"res://source/common/gameplay/items/consumables/minor_mana_potion.tres": 25,
	"res://source/common/gameplay/items/consumables/health_potion.tres": 50,
	"res://source/common/gameplay/items/consumables/mana_potion.tres": 50,
	"res://source/common/gameplay/items/consumables/greater_health_potion.tres": 100,
	"res://source/common/gameplay/items/consumables/greater_mana_potion.tres": 100,
	"res://source/common/gameplay/items/consumables/prayer_potion.tres": 100,
}
## The ONE shop still allowed to stock potions: the Lost Soul, who stands in all
## three dungeons. Every other vendor was cleared out so players buy from players.
const DUNGEON_SHOP: String = "res://source/common/gameplay/shops/resources/lost_soul_shop.tres"
## What the Lost Soul charges: 2.5x the old town price. A potion down here is a
## panic buy that costs you the run's profit, never a supply line — the whole
## point is that restocking at the Trading Post before you go is the cheap play.
const DUNGEON_POTION_PRICES: Dictionary = {
	"res://source/common/gameplay/items/consumables/health_potion.tres": 2500,
	"res://source/common/gameplay/items/consumables/greater_health_potion.tres": 3750,
	"res://source/common/gameplay/items/consumables/mana_potion.tres": 3750,
	"res://source/common/gameplay/items/consumables/greater_mana_potion.tres": 5000,
}
const SHOP_DIR: String = "res://source/common/gameplay/shops/resources"
## Load-and-shape check for Farming herb ladder + Herblore alchemy station.
##
## Runs as a SCENE, not `-s`: under `-s` there are no autoloads, so
## ConsumableItem (which reaches ClientState) fails to compile and every potion
## in the station and the job list loads as null — the check then reports
## cascading false failures. See verify_bank.gd for the same note.
##
##   godot --headless --path . --mode=client res://tools/verify_herblore.tscn

func _ready() -> void:
	var fails: Array[String] = []

	var farm: JobPerks = JobRegistry.perks_for(&"harvesting")
	if farm == null:
		fails.append("JobRegistry missing harvesting")
	elif farm.source_items.size() < 14:
		fails.append("Farming sources expected >= 14, got %d" % farm.source_items.size())
	else:
		print("farming sources=", farm.source_items.size(), " levels=", farm.source_levels)

	var herb: JobPerks = JobRegistry.perks_for(&"herblore")
	if herb == null:
		fails.append("JobRegistry missing herblore")
	else:
		print("herblore=", herb.display_name, " recipes=", herb.recipe_items.size())
		# 7 potion ladder + 4 weapon coatings + prayer potion + 2 Hollow Seep brews
		# + 6 high-tier combination draughts.
		if herb.recipe_items.size() != 20:
			fails.append("Herblore recipe_items expected 20, got %d" % herb.recipe_items.size())

	if not JobRegistry.JOBS.has(&"herblore"):
		fails.append("JOBS dict missing herblore")

	var station: CraftingStationResource = load(
		"res://source/common/gameplay/crafting/resources/alchemy_station.tres"
	)
	if station == null:
		fails.append("alchemy_station.tres failed to load")
	else:
		print("station=", station.station_name, " profession=", station.profession,
			" recipes=", station.recipes.size())
		if station.profession != &"herblore":
			fails.append("alchemy station profession should be herblore")
		if station.recipes.size() != 20:
			fails.append("expected 20 brew recipes, got %d" % station.recipes.size())
		for r: CraftingRecipe in station.recipes:
			if r == null or r.output_item == null:
				fails.append("null brew recipe")
				continue
			print("  brew ", r.output_item.item_name, " lv", r.required_level, " xp", r.xp_reward)
			# THE VIAL FLOOR. Every potion must have a 500g vial behind it, which is
			# what keeps the Trading Post price of a brew off the floor.
			#
			# A COMBINATION draught pays that floor TRANSITIVELY: it is brewed from
			# finished potions, and each of those already bought its own vial. A
			# Corrosive Ember Draught consumes an Ember and a Tonic, so two vials'
			# worth of cost is already inside it, and demanding a third Vial of
			# Water would charge for glass the recipe never uses — and would break
			# the reclaim ledger, which hands the leftover glass back as an Empty
			# Vial. So the rule is "one vial per output, from somewhere", not
			# "a Vial of Water ingredient".
			var vials_in: int = 0
			for ing: CraftIngredient in r.ingredients:
				if ing == null or ing.item == null:
					fails.append("null ingredient on %s" % r.output_item.item_name)
					continue
				vials_in += PotionMixer.vial_count(ing.item) * ing.amount
				if String(ing.item.get_meta(&"slug", &"")) == "vial_of_water" and ing.amount != 1:
					fails.append("%s vial amount %d != 1" % [r.output_item.item_name, ing.amount])
			if vials_in < 1:
				fails.append("%s has no vial behind it" % r.output_item.item_name)
			# Glass in must equal glass out plus glass returned, or brewing is
			# quietly creating or destroying vials.
			var vials_out: int = PotionMixer.vial_count(r.output_item) * r.output_amount
			var reclaimed: int = PotionMixer.reclaimed_glass(r)
			if vials_in != vials_out + reclaimed:
				fails.append("%s glass ledger: %d in, %d out, %d back" % [
					r.output_item.item_name, vials_in, vials_out, reclaimed
				])

	var herb_slugs: Array[String] = [
		"healing_herb", "frostpetal", "sunwort", "moonbloom",
		"bloodcap", "starblossom", "grimshade",
	]
	# The high-tier patches continue the same ladder; they are checked by the
	# same loop so a new herb cannot be added with the tool or the level wrong.
	herb_slugs.append_array([
		"rust_spore_cap", "nightshade_bramble", "magma_root",
		"sun_lit_lotus", "gloom_spore_cap", "iron_spike_thorn",
	])
	var expected_levels: Dictionary = {
		"healing_herb": 1, "frostpetal": 5, "sunwort": 10, "moonbloom": 20,
		"bloodcap": 30, "starblossom": 40, "grimshade": 50,
		"rust_spore_cap": 70, "nightshade_bramble": 74, "magma_root": 78,
		"sun_lit_lotus": 82, "gloom_spore_cap": 85, "iron_spike_thorn": 92,
	}
	for slug: String in herb_slugs:
		var node_res: MineableNodeResource = load(
			"res://source/common/gameplay/maps/components/mineable_nodes/%s.tres" % slug
		)
		if node_res == null:
			fails.append("node %s missing" % slug)
			continue
		if node_res.required_tool != &"sickle":
			fails.append("%s tool should be sickle" % slug)
		# Farming herbs harvest on right-click so woodcutting left-clicks pass through.
		if int(node_res.required_level) != int(expected_levels[slug]):
			fails.append("%s level %d != %d" % [slug, node_res.required_level, expected_levels[slug]])
		if not node_res.job_xp.has(&"harvesting"):
			fails.append("%s missing harvesting xp" % slug)
		# HerbalismItem copies its patch's level onto the ITEM so a bag tooltip can
		# say where the herb comes from without loading the node resource. A copy
		# drifts; this is the check that keeps it honest, and it is why the copy is
		# safe to have at all.
		var herb_item: HerbalismItem = node_res.ore as HerbalismItem
		if herb_item != null and herb_item.harvest_level != node_res.required_level:
			fails.append("%s item harvest_level %d != node %d" % [
				slug, herb_item.harvest_level, node_res.required_level
			])
		print("  node ", slug, " lv", node_res.required_level, " xp", node_res.job_xp.get(&"harvesting", 0))

	for sickle_slug: String in ["sickle", "sickle_iron", "sickle_steel", "sickle_mithril"]:
		var tool: ToolItem = load(
			"res://source/common/gameplay/items/weapons/tools/%s.tres" % sickle_slug
		)
		if tool == null:
			fails.append("tool %s missing" % sickle_slug)
			continue
		if tool.tool_type != &"sickle":
			fails.append("%s tool_type wrong" % sickle_slug)
		if tool.required_skill != &"harvesting":
			fails.append("%s should require harvesting" % sickle_slug)
		print("  tool ", sickle_slug, " farm_lv", tool.required_skill_level)

	if not LeaderboardService.TOTAL_LEVEL_SKILLS.has(&"herblore"):
		fails.append("TOTAL_LEVEL_SKILLS missing herblore")

	var mira_shop: ShopResource = load(
		"res://source/common/gameplay/shops/resources/miras_apothecary.tres"
	)
	if mira_shop == null:
		fails.append("miras_apothecary.tres failed to load")
	else:
		var vial_price := 0
		for entry: ShopEntry in mira_shop.entries:
			if entry == null or entry.item == null:
				continue
			if String(entry.item.get_meta(&"slug", &"")) == "vial_of_water":
				vial_price = entry.price
		if vial_price != VIAL_PRICE:
			fails.append("Mira should sell vial of water for %d, got %d" % [
				VIAL_PRICE, vial_price
			])

	# Potions are a PLAYER good: a vendor pays pocket change for one, so the only
	# worthwhile place to sell is the Trading Post. The cap is the point — if a
	# potion's vendor_value ever creeps back up, this fails.
	for path: String in POTION_VENDOR_VALUES.keys():
		var potion: Item = load(path)
		var want: int = int(POTION_VENDOR_VALUES[path])
		if potion == null:
			fails.append("%s failed to load" % path.get_file())
		elif potion.vendor_value != want:
			fails.append("%s vendor_value %d, want %d" % [
				path.get_file(), potion.vendor_value, want
			])
		elif potion.vendor_value > VENDOR_VALUE_CAP:
			fails.append("%s vendor_value %d is over the %dg cap" % [
				path.get_file(), potion.vendor_value, VENDOR_VALUE_CAP
			])

	fails.append_array(_check_no_potions_outside_dungeon())
	fails.append_array(_check_dungeon_prices())

	if fails.is_empty():
		print("VERIFY_PASS herblore")
		get_tree().quit(0)
	else:
		for f: String in fails:
			print("VERIFY_FAIL ", f)
		get_tree().quit(1)


## Sweeps every shop resource for potion stock. A potion back on a town vendor's
## shelf would quietly undercut the Trading Post, and it is one line in a .tres —
## exactly the kind of change that lands without anyone noticing.
func _check_dungeon_prices() -> Array[String]:
	var fails: Array[String] = []
	var shop: ShopResource = load(DUNGEON_SHOP) as ShopResource
	if shop == null:
		fails.append("lost_soul_shop.tres failed to load")
		return fails
	var seen: Dictionary = {}
	for entry: ShopEntry in shop.entries:
		if entry == null or entry.item == null:
			continue
		var path: String = entry.item.resource_path
		if not DUNGEON_POTION_PRICES.has(path):
			continue
		seen[path] = true
		var want: int = int(DUNGEON_POTION_PRICES[path])
		if entry.price != want:
			fails.append("Lost Soul %s costs %d, want %d" % [
				entry.item.item_name, entry.price, want
			])
	for path: String in DUNGEON_POTION_PRICES.keys():
		if not seen.has(path):
			fails.append("Lost Soul no longer stocks %s" % String(path).get_file())
	return fails


func _check_no_potions_outside_dungeon() -> Array[String]:
	var fails: Array[String] = []
	var dir: DirAccess = DirAccess.open(SHOP_DIR)
	if dir == null:
		fails.append("could not open %s" % SHOP_DIR)
		return fails
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var path: String = SHOP_DIR.path_join(file_name)
		if path == DUNGEON_SHOP:
			continue
		var shop: ShopResource = load(path) as ShopResource
		if shop == null or shop.entries == null:
			continue
		for entry: ShopEntry in shop.entries:
			if entry == null or entry.item == null:
				continue
			if POTION_VENDOR_VALUES.has(entry.item.resource_path):
				fails.append("%s still stocks %s — potions are dungeon-only" % [
					file_name, entry.item.item_name
				])
	return fails
