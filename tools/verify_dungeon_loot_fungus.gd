extends SceneTree
## Headless gate for dungeon charges / solo scaling / Fungus Domain / key item.
## Run: godot --headless --path . -s tools/verify_dungeon_loot_fungus.gd


func _init() -> void:
	var fails: PackedStringArray = PackedStringArray()

	# --- Dungeon Key item ---
	var key: Resource = load("res://source/common/gameplay/items/consumables/dungeon_key.tres")
	if key == null or not (key is DungeonKeyItem):
		fails.append("dungeon_key.tres missing or wrong class")
	elif (key as DungeonKeyItem).item_icon == null:
		fails.append("dungeon_key icon missing")

	# --- Charge helpers ---
	var pr := PlayerResource.new()
	if DungeonService.charges_remaining(pr) != DungeonService.DAILY_FREE_CHARGES:
		fails.append("fresh character should have %d charges" % DungeonService.DAILY_FREE_CHARGES)
	for i: int in DungeonService.DAILY_FREE_CHARGES:
		if not DungeonService.consume_charge(pr):
			fails.append("consume_charge failed on free pool step %d" % i)
	if DungeonService.charges_remaining(pr) != 0:
		fails.append("free pool should be empty after 3 consumes")
	if DungeonService.consume_charge(pr):
		fails.append("consume_charge should fail when empty")
	var left: int = DungeonService.add_bonus_charge(pr, 2)
	if left != 2:
		fails.append("add_bonus_charge expected 2 left, got %d" % left)
	if not DungeonService.consume_charge(pr):
		fails.append("should consume bonus charge")
	if DungeonService.charges_remaining(pr) != 1:
		fails.append("expected 1 bonus left")

	# --- Solo scaling math ---
	if DungeonService._scale_amount(10, 1.5) != 15:
		fails.append("1.5x amount scale broken")
	if DungeonService._scale_amount(1, 1.5) != 2 and DungeonService._scale_amount(1, 1.5) != 1:
		# maxi(1, round(1.5)) = 2
		fails.append("solo min amount scale unexpected: %d" % DungeonService._scale_amount(1, 1.5))
	var chance: float = minf(1.0, 0.22 * DungeonService.SOLO_CHANCE_MULT)
	if not is_equal_approx(chance, 0.44):
		fails.append("solo chance 22%% -> expected 44%%, got %s" % chance)

	# --- Reward tables ---
	for path: String in [
		"res://source/common/gameplay/dungeon/dungeon_reward_v1.tres",
		"res://source/common/gameplay/dungeon/dungeon_reward_hard.tres",
		"res://source/common/gameplay/dungeon/fungus_reward_normal.tres",
		"res://source/common/gameplay/dungeon/fungus_reward_hard.tres",
	]:
		var rew: DungeonReward = load(path) as DungeonReward
		if rew == null:
			fails.append("missing reward %s" % path)
			continue
		if rew.gold_min < 3000:
			fails.append("%s gold_min too low (%d)" % [path, rew.gold_min])
		if rew.loot.is_empty():
			fails.append("%s has empty loot" % path)
		if rew.rolls_min < 3 or rew.rolls_max < 4:
			fails.append("%s should draw 3–4 loot rolls (got %d–%d)" % [path, rew.rolls_min, rew.rolls_max])

	var dark: DungeonResource = load(
		"res://source/common/gameplay/maps/instance/instance_collection/dungeons/dungeon.tres"
	) as DungeonResource
	var fungus: DungeonResource = load(
		"res://source/common/gameplay/maps/instance/instance_collection/dungeons/fungus_dungeon.tres"
	) as DungeonResource
	if dark == null or dark.reward == null or dark.hard_reward == null:
		fails.append("Dark Cave dungeon resource incomplete")
	elif dark.normal_health_mult < 10.0 or dark.normal_damage_mult < 6.0:
		fails.append("Dark Cave trash multipliers too low for Runite/Fire kits")
	elif dark.party_boss_health(1) < 4999.0 or dark.party_boss_health(2) < 9999.0 \
			or dark.party_boss_health(3) < 17499.0 or dark.party_boss_health(4) < 24999.0:
		fails.append("Dark Cave boss HP should be 5k/10k/17.5k/25k by party size")
	if fungus == null or fungus.reward == null or fungus.hard_reward == null:
		fails.append("Fungus Domain dungeon resource incomplete")
	elif fungus.normal_health_mult < 3.0 or fungus.normal_damage_mult < 5.0:
		fails.append("Fungus Domain trash multipliers too low vs Dark Cave")
	elif fungus.party_boss_health(1) < 6499.0 or fungus.party_boss_health(4) < 31999.0:
		fails.append("Fungus Domain boss HP should scale above Dark Cave (6.5k solo / 32k four)")
	elif fungus.boss_slam_damage < 150.0 or fungus.boss_slam_damage > 250.0:
		fails.append("Fungus Domain slam should be a dodgeable chunk, not a one-shot")
	if dark != null:
		if dark.hard_health_mult < dark.normal_health_mult * 2.0 \
				or dark.hard_damage_mult < dark.normal_damage_mult * 2.0:
			fails.append("Dark Cave Hard trash should be ~2× Normal")
		if dark.hard_boss_health_mult < 2.0:
			fails.append("Dark Cave Hard boss HP multiplier too low")
	if fungus != null:
		if fungus.hard_health_mult < fungus.normal_health_mult * 2.0 \
				or fungus.hard_damage_mult < fungus.normal_damage_mult * 2.0:
			fails.append("Fungus Domain Hard trash should be ~2× Normal")
		if fungus.hard_boss_health_mult < 2.0:
			fails.append("Fungus Domain Hard boss HP multiplier too low")
	var svc: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/dungeon/dungeon_service.gd"
	)
	if svc.find("belongs to a different station") >= 0:
		fails.append("Hard rooms still reject joiners from another keeper/instance")
	if svc.find("func _lookup_room_code") < 0 or svc.find("pad_zeros") < 0:
		fails.append("join-by-code must pad short numeric codes")
	if svc.find("wrong_dungeon") < 0:
		fails.append("join-by-code must match dungeon type, not world instance")
	var mage: EnemyTypeResource = load(
		"res://source/common/gameplay/characters/npc/types/skeleton_mage.tres"
	) as EnemyTypeResource
	if mage == null:
		fails.append("skeleton_mage.tres missing")
	elif mage.slam_damage > 20.0:
		fails.append("Dark Cave mage slam still one-shots (%s)" % mage.slam_damage)
	if fungus != null and fungus.display_name != "Fungus Domain":
		fails.append("Fungus Domain display_name wrong")

	# --- Fungus map: final_room + boss spawn ---
	var fungus_map: PackedScene = load("res://source/common/gameplay/maps/maps/fungus_cave/fungus_dungeon.tscn")
	if fungus_map == null:
		fails.append("fungus_dungeon.tscn failed to load")
	else:
		var root: Node = fungus_map.instantiate()
		var final_room: Node = root.get_node_or_null("FinalRoom")
		if final_room == null:
			fails.append("FinalRoom missing")
		elif not bool(final_room.get("final_room")):
			fails.append("FinalRoom.final_room not true")
		else:
			var heart: Node = final_room.get_node_or_null("FungalHeart")
			if heart == null or heart.get("enemy_type") == null:
				fails.append("FinalRoom missing FungalHeart spawn")
		var room1: Node = root.get_node_or_null("Room1")
		if room1 == null or room1.get_child_count() < 2:
			fails.append("Room1 needs authored spawns")
		root.free()

	# --- Keepers ---
	var dk: NPCResource = load("res://source/common/gameplay/characters/npc/npcs/dungeon_keeper.tres") as NPCResource
	var fk: NPCResource = load("res://source/common/gameplay/characters/npc/npcs/fungal_keeper.tres") as NPCResource
	if dk == null or fk == null:
		fails.append("keeper NPC resources missing")
	else:
		var dk_text: String = dk.greeting + " ".join(PackedStringArray())
		if "Solo" not in dk.greeting and "solo" not in dk.greeting and "alone" not in dk.greeting:
			fails.append("DungeonKeeper greeting should advertise solo incentive")
		var has_dungeon_inter: bool = false
		for inter: NPCInteraction in fk.interactions:
			if inter is DungeonInteraction and (inter as DungeonInteraction).dungeon != null:
				has_dungeon_inter = true
		if not has_dungeon_inter:
			fails.append("FungalKeeper missing DungeonInteraction")

	# --- Boss key drops (world / farm bosses; story keys are quest turn-in) ---
	var bosses_with_key: int = _count_boss_keys_recursive("res://source/common/gameplay/characters/npc/types")
	if bosses_with_key < 12:
		fails.append("expected >=12 bosses with dungeon_key drop, got %d" % bosses_with_key)

	var story_quests: Array[Dictionary] = [
		{"path": "res://source/common/gameplay/quests/resources/goblin_woodland/the_goblin_chief.tres", "min": 1},
		{"path": "res://source/common/gameplay/quests/resources/bandit_hideout/the_bandit_captain.tres", "min": 1},
		{"path": "res://source/common/gameplay/quests/resources/fungus_cave/the_fungal_heart.tres", "min": 1},
		{"path": "res://source/common/gameplay/quests/resources/hollow_seep/break_the_cage.tres", "min": 1},
		{"path": "res://source/common/gameplay/quests/resources/hollow_seep/cut_the_heart.tres", "min": 1},
		{"path": "res://source/common/gameplay/quests/resources/hollow_seep/the_sovereign_below.tres", "min": 2},
		{"path": "res://source/common/gameplay/quests/resources/hollow_seep/leave_the_crown.tres", "min": 2},
		{"path": "res://source/common/gameplay/quests/resources/hollow_seep/the_fuel_lock.tres", "min": 2},
		{"path": "res://source/common/gameplay/quests/resources/hollow_seep/the_thing_it_was_built_to_run.tres", "min": 2},
	]
	for entry: Dictionary in story_quests:
		var quest: QuestResource = load(str(entry["path"])) as QuestResource
		if quest == null:
			fails.append("missing story quest %s" % entry["path"])
			continue
		var keys: int = 0
		for reward: QuestReward in quest.reward_items:
			if reward != null and reward.item != null and str(reward.item.item_name) == "Dungeon Key":
				keys += reward.amount
		if keys < int(entry["min"]):
			fails.append("%s should grant >=%d dungeon keys on turn-in, got %d" % [
				quest.quest_name, int(entry["min"]), keys
			])

	for path: String in [
		"res://source/common/gameplay/characters/npc/types/goblins/goblin_chief.tres",
		"res://source/common/gameplay/characters/npc/types/bandit_captain.tres",
		"res://source/common/gameplay/characters/npc/types/fungus/fungal_heart.tres",
		"res://source/common/gameplay/characters/npc/types/bosses/cistern_sovereign.tres",
		"res://source/common/gameplay/characters/npc/types/bosses/sand_king.tres",
		"res://source/common/gameplay/characters/npc/types/bosses/cinderborn.tres",
		"res://source/common/gameplay/characters/npc/types/mecha_stone_golem.tres",
	]:
		var et: EnemyTypeResource = load(path) as EnemyTypeResource
		if et == null:
			fails.append("missing quest boss %s" % path)
			continue
		for drop: LootDrop in et.loot:
			if drop != null and drop.item != null and str(drop.item.item_name) == "Dungeon Key":
				fails.append("%s quest boss still drops dungeon keys" % et.display_name)

	if fails.is_empty():
		print("VERIFY_PASS dungeon_loot_fungus")
		quit(0)
	else:
		for f: String in fails:
			push_error("VERIFY_FAIL: " + f)
			print("VERIFY_FAIL: ", f)
		quit(1)


func _count_boss_keys_recursive(path: String) -> int:
	var count: int = 0
	var dir := DirAccess.open(path)
	if dir == null:
		return 0
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full: String = path.path_join(name)
		if dir.current_is_dir():
			count += _count_boss_keys_recursive(full)
		elif name.ends_with(".tres"):
			var res: Resource = load(full)
			if res is EnemyTypeResource and (res as EnemyTypeResource).is_boss:
				var has_key: bool = false
				for drop: LootDrop in (res as EnemyTypeResource).loot:
					if drop != null and drop.item != null and str(drop.item.item_name) == "Dungeon Key":
						has_key = true
				if has_key:
					count += 1
		name = dir.get_next()
	return count
