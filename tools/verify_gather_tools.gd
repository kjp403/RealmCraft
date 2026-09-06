extends Node
## Headless gate: the gathering-tool ladder still keeps up with node HP.
##
## WHY THIS EXISTS
## Nothing modelled [member MineableNodeResource.extraction_hp] before this.
## The XP rebuild in 74d883fa priced every gather ladder off swings-per-yield
## (extraction_hp / tool power) in a throwaway spreadsheet, so when the
## expansion nodes landed on a steep HP curve (Yew 6 -> Wispwood 24 -> Nebula 42
## -> Glimmer 64 -> Rosewood 90) against a flat +1-per-tier tool curve, nothing
## caught it. A Celestial Axe took 12 swings per Rosewood log where every
## pre-expansion tier took 2, and each axe upgrade bought one swing out of
## twelve. Kyle reported it as "tool power doesn't do much".
##
## The three invariants below are exactly what drifted:
##   1. A node worked with the best tool its own level gate allows must not need
##      more than MAX_SWINGS swings. This is the one that broke.
##   2. Gather rate (power / swing_cooldown) must never fall along a tool
##      ladder, so buying the next tier is never a downgrade.
##   3. Swings per yield must never rise as tool tier rises, on any node.
##
## Runs as a SCENE, not as `-s`: JobRegistry is an autoload and
## MineableNodeResource pulls in the shimmer shader. See tools/run_verify.sh.
##
##   godot --headless --path . res://tools/verify_gather_tools.tscn

const NODE_DIR := "res://source/common/gameplay/maps/components/mineable_nodes/"
const TOOL_DIR := "res://source/common/gameplay/items/weapons/tools/"
## The starter Wooden tools deliberately leave extraction_damage / swing_cooldown
## at -1 and inherit whatever their swing ability is authored with, so a tool's
## real numbers only resolve against these.
const SWING_DIR := "res://source/common/gameplay/combat/ability/ability_collection/pick_swing/"

## Ceiling on swings per yield with the best tool the node's own level gate
## allows. Rosewood at 12 is what this exists to catch; the pre-expansion tiers
## sit at 2-3 and the reworked expansion tiers at 4-6.
const MAX_SWINGS: int = 8

## Per-yield cooldown multipliers to report xp/hr at. 0.5 is the level-only
## floor (JobPerks.min_cooldown_factor) — a player who just hit the gate and has
## spent no perk points. 0.27 is endgame: the 0.3 abs_min_cooldown_factor with a
## full skilling outfit's SPEED bonus on top. The XP curve is pinned at 0.27.
const FACTOR_FRESH: float = 0.5
const FACTOR_ENDGAME: float = 0.27

var _fails: int = 0
## tool_type -> [extraction_damage, cooldown] the swing ability supplies when a
## tool leaves its own values at the -1 sentinel.
var _swing_defaults: Dictionary = {}


func _ready() -> void:
	_load_swing_defaults()
	var tools: Dictionary = _load_tools()
	_check_tool_ladders(tools)
	_check_nodes(tools)
	if _fails > 0:
		print("VERIFY_FAIL %d problem(s)" % _fails)
		get_tree().quit(1)
		return
	print("VERIFY_PASS")
	get_tree().quit(0)


func _fail(msg: String) -> void:
	printerr("FAIL ", msg)
	_fails += 1


func _load_swing_defaults() -> void:
	var dir := DirAccess.open(SWING_DIR)
	if dir == null:
		_fail("cannot open " + SWING_DIR)
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var swing: PickSwingAbility = ResourceLoader.load(SWING_DIR + fname) as PickSwingAbility
			if swing != null:
				_swing_defaults[swing.tool_type] = [swing.extraction_damage, swing.cooldown]
		fname = dir.get_next()
	dir.list_dir_end()


## Resolve a tool's real numbers, filling the -1 sentinel from its swing ability.
func _resolved(tool_item: ToolItem) -> Array:
	var fallback: Array = _swing_defaults.get(tool_item.tool_type, [1, 0.45])
	var damage: int = tool_item.extraction_damage if tool_item.extraction_damage > 0 else int(fallback[0])
	var cd: float = tool_item.swing_cooldown if tool_item.swing_cooldown > 0.0 else float(fallback[1])
	return [maxi(1, damage), maxf(0.01, cd)]


## tool_type -> Array[ToolItem], ascending by required_skill_level.
func _load_tools() -> Dictionary:
	var by_type: Dictionary = {}
	var dir := DirAccess.open(TOOL_DIR)
	if dir == null:
		_fail("cannot open " + TOOL_DIR)
		return by_type
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var tool_item: ToolItem = ResourceLoader.load(TOOL_DIR + fname) as ToolItem
			if tool_item != null and tool_item.tool_type != &"":
				var list: Array = by_type.get(tool_item.tool_type, [])
				list.append(tool_item)
				by_type[tool_item.tool_type] = list
		fname = dir.get_next()
	dir.list_dir_end()
	for tool_type: StringName in by_type:
		var list: Array = by_type[tool_type]
		list.sort_custom(func(a: ToolItem, b: ToolItem) -> bool:
			return a.required_skill_level < b.required_skill_level
		)
	return by_type


## Effective extraction rate in HP per second — the number that actually decides
## how long a yield takes, and the one a tier must never lose on.
func _gather_rate(tool_item: ToolItem) -> float:
	var r: Array = _resolved(tool_item)
	return float(r[0]) / float(r[1])


func _check_tool_ladders(tools: Dictionary) -> void:
	for tool_type: StringName in tools:
		var list: Array = tools[tool_type]
		var prev: ToolItem = null
		for tool_item: ToolItem in list:
			# A tier that gathers SLOWER than the one below it is the failure.
			# An exact tie is only ever the starter tool sharing its numbers with
			# Bronze, which costs a player nothing — reported, not failed.
			if prev != null:
				var rate: float = _gather_rate(tool_item)
				var prev_rate: float = _gather_rate(prev)
				if rate < prev_rate:
					_fail("%s (%.1f hp/s) gathers slower than %s (%.1f hp/s)" % [
						tool_item.item_name, rate, prev.item_name, prev_rate,
					])
				elif is_equal_approx(rate, prev_rate):
					print("  note: %s and %s gather at the same rate (%.1f hp/s)" % [
						prev.item_name, tool_item.item_name, rate,
					])
			prev = tool_item
		var names: PackedStringArray = PackedStringArray()
		for tool_item: ToolItem in list:
			var r: Array = _resolved(tool_item)
			names.append("%s %d/%.2f" % [String(tool_item.item_name).split(" ")[0], r[0], r[1]])
		print("%-12s ladder: %s" % [tool_type, ", ".join(names)])


func _swings(hp: int, tool_item: ToolItem) -> int:
	return ceili(float(hp) / float(int(_resolved(tool_item)[0])))


## Best tool of the right type a player standing at this node can legally hold.
## Node gates and tool gates read the same skill, so the node's required_level
## is exactly the player level to assume.
func _best_tool(tools: Dictionary, required_tool: StringName, level: int) -> ToolItem:
	var best: ToolItem = null
	for tool_item: ToolItem in tools.get(required_tool, []):
		if tool_item.required_skill_level <= maxi(1, level):
			if best == null or _gather_rate(tool_item) > _gather_rate(best):
				best = tool_item
	return best


func _check_nodes(tools: Dictionary) -> void:
	var dir := DirAccess.open(NODE_DIR)
	if dir == null:
		_fail("cannot open " + NODE_DIR)
		return
	var rows: Array[Array] = []
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var data: MineableNodeResource = ResourceLoader.load(NODE_DIR + fname) as MineableNodeResource
			if data != null:
				rows.append([fname.trim_suffix(".tres"), data])
		fname = dir.get_next()
	dir.list_dir_end()

	rows.sort_custom(func(a: Array, b: Array) -> bool:
		var da: MineableNodeResource = a[1]
		var db: MineableNodeResource = b[1]
		if da.required_tool != db.required_tool:
			return String(da.required_tool) < String(db.required_tool)
		return da.required_level < db.required_level
	)

	print("\n%-26s %-12s %3s %4s  %5s  %-12s %3s  %8s  %8s" % [
		"node", "tool", "lvl", "hp", "xp", "best tool", "sw", "xp/hr@.5", "xp/hr@.27",
	])
	var prev_tool: StringName = &""
	var prev_rate: float = 0.0
	var prev_slug: String = ""
	for row: Array in rows:
		var slug: String = row[0]
		var data: MineableNodeResource = row[1]
		if data.required_tool == &"":
			continue
		var best: ToolItem = _best_tool(tools, data.required_tool, data.required_level)
		if best == null:
			_fail("%s needs a %s but no %s exists at level %d"
				% [slug, data.required_tool, data.required_tool, data.required_level])
			continue

		var swings: int = _swings(data.extraction_hp, best)
		if swings > MAX_SWINGS:
			_fail("%s: %d swings with a %s (max %d) — node HP has outrun the tool ladder"
				% [slug, swings, best.item_name, MAX_SWINGS])

		# Swings must never rise with tier. A tool that hits harder but is gated
		# higher is still allowed to tie (integer swing counts quantise hard on
		# a low-HP node), it just may not cost MORE swings than a weaker tool.
		var prev_swings: int = 1 << 30
		for tool_item: ToolItem in tools.get(data.required_tool, []):
			var this_swings: int = _swings(data.extraction_hp, tool_item)
			if this_swings > prev_swings:
				_fail("%s: %s needs %d swings, more than the tier below it (%d)"
					% [slug, tool_item.item_name, this_swings, prev_swings])
			prev_swings = this_swings

		var xp: int = 0
		for job: StringName in data.job_xp:
			xp = int(data.job_xp[job])
			break
		var chop: float = float(swings) * float(_resolved(best)[1])
		var fresh: float = chop + data.player_cooldown_seconds * FACTOR_FRESH
		var endgame: float = chop + data.player_cooldown_seconds * FACTOR_ENDGAME
		var rate_endgame: float = float(xp) * 3600.0 / endgame
		print("%-26s %-12s %3d %4d  %5d  %-12s %3d  %8.0f  %8.0f" % [
			slug, data.required_tool, data.required_level, data.extraction_hp, xp,
			String(best.item_name).split(" ")[0], swings,
			float(xp) * 3600.0 / fresh, rate_endgame,
		])

		# Unlocking a higher node that pays LESS per hour than the one below it
		# is the same defect one level up: the node tier moved and the tool
		# ladder did not follow. Reported rather than failed — Fishing has a
		# standing one (Halibut opens at 60, the Dragon rod at 65), and that is
		# content to add, not a number to nudge.
		if data.required_tool == prev_tool and rate_endgame < prev_rate:
			print("  note: %s pays %.0f xp/hr, less than %s at %.0f — inverted ladder"
				% [slug, rate_endgame, prev_slug, prev_rate])
		prev_tool = data.required_tool
		prev_rate = rate_endgame
		prev_slug = slug
