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
	if failed > 0 or quest_count != 30 or seal_id <= 0 or cap_id <= 0:
		print("HOLLOW_SEEP_VERIFY_FAIL failed=", failed)
		quit(1)
		return
	print("HOLLOW_SEEP_VERIFY_PASS")
	quit(0)
