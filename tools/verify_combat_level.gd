extends SceneTree
## Headless checks for mastery-derived character level.
##   - level is DERIVED from the five weapon masteries ONLY, capped at 126
##   - Slayer and the gathering jobs must NOT move it
##   - it advances automatically when a mastery level lands
##   - attribute points track the level, and are never granted twice
##   - character xp_reward no longer levels anyone

const CATS: Array[StringName] = [&"sword", &"hammer", &"bow", &"wand", &"book"]


func _init() -> void:
	var failures: Array[String] = []

	# --- Formula anchors ---------------------------------------------------
	var p := PlayerResource.new()
	if p.derived_combat_level() != 1:
		failures.append("fresh character is level %d, expected 1" % p.derived_combat_level())

	# All five at 99 -> exactly the 126 cap (the point of the 7/11 weights).
	for c: StringName in CATS:
		p.masteries[c] = {"level": 99, "xp": 0, "spent": {}}
	if p.derived_combat_level() != 126:
		failures.append("all-99 gives combat level %d, expected 126" % p.derived_combat_level())

	# SLAYER MUST NOT CONTRIBUTE. 99 Slayer on an untrained character stays level 1.
	var slayer_only := PlayerResource.new()
	slayer_only.skills[&"slayer"] = {"level": 99, "xp": 0, "perks": {}}
	if slayer_only.derived_combat_level() != 1:
		failures.append("99 Slayer alone gives combat level %d, expected 1" % slayer_only.derived_combat_level())
	# ...nor on top of a trained character.
	var with_slayer := PlayerResource.new()
	with_slayer.masteries[&"sword"] = {"level": 70, "xp": 0, "spent": {}}
	var without: int = with_slayer.derived_combat_level()
	with_slayer.skills[&"slayer"] = {"level": 99, "xp": 0, "perks": {}}
	if with_slayer.derived_combat_level() != without:
		failures.append("adding 99 Slayer moved combat level %d -> %d" % [without, with_slayer.derived_combat_level()])

	# A lone specialist must be respectable but short of cap; breadth earns the rest.
	var solo := PlayerResource.new()
	solo.masteries[&"sword"] = {"level": 99, "xp": 0, "spent": {}}
	var solo_level: int = solo.derived_combat_level()
	if solo_level >= 126:
		failures.append("one maxed weapon alone hit the cap (%d)" % solo_level)
	if solo_level < 60:
		failures.append("one maxed weapon alone gives only %d — specialists stranded" % solo_level)

	# Monotonic: level must never fall as a mastery rises.
	var prev: int = 0
	for lvl: int in range(1, 100):
		var probe := PlayerResource.new()
		probe.masteries[&"bow"] = {"level": lvl, "xp": 0, "spent": {}}
		var got: int = probe.derived_combat_level()
		if got < prev:
			failures.append("combat level fell from %d to %d at mastery %d" % [prev, got, lvl])
		if got < 1 or got > 126:
			failures.append("combat level %d out of range at mastery %d" % [got, lvl])
		prev = got

	# --- It actually advances on a mastery level-up ------------------------
	var live := PlayerResource.new()
	var before: int = live.level
	live.add_mastery_xp(&"sword", SkillXp.total_xp_for_level(40))
	if int(live.get_mastery(&"sword").get("level", 1)) < 40:
		failures.append("mastery did not reach 40 from a bulk grant")
	if live.level <= before:
		failures.append("character level stayed %d after a mastery climb to 40" % live.level)
	if live.level != live.derived_combat_level():
		failures.append("level %d out of sync with derived %d" % [live.level, live.derived_combat_level()])
	if live.available_attributes_points != PlayerResource.attribute_points_at_level(live.level):
		failures.append("banked %d attribute points at level %d, expected %d"
			% [live.available_attributes_points, live.level, PlayerResource.attribute_points_at_level(live.level)])

	# Neither Slayer nor a gathering skill may move it.
	var lvl_before: int = live.level
	live.add_skill_xp(&"slayer", SkillXp.total_xp_for_level(60))
	if live.level != lvl_before:
		failures.append("Slayer XP raised combat level %d -> %d" % [lvl_before, live.level])
	live.add_skill_xp(&"mining", SkillXp.total_xp_for_level(50))
	if live.level != lvl_before:
		failures.append("mining raised combat level %d -> %d" % [lvl_before, live.level])

	# --- Points are never double-granted -----------------------------------
	var pts: int = live.available_attributes_points
	var resynced: int = live.sync_combat_level()
	if resynced != 0 or live.available_attributes_points != pts:
		failures.append("re-syncing granted %d extra points" % (live.available_attributes_points - pts))

	# --- Character xp no longer levels -------------------------------------
	var xp_only := PlayerResource.new()
	var got_xp: Dictionary = xp_only.add_experience(500_000)
	if xp_only.level != 1:
		failures.append("add_experience levelled the character to %d" % xp_only.level)
	if int(got_xp.get("levels_gained", -1)) != 0:
		failures.append("add_experience reported %d levels gained" % int(got_xp.get("levels_gained", -1)))
	if xp_only.experience != 500_000:
		failures.append("adventure xp counter did not bank (%d)" % xp_only.experience)

	# --- Budgets held roughly flat vs the old 1-20 x 3/level ladder --------
	var at_cap: int = PlayerResource.attribute_points_at_level(126)
	if at_cap < 50 or at_cap > 75:
		failures.append("attribute points at cap = %d, expected ~62 (old ladder gave 57)" % at_cap)
	var free_hp: float = PlayerResource.HEALTH_PER_LEVEL * 125.0
	if free_hp < 80.0 or free_hp > 110.0:
		failures.append("free HP at cap = %.0f, expected ~95 (old ladder gave 95)" % free_hp)

	# --- Gear gated above the old cap is now reachable ----------------------
	if PlayerResource.COMBAT_LEVEL_CAP < 50:
		failures.append("cap %d still strands required_level 50 gear" % PlayerResource.COMBAT_LEVEL_CAP)

	if failures.is_empty():
		print("VERIFY_PASS combat_level cap=%d at_cap_points=%d free_hp=%.0f"
			% [PlayerResource.COMBAT_LEVEL_CAP, at_cap, free_hp])
		quit(0)
	else:
		for f: String in failures:
			print("VERIFY_FAIL ", f)
		quit(1)
