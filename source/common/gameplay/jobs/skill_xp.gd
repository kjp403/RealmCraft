class_name SkillXp
extends RefCounted
## Canonical Old School RuneScape skill XP curve for every profession skill.
##
## All jobs in [JobRegistry] (current and future) gain XP through
## [method PlayerResource.add_skill_xp], which reads this table — so new skills
## inherit the curve automatically. Level 99 requires 13,034,431 total XP.
##
## Formula (Jagex / OSRS):
##   points(level) = floor(level + 300 * 2^(level/7))
##   total_xp(L)   = floor( sum_{i=1}^{L-1} points(i) / 4 )
##   xp_to_next(L) = total_xp(L+1) - total_xp(L)


const LEVEL_CAP: int = 99
const TOTAL_XP_AT_CAP: int = 13_034_431

## XP needed to advance from level N to N+1, indexed by (level - 1).
## Baked once from the OSRS formula in [_static_init].
static var XP_TO_NEXT: Array[int] = []


static func _static_init() -> void:
	_bake_table()


## Build XP_TO_NEXT from the OSRS formula so the table cannot drift from
## Jagex's curve. Godot 4.7 rejects large PackedInt32Array const literals,
## so this is a static Array filled at class load.
static func _bake_table() -> void:
	XP_TO_NEXT.clear()
	XP_TO_NEXT.resize(LEVEL_CAP - 1)
	var prev_total: int = 0
	for level: int in range(1, LEVEL_CAP):
		var next_total: int = _cumulative_xp(level + 1)
		XP_TO_NEXT[level - 1] = next_total - prev_total
		prev_total = next_total


## Raw OSRS cumulative XP to *reach* [param level] (level 1 = 0).
static func _cumulative_xp(level: int) -> int:
	if level <= 1:
		return 0
	var points_sum: float = 0.0
	for i: int in range(1, level):
		points_sum += floorf(float(i) + 300.0 * pow(2.0, float(i) / 7.0))
	return int(floorf(points_sum / 4.0))


## XP required to go from [param level] → level+1. Returns 0 at/above the cap.
static func xp_to_next(level: int) -> int:
	if level < 1 or level >= LEVEL_CAP:
		return 0
	if XP_TO_NEXT.is_empty():
		_bake_table()
	return int(XP_TO_NEXT[level - 1])


## Cumulative XP required to *reach* [param level] (level 1 = 0, level 99 = 13_034_431).
static func total_xp_for_level(level: int) -> int:
	var capped: int = clampi(level, 1, LEVEL_CAP)
	if capped <= 1:
		return 0
	if XP_TO_NEXT.is_empty():
		_bake_table()
	var total: int = 0
	for i: int in range(1, capped):
		total += int(XP_TO_NEXT[i - 1])
	return total
