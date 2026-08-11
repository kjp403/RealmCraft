class_name JobPerks
extends Resource
## Data-driven definition of one job's progression: baseline rates, perk
## tree, and the human-readable UI lines. Every job is now a `.tres` file
## referencing this script — adding a new job is a content edit, not new
## code.
##
## Two effect domains coexist on the same class so gathering and crafting
## jobs share one shape:
##   - Gathering: cooldown reduction + bonus-yield chance + XP multiplier
##   - Crafting:  refund chance + extra-item chance + XP multiplier
## A job leaves the fields it doesn't use at zero. The generic helpers
## return 0.0 for any effect a job didn't define.
##
## Perks are an Array of Dictionaries (not nested resources) so designers
## can edit the perk list inline in the `.tres` without having to author a
## sub-resource per perk. Each perk dict:
##   {
##     "id":       StringName,  # &"diligent", &"frugal", etc.
##     "name":     String,      # UI label
##     "effect":   StringName,  # &"cooldown" / &"bonus_yield" / &"xp" / &"refund" / &"extra_item"
##     "per_rank": float,       # how much one rank adds to that effect
##     "max_rank": int,         # rank cap on this perk
##   }

@export var job_slug: StringName
@export var display_name: String
## Optional dedicated skill icon (OSRS-style). When set, Skills UI prefers
## this over falling back to the first gather/recipe item icon.
@export var icon: Texture2D
## &"gathering" or &"crafting" — drives Jobs-panel grouping.
@export var category: StringName
## Sort order WITHIN the category (lower = higher in the list). Lets us
## pin Mining above Harvesting even though the registry dict is iterated
## in insertion order.
@export var sort_order: int = 0

@export_group("Perk points")
## One perk point granted every N levels.
@export var perk_every_levels: int = 10

@export_group("Baseline (gathering only — leave 0 for crafting jobs)")
@export var cooldown_reduction_per_level: float = 0.0
@export var min_cooldown_factor: float = 0.5
@export var bonus_yield_per_level: float = 0.0
@export var max_bonus_yield_chance: float = 0.25

@export_group("Caps (absolute limits after perks)")
@export var abs_min_cooldown_factor: float = 0.3
@export var abs_max_bonus_yield_chance: float = 0.5
@export var abs_max_refund_chance: float = 0.5
@export var abs_max_extra_item_chance: float = 0.4

@export_group("Perks tree")
@export var perks: Array[Dictionary] = []

@export_group("Content preview (Jobs UI)")
## Items players can gather to feed THIS job's XP. Shown in the "Sources"
## tab — the client renders icon + item_name + (Lv X from [member
## source_levels]). Bake tool fills this from MineableNodeResource scans
## (`source/common/gameplay/jobs/bake_source_slugs.gd`).
@export var source_items: Array[Item] = []
## Parallel to [member source_items] — the required job-level the source
## was gated behind on its MineableNodeResource. Length must match
## source_items; 0 = no requirement.
@export var source_levels: Array[int] = []
## Items this job can craft (the recipe outputs). Shown in the "Recipes"
## tab the same way. Bake tool fills from CraftingStationResource scans.
## Do NOT put WeaponItem (or other scene-heavy items) here — JobRegistry
## preloads every JobPerks at startup, and WeaponItem → weapon scene →
## Client creates a circular load that freezes Skills at Total level 0.
@export var recipe_items: Array[Item] = []
## Parallel to [member recipe_items] — the required job-level on each
## recipe. 0 = no requirement.
@export var recipe_levels: Array[int] = []
## Recipe outputs loaded on demand when the Skills detail opens (not at
## JobRegistry preload). Use for WeaponItem and anything else that pulls
## Client-dependent scenes. Parallel to [member recipe_deferred_levels].
@export var recipe_deferred_paths: PackedStringArray = []
## Required job-level for each [member recipe_deferred_paths] entry.
@export var recipe_deferred_levels: Array[int] = []

@export_group("UI")
## describe() formats these against a context dict built from the current
## effective values. Available placeholders (each is an int percent):
##   {cooldown}      gather speed (1 - effective_cooldown_factor) * 100
##   {bonus_yield}   effective_bonus_yield_chance * 100
##   {xp}            (xp_multiplier - 1) * 100
##   {refund}        refund_chance * 100
##   {extra_item}    extra_item_chance * 100
## Example: "Gather speed +{cooldown}%"
@export var describe_lines: Array[String] = []


# ---------------------------------------------------------------------------
# Recipe guide (eager + deferred)
# ---------------------------------------------------------------------------

## True when this job has any craft recipe listed for the Skills UI.
func has_recipe_guide() -> bool:
	return not recipe_items.is_empty() or not recipe_deferred_paths.is_empty()


## Resolved craft-guide rows for the Skills / Jobs UI. Eager [member
## recipe_items] plus deferred paths loaded on demand, sorted by level then
## name so metal weapons sit with their bars (not buried after Dragon).
## Each entry: `{ "item": Item, "level": int }`. Missing paths are skipped.
func recipe_guide_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in recipe_items.size():
		var item: Item = recipe_items[i]
		if item == null:
			continue
		var lvl: int = recipe_levels[i] if i < recipe_levels.size() else 0
		out.append({"item": item, "level": lvl})
	for i: int in recipe_deferred_paths.size():
		var path: String = recipe_deferred_paths[i]
		if path.is_empty():
			continue
		var loaded: Resource = load(path)
		var item: Item = loaded as Item
		if item == null:
			push_warning("JobPerks %s: deferred recipe path failed: %s" % [job_slug, path])
			continue
		var lvl: int = (
			recipe_deferred_levels[i] if i < recipe_deferred_levels.size() else 0
		)
		out.append({"item": item, "level": lvl})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var la: int = int(a["level"])
		var lb: int = int(b["level"])
		if la != lb:
			return la < lb
		var ia: Item = a["item"] as Item
		var ib: Item = b["item"] as Item
		return String(ia.item_name) < String(ib.item_name)
	)
	return out


# ---------------------------------------------------------------------------
# Perk-point bookkeeping (job-agnostic)
# ---------------------------------------------------------------------------

func earned_points(level: int) -> int:
	if perk_every_levels <= 0:
		return 0
	@warning_ignore("integer_division")
	return level / perk_every_levels # floored on purpose — N levels per perk point


func spent_points(player_perks: Dictionary) -> int:
	var total: int = 0
	for perk_id in player_perks:
		total += int(player_perks[perk_id])
	return total


func available_points(skill: Dictionary) -> int:
	return earned_points(int(skill.get("level", 1))) - spent_points(skill.get("perks", {}))


func rank(player_perks: Dictionary, perk_id: StringName) -> int:
	return int(player_perks.get(perk_id, 0))


# ---------------------------------------------------------------------------
# Generic effect sum — adds up (per_rank × player's rank) over every perk
# whose effect matches. Returns 0.0 for effects no perk targets, so a
# crafting job calling sum_effect(&"cooldown") just gets 0 cleanly.
# ---------------------------------------------------------------------------

func sum_effect(player_perks: Dictionary, effect: StringName) -> float:
	# Perks come from .tres with String values (the resource parser doesn't
	# accept StringName literals inside Array[Dictionary] entries), so
	# coerce to StringName here for the comparison + the player-perks
	# rank lookup.
	var total: float = 0.0
	for perk in perks:
		if StringName(String(perk.get("effect", ""))) != effect:
			continue
		var per_rank: float = float(perk.get("per_rank", 0.0))
		var r: int = rank(player_perks, StringName(String(perk.get("id", ""))))
		total += per_rank * float(r)
	return total


# ---------------------------------------------------------------------------
# Effective values
# ---------------------------------------------------------------------------

func cooldown_factor(level: int) -> float:
	# Baseline-only — used by the gather-speed UI line as a "before perks" reference.
	return clampf(1.0 - cooldown_reduction_per_level * float(level - 1), min_cooldown_factor, 1.0)


func effective_cooldown_factor(level: int, player_perks: Dictionary) -> float:
	var factor: float = cooldown_factor(level) - sum_effect(player_perks, &"cooldown")
	return clampf(factor, abs_min_cooldown_factor, 1.0)


func bonus_yield_chance(level: int) -> float:
	return minf(max_bonus_yield_chance, bonus_yield_per_level * float(level - 1))


func effective_bonus_yield_chance(level: int, player_perks: Dictionary) -> float:
	return minf(abs_max_bonus_yield_chance, bonus_yield_chance(level) + sum_effect(player_perks, &"bonus_yield"))


func xp_multiplier(player_perks: Dictionary) -> float:
	return 1.0 + sum_effect(player_perks, &"xp")


func refund_chance(player_perks: Dictionary) -> float:
	return minf(abs_max_refund_chance, sum_effect(player_perks, &"refund"))


func extra_item_chance(player_perks: Dictionary) -> float:
	return minf(abs_max_extra_item_chance, sum_effect(player_perks, &"extra_item"))


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

func describe(level: int, player_perks: Dictionary) -> PackedStringArray:
	var context: Dictionary = {
		"cooldown": roundi((1.0 - effective_cooldown_factor(level, player_perks)) * 100.0),
		"bonus_yield": roundi(effective_bonus_yield_chance(level, player_perks) * 100.0),
		"xp": roundi((xp_multiplier(player_perks) - 1.0) * 100.0),
		"refund": roundi(refund_chance(player_perks) * 100.0),
		"extra_item": roundi(extra_item_chance(player_perks) * 100.0),
	}
	var out: PackedStringArray = PackedStringArray()
	for line in describe_lines:
		out.append(String(line).format(context))
	return out


## Human-readable "what one rank does" for the perk picker UI.
static func describe_perk_effect(effect: String, per_rank: float) -> String:
	var pct: int = roundi(per_rank * 100.0)
	match effect:
		"xp":
			return "+%d%% skill XP per rank" % pct
		"cooldown":
			return "+%d%% gather speed per rank" % pct
		"bonus_yield":
			return "+%d%% bonus yield chance per rank" % pct
		"refund":
			return "+%d%% material refund chance per rank" % pct
		"extra_item":
			return "+%d%% extra item chance per rank" % pct
		"skip_discount":
			return "-%d%% Slayer task reassignment cost per rank" % pct
		_:
			return "Specializes this skill (+%.0f%% per rank)." % (per_rank * 100.0)


## Short explanation of how perk points are earned for this job.
func points_rules_text() -> String:
	if perk_every_levels <= 0:
		return "This skill does not grant perk points."
	return (
		"Earn 1 perk point every %d levels in this skill. Spend points to specialize — each rank stacks a permanent bonus. Unspent points do nothing until assigned."
		% perk_every_levels
	)


# ---------------------------------------------------------------------------
# Compatibility shim — older code calls perks_class.PERKS expecting a dict.
# Returns a generated dict keyed by perk id so the perk-picker UI keeps
# working without a rewrite. New code should iterate the [member perks]
# Array directly.
# ---------------------------------------------------------------------------

func get_perk_def(perk_id: StringName) -> Dictionary:
	for perk in perks:
		if StringName(String(perk.get("id", ""))) == perk_id:
			return perk
	return {}


func has_perk(perk_id: StringName) -> bool:
	return not get_perk_def(perk_id).is_empty()
