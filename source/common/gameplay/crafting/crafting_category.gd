class_name CraftingCategory
extends RefCounted
## Which tab a crafting recipe belongs to at a given station, and in what order
## those tabs are shown.
##
## This lives in `common/` rather than beside the crafting menu so a verifier
## can assert the real rule instead of a copy of it. The tab a recipe lands in
## is authored nowhere — it is DERIVED from the output item's type, path and
## name — so the only way to catch a recipe falling into the wrong tab is to run
## the same function the menu runs.
##
## Categories are plain StringNames rather than an enum because a station may
## surface any subset of them, and [method label] is the only place they become
## user-facing text.

## Smithing Table metal tiers, each its own tab.
##
## Adamant, Runite and Dragon used to collapse into a single "Ascended" tab
## along with every ascension set above them, because the tier lookup began with
## `required_level >= 50 -> ascended` and that test ran BEFORE the metal-name
## match. The result was one tab holding Adamant, Dragon, Basilisk, Runewoven,
## Astral, Wyrmguard, Runite and Godsteel interleaved. The ascension sets now
## live on the Ascended Workbench, so every metal tier gets the dedicated tab
## the low end always had.
const SMITHING_TIERS: Array[StringName] = [
	&"bronze", &"iron", &"steel", &"mithril", &"adamant", &"runite", &"dragon",
]

## Tier tokens matched against the output's name + path, longest / most specific
## first so "adamant" cannot be shadowed by a shorter token.
const _TIER_TOKENS: Array[StringName] = [
	&"mithril", &"adamant", &"runite", &"dragon", &"bronze", &"steel", &"iron",
]


## The tab [param recipe] belongs to at [param station].
##
## A Smithing bench uses metal tiers plus Tools / Jewelry / Materials; every
## other bench uses Armor / Weapons / Cloth / Leather plus the same two.
## There is deliberately no "all" tab — mixing categories interleaves
## unrelated rows, which is the problem this whole split exists to fix.
static func of(recipe: CraftingRecipe, station: CraftingStationResource) -> StringName:
	if recipe == null or recipe.output_item == null:
		return &"materials"
	if recipe.output_item is MaterialItem:
		return &"materials"
	if is_jewelry(recipe.output_item):
		return &"jewelry"
	if station != null and station.profession == &"smithing":
		# Gathering tools get their own tab instead of scattering one pickaxe,
		# axe and sickle across seven metal tabs. This has to beat the tier
		# check below, which matches on the metal in the name: without it the
		# Dragon pickaxe would sit under Dragon, away from the other pickaxes.
		if recipe.output_item is ToolItem:
			return &"tools"
		return smithing_tier(recipe)
	var path: String = recipe.output_item.resource_path
	# Weapons before the cloth / leather split: a bench hosting both gear and
	# weapons (the Ascended Workbench) would otherwise dump every sword, bow,
	# hammer, wand and book into the "armor" catch-all at the end.
	if path.contains("/weapons/"):
		return &"weapons"
	if path.contains("/cloth/"):
		return &"cloth"
	if path.contains("/leather/"):
		return &"leather"
	return &"armor"


## Rings + necklaces / amulets / relics under gears/jewelry (or a ring slot).
static func is_jewelry(item: Item) -> bool:
	if item == null:
		return false
	var path: String = item.resource_path
	if path.contains("/jewelry/") or path.contains("/rings/"):
		return true
	var gear: GearItem = item as GearItem
	if gear == null or gear.slot == null:
		return false
	var slot_file: String = gear.slot.resource_path.get_file()
	return (
		slot_file.begins_with("ring")
		or slot_file.begins_with("amulet")
		or slot_file.begins_with("relic")
	)


## Bronze…Dragon from the output's name / path.
static func smithing_tier(recipe: CraftingRecipe) -> StringName:
	var haystack: String = (
		String(recipe.output_item.item_name) + " " + recipe.output_item.resource_path
	).to_lower()
	for tier: StringName in _TIER_TOKENS:
		if haystack.contains(String(tier)):
			return tier
	# Unmatched metal (tools named oddly, copper leftovers) — still smithable.
	return &"bronze"


## Tab order for [param station]. Categories not present are skipped by the
## caller; anything unexpected is appended rather than dropped.
static func preferred_order(station: CraftingStationResource) -> Array[StringName]:
	var out: Array[StringName] = []
	if station != null and station.profession == &"smithing":
		out.append_array(SMITHING_TIERS)
		out.append_array([&"tools", &"jewelry", &"materials"])
	else:
		out.append_array([
			&"armor", &"weapons", &"cloth", &"leather", &"jewelry", &"materials",
		])
	return out


## User-facing tab text.
static func label(cat: StringName) -> String:
	match cat:
		&"jewelry":
			return "Jewelry"
		&"materials":
			return "Materials"
		_:
			return String(cat).capitalize()
