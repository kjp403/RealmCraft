extends SceneTree
## Headless checks for monster OOC regen delay, Guild Hall death recall,
## NPC visual scales, and metal pickaxe/axe tooling.
## Run: godot --headless --path . -s tools/verify_regen_respawn_tools.gd
## Expect: VERIFY_PASS

func _init() -> void:
	var failures: PackedStringArray = PackedStringArray()

	var npc_src: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/characters/npc/hostile_npc.gd"
	)
	if npc_src.find("OUT_OF_COMBAT_REGEN_DELAY_MS: int = 10000") < 0:
		failures.append("missing 10s OUT_OF_COMBAT_REGEN_DELAY_MS")
	if npc_src.find("_can_out_of_combat_regen") < 0:
		failures.append("missing _can_out_of_combat_regen gate")
	# Regen is walk-home-only: no passive idle trickle, and the arrival top-off is
	# gated on the same out-of-combat window (a kited boss can't reset mid-fight).
	if npc_src.find("IDLE_REGEN_RATE") >= 0:
		failures.append("idle regen should be gone — recovery routes through RETURNING")
	if npc_src.find("_process_idle_recovery") < 0:
		failures.append("missing _process_idle_recovery (wounded idle mob walks home)")
	if npc_src.find("< hmax and _can_out_of_combat_regen()") < 0:
		failures.append("spawn-point top-off is not gated on the out-of-combat window")
	# Committed bosses (leashes = false) must reset too — the old carve-out that
	# returned early from regen for them is gone.
	if npc_src.find("if _is_committed():\n\t\treturn\n\tif not _can_out_of_combat_regen()") >= 0:
		failures.append("committed mobs still exempt from out-of-combat recovery")

	var player_src: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/characters/player/player.gd"
	)
	if player_src.find("recall_player(peer_id)") < 0:
		failures.append("die() should recall_player to Guild Hall")
	if player_src.find("send_player_death_return") >= 0:
		failures.append("die() should not use death_return_instance path anymore")

	var scales_down: PackedStringArray = PackedStringArray([
		"trpg_intellect_devourer", "trpg_carrion_crawler",
		"trpg_sewer_gorgon", "trpg_acid_ooze",
	])
	for slug: String in scales_down:
		var t: String = FileAccess.get_file_as_string(
			"res://source/common/gameplay/characters/npc/types/trpg/%s.tres" % slug
		)
		if t.find("visual_scale = 0.55") < 0:
			failures.append("%s visual_scale != 0.55" % slug)

	for slug: String in ["trpg_sewer_skeleton", "trpg_slime"]:
		var t: String = FileAccess.get_file_as_string(
			"res://source/common/gameplay/characters/npc/types/trpg/%s.tres" % slug
		)
		if t.find("visual_scale = 1.4") < 0:
			failures.append("%s visual_scale != 1.4" % slug)

	var tool_src: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/items/weapons/tool_item.gd"
	)
	if tool_src.find("bonus_yield_chance") < 0:
		failures.append("ToolItem missing bonus_yield_chance")

	var expect_bonus: Dictionary = {
		"bronze": 0.03, "iron": 0.05, "steel": 0.07,
		"mithril": 0.1, "adamant": 0.12, "runite": 0.15,
	}
	var expect_skill: Dictionary = {
		"bronze": 1, "iron": 5, "steel": 10,
		"mithril": 20, "adamant": 35, "runite": 50,
	}
	for metal: String in expect_bonus.keys():
		for kind: String in ["pickaxe", "axe"]:
			var path: String = (
				"res://source/common/gameplay/items/weapons/tools/%s_%s.tres" % [kind, metal]
			)
			if not FileAccess.file_exists(path):
				failures.append("missing %s" % path)
				continue
			var body: String = FileAccess.get_file_as_string(path)
			if body.find("bonus_yield_chance = %s" % str(expect_bonus[metal])) < 0 \
					and body.find("bonus_yield_chance = %.2f" % float(expect_bonus[metal])) < 0 \
					and body.find("bonus_yield_chance = %.1f" % float(expect_bonus[metal])) < 0:
				# 0.1 may serialize as 0.1
				if float(expect_bonus[metal]) == 0.1 and body.find("bonus_yield_chance = 0.1") >= 0:
					pass
				else:
					failures.append("%s_%s bad bonus_yield" % [kind, metal])
			if body.find("required_skill_level = %d" % int(expect_skill[metal])) < 0:
				failures.append("%s_%s bad skill level" % [kind, metal])
			var item: Resource = load(path)
			if item == null or not (item is ToolItem):
				failures.append("%s_%s failed to load as ToolItem" % [kind, metal])

	var anvil: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/crafting/resources/anvil.tres"
	)
	for rid: String in [
		"R_tool_pick_br", "R_tool_axe_br", "R_tool_pick_ru", "R_tool_axe_ru"
	]:
		if anvil.find(rid) < 0:
			failures.append("anvil missing %s" % rid)

	if ContentRegistryHub.load_by_slug(&"items", &"pickaxe_bronze") == null:
		failures.append("pickaxe_bronze not in items index")
	if ContentRegistryHub.load_by_slug(&"items", &"axe_runite") == null:
		failures.append("axe_runite not in items index")

	if failures.is_empty():
		print("VERIFY_PASS regen_respawn_tools")
		quit(0)
	else:
		print("VERIFY_FAIL")
		for line: String in failures:
			print("  - ", line)
		quit(1)
