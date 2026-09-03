class_name HerbalismItem
extends MaterialItem
## A FARMED herb: the gathered input side of Herblore.
##
## Extends [MaterialItem] rather than replacing it, because a herb already IS a
## material everywhere that matters — the bag tab, the trade rules, the vendor
## sale, the crafting ingredient lookup. Forking that into a parallel item type
## would mean teaching [Inventory], the shops, the market and the salvage table
## about a second "material-ish" class, and every one of them that was missed
## would fail closed and silently.
##
## What is genuinely new here is AUTHORING METADATA the old herbs carry only in
## their prose description: which patch tier grows it, and which draught it is
## the catalyst for. Those two facts are read by tooling (the patch planter, the
## recipe audit) and by the tooltip, so they belong in fields rather than in a
## sentence a human has to parse.
##
## The seven starter herbs (Healing Herb ... Grimshade) stay plain [MaterialItem]
## and keep working untouched. Nothing reads [HerbalismItem] as a REQUIREMENT —
## it is a richer authoring surface, not a new contract.


## Herblore tiers, in the order the skill unlocks them. Purely descriptive: it
## drives the tooltip line and lets the patch tooling group herbs without
## hard-coding level numbers in two places.
enum Tier {
	COMMON,   ## Healing Herb / Frostpetal band — roadside, no gate worth naming.
	UNCOMMON, ## Sunwort / Moonbloom.
	RARE,     ## Bloodcap / Starblossom / Grimshade.
	ENDGAME,  ## The high-tier farming patches this class was added for.
}

## Where the patch grows. Not a map name — a BIOME FAMILY, so a herb can be
## planted in several maps of the same character without re-authoring.
@export var tier: Tier = Tier.ENDGAME
## Harvesting level the patch itself gates on. Mirrors the value authored on the
## matching [MineableNodeResource]; kept here so a tooltip in the bag can explain
## where the herb comes from without loading the node resource.
##
## It is deliberately a COPY, not the source of truth — the node resource gates
## the actual gather. `tools/verify_herblore.gd` compares the two and fails on
## drift, which is cheaper than a lookup on every tooltip draw.
@export var harvest_level: int = 60
## Herblore level of the draught this herb is the catalyst for. Same copy-and-
## verify arrangement as [member harvest_level].
@export var herblore_level: int = 90
## Slug of the potion this herb is the catalyst for (&"venom_draught"). Empty for
## a herb that is only an ingredient rather than THE defining one.
##
## One-way on purpose: the recipe lives on the alchemy station, and a herb that
## claimed to own a recipe would be a second place to change when the recipe
## moves. This is a label for the tooltip and the audit, not a lookup.
@export var catalyst_for: StringName = &""
## Free-form biome hint shown on the tooltip ("Emberlands", "Sunken Grove").
@export var patch_biome: String = ""


func _init() -> void:
	super()
	# Endgame herbs are the scarce half of every combination draught, so they
	# stack like the rest of the herb ladder rather than filling a bag.
	stack_limit = 10


func stat_lines() -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	if harvest_level > 1:
		lines.append({
			"text": "Requires Harvesting %d" % harvest_level, "kind": &"level",
		})
	if not patch_biome.is_empty():
		lines.append({"text": "Grows in %s" % patch_biome, "kind": &"level"})
	if not catalyst_for.is_empty():
		lines.append({
			"text": "Catalyst: %s (Herblore %d)" % [
				String(catalyst_for).capitalize(), herblore_level,
			],
			"kind": &"charges",
		})
	return lines
