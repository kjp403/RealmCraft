class_name SkillXp
extends RefCounted
## Old-school RuneScape skill XP curve for profession skills.
## Level 99 requires 13,034,431 total XP. Levels are capped at 99.


const LEVEL_CAP: int = 99

## XP needed to advance from level N to N+1, indexed by (level - 1).
## Derived from the OSRS formula so sum(XP_TO_NEXT[0..97]) == 13_034_431.
## Stored as a static Array (not const PackedInt32Array) — Godot 4.7 rejects
## large PackedInt32Array literals as const expressions.
static var XP_TO_NEXT: Array[int] = [
	83, 91, 102, 112, 124, 138, 151, 168, 185, 204,
	226, 249, 274, 304, 335, 369, 408, 450, 497, 548,
	606, 667, 737, 814, 898, 990, 1094, 1207, 1332, 1470,
	1623, 1791, 1977, 2182, 2409, 2658, 2935, 3240, 3576, 3947,
	4358, 4810, 5310, 5863, 6471, 7144, 7887, 8707, 9612, 10612,
	11715, 12934, 14278, 15764, 17404, 19214, 21212, 23420, 25856, 28546,
	31516, 34795, 38416, 42413, 46826, 51699, 57079, 63019, 69576, 76818,
	84812, 93638, 103383, 114143, 126022, 139138, 153619, 169608, 187260, 206750,
	228269, 252027, 278259, 307221, 339198, 374502, 413482, 456519, 504037, 556499,
	614422, 678376, 748985, 826944, 913019, 1008052, 1112977, 1228825,
]


## XP required to go from [param level] → level+1. Returns 0 at/above the cap.
static func xp_to_next(level: int) -> int:
	if level < 1 or level >= LEVEL_CAP:
		return 0
	return int(XP_TO_NEXT[level - 1])


## Cumulative XP required to *reach* [param level] (level 1 = 0, level 99 = 13_034_431).
static func total_xp_for_level(level: int) -> int:
	var capped: int = clampi(level, 1, LEVEL_CAP)
	var total: int = 0
	for i: int in range(1, capped):
		total += xp_to_next(i)
	return total
