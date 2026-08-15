extends SceneTree
## Smoke-load Hollow Seep NPCs and quests.

func _initialize() -> void:
	var npcs := PackedStringArray([
		"res://source/common/gameplay/characters/npc/npcs/hall_keeper.tres",
		"res://source/common/gameplay/characters/npc/npcs/charter_clerk.tres",
		"res://source/common/gameplay/characters/npc/npcs/scout_calder.tres",
		"res://source/common/gameplay/characters/npc/npcs/lira_voss.tres",
		"res://source/common/gameplay/characters/npc/npcs/lira_voss_freed.tres",
		"res://source/common/gameplay/characters/npc/npcs/cave_scribe_wren.tres",
		"res://source/common/gameplay/characters/npc/npcs/rook_hale.tres",
		"res://source/common/gameplay/characters/npc/npcs/sewers/sluice_warden_obry.tres",
		"res://source/common/gameplay/characters/npc/npcs/bone_carver.tres",
		"res://source/common/gameplay/characters/npc/npcs/fire_forge/forgemaster_helka.tres",
	])
	var failed := 0
	for path in npcs:
		var npc: NPCResource = load(path) as NPCResource
		if npc == null:
			push_error("FAIL npc %s" % path)
			failed += 1
			continue
		print("npc ", npc.npc_name, " key=", npc.giver_key())
	var qdir := "res://source/common/gameplay/quests/resources/hollow_seep"
	var quest_count := 0
	for fname: String in ResourceLoader.list_directory(qdir):
		if not fname.ends_with(".tres"):
			continue
		var quest: QuestResource = load(qdir.path_join(fname)) as QuestResource
		if quest == null:
			push_error("FAIL quest %s" % fname)
			failed += 1
		else:
			quest_count += 1
			var qid: int = int(quest.get_meta(&"id", 0))
			if qid <= 0:
				push_error("FAIL quest id %s" % fname)
				failed += 1
	var seal_id: int = ContentRegistryHub.id_from_slug(&"quests", &"the_charter_seal")
	var cap_id: int = ContentRegistryHub.id_from_slug(&"items", &"pale_sporecap")
	print("quests_loaded=", quest_count, " charter_id=", seal_id, " sporecap_id=", cap_id)
	var weapon_climaxes := PackedStringArray([
		"res://source/common/gameplay/quests/resources/goblin_woodland/the_goblin_chief.tres",
		qdir.path_join("cut_the_heart.tres"),
		qdir.path_join("break_the_cage.tres"),
		qdir.path_join("the_sovereign_below.tres"),
		qdir.path_join("bone_and_shard.tres"),
		qdir.path_join("leave_the_crown.tres"),
		qdir.path_join("the_fuel_lock.tres"),
		qdir.path_join("the_thing_it_was_built_to_run.tres"),
	])
	for path in weapon_climaxes:
		var quest: QuestResource = load(path) as QuestResource
		if quest == null or quest.reward_style_weapons.size() < 5:
			push_error("FAIL unique weapon kit %s" % path)
			failed += 1
			continue
		print("weapon ", quest.quest_name, " styles=", quest.reward_style_weapons.size(), " items=", quest.reward_items.size())
	var hammer: QuestResource = load(qdir.path_join("proof_of_the_hammer.tres")) as QuestResource
	if hammer == null or not hammer.reward_style_weapons.is_empty() or hammer.objectives.size() != 3:
		push_error("FAIL proof_of_the_hammer should be bronze armour crafts, no unique weapon grant")
		failed += 1
	else:
		print("hammer crafts=", hammer.objectives.size(), " styles=", hammer.reward_style_weapons.size())
	var hole: QuestResource = load(qdir.path_join("the_hole_in_the_wall.tres")) as QuestResource
	var chief: QuestResource = load("res://source/common/gameplay/quests/resources/goblin_woodland/the_goblin_chief.tres") as QuestResource
	if hole == null or chief == null or hole.requires_quests.is_empty() or String(hole.requires_quests[0].get_meta(&"slug", &"")) != "the_goblin_chief":
		push_error("FAIL the_hole_in_the_wall must require the_goblin_chief")
		failed += 1
	if failed > 0 or quest_count != 30 or seal_id <= 0 or cap_id <= 0:
		print("HOLLOW_SEEP_VERIFY_FAIL failed=", failed)
		quit(1)
		return
	print("HOLLOW_SEEP_VERIFY_PASS")
	quit(0)
