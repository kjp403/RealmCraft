class_name DailyRewardTable
extends Resource
## Payout curve for the skilling daily board. One table serves all nine skills
## and all three difficulties: a BASE payout is scaled by a per-difficulty
## multiplier, so tuning the whole board is a two-number edit rather than
## 9 x 3 hand-authored reward rows.
##
## Why a multiplier instead of 27 authored values: the difficulty bands
## ([constant DailyTaskResource.QUANTITY_BANDS]) already encode "how much work",
## with midpoints of roughly 37 / 150 / 400 actions — a 1 : 4 : 10.7 ratio. The
## default multipliers (1 / 4.5 / 14) sit deliberately ABOVE that ratio so a Hard
## task pays ~30% more per action than an Easy one. Hard is a whole-session
## commitment; it has to beat farming Easy three times over or nobody picks it.
##
## Skill XP is paid as a FRACTION OF A LEVEL rather than a flat number. A flat
## grant is either insulting at level 80 or trivialises level 20 — there is no
## single good constant across an OSRS 1-99 curve ([SkillXp]). Paying
## `xp_to_next(level) * fraction` self-balances the whole curve for free.

## Gold paid for an EASY task. Medium/Hard scale from here.
@export var base_gold: int = 500
## Adventure XP (the lifetime HUD counter — levels nothing, see
## [member PlayerResource.experience]) paid for an EASY task.
@export var base_adventure_xp: int = 30
## Share of the assigned skill's CURRENT level-up requirement paid for an EASY
## task. 0.025 = 2.5% of a level; Hard therefore pays ~35% of a level.
@export var base_skill_xp_fraction: float = 0.025
## Floor under the fraction, for level 99 (where xp_to_next is 0) and for the
## very low levels where 2.5% of a level rounds to noise.
@export var base_skill_xp_min: int = 120

## Indexed by [enum DailyTaskResource.Difficulty] — EASY, MEDIUM, HARD.
## Must stay length-3; [method multiplier_for] falls back to 1.0 if it isn't,
## so a mis-authored table under-pays instead of crashing a claim.
@export var difficulty_multipliers: PackedFloat32Array = PackedFloat32Array([1.0, 4.5, 14.0])


## Scale factor for [param difficulty]. Out-of-range or a short/mis-authored
## array yields 1.0 — a claim must never fail because content is wrong.
func multiplier_for(difficulty: int) -> float:
	if difficulty < 0 or difficulty >= difficulty_multipliers.size():
		return 1.0
	return maxf(0.0, difficulty_multipliers[difficulty])


func gold_for(difficulty: int) -> int:
	return maxi(0, roundi(float(base_gold) * multiplier_for(difficulty)))


func adventure_xp_for(difficulty: int) -> int:
	return maxi(0, roundi(float(base_adventure_xp) * multiplier_for(difficulty)))


## Skill XP for [param difficulty] at [param skill_level]. Takes the larger of
## "a fraction of this level's XP requirement" and the scaled floor, so level 99
## (xp_to_next == 0) still pays out instead of silently granting nothing.
func skill_xp_for(difficulty: int, skill_level: int) -> int:
	var mult: float = multiplier_for(difficulty)
	var to_next: int = SkillXp.xp_to_next(clampi(skill_level, 1, SkillXp.LEVEL_CAP))
	var scaled: int = roundi(float(to_next) * base_skill_xp_fraction * mult)
	var floor_xp: int = roundi(float(base_skill_xp_min) * mult)
	return maxi(scaled, floor_xp)
