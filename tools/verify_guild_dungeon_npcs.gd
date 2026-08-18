extends SceneTree
## Headless checks for the Durael relocation, the Guild Hall Fungus Domain keeper,
## and the trimmed dungeon-lobby info panel.
## Run: godot --headless --path . -s tools/verify_guild_dungeon_npcs.gd
## Expect: VERIFY_PASS

func _init() -> void:
	var failures: PackedStringArray = PackedStringArray()

	# --- Durael moved to (2453, 1800) in the forest -------------------------
	var forest: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/maps/maps/forest/forest.tscn"
	)
	var durael_at: int = forest.find("[node name=\"Durael\"")
	if durael_at < 0:
		failures.append("Durael node missing from forest.tscn")
	elif forest.substr(durael_at, 220).find("position = Vector2(2453, 1800)") < 0:
		failures.append("Durael is not at (2453, 1800)")

	# --- Guild Hall: DungeonKeeper + a Fungus Domain keeper beside him ------
	var hall: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/maps/maps/guild_house/inside_map.tscn"
	)
	if hall.find("npcs/fungal_keeper.tres") < 0:
		failures.append("Guild Hall does not reference fungal_keeper.tres")
	var keeper_at: int = hall.find("[node name=\"FungalKeeper\"")
	if keeper_at < 0:
		failures.append("FungalKeeper node missing from the Guild Hall")
	elif hall.substr(keeper_at, 220).find("position = Vector2(-201, -320)") < 0:
		failures.append("FungalKeeper is not at (-201, -320)")
	if hall.find("[node name=\"DungeonMaster\"") < 0:
		failures.append("DungeonMaster (Dark Cave) went missing from the Guild Hall")
	if hall.find("npcs/brimstone_keeper.tres") < 0:
		failures.append("Guild Hall does not reference brimstone_keeper.tres")
	if hall.find("[node name=\"BrimstoneKeeper\"") < 0:
		failures.append("BrimstoneKeeper node missing from the Guild Hall")

	# The keeper must actually open the Fungus Domain, not just stand there.
	var keeper_res: NPCResource = load(
		"res://source/common/gameplay/characters/npc/npcs/fungal_keeper.tres"
	) as NPCResource
	if keeper_res == null:
		failures.append("fungal_keeper.tres failed to load as an NPCResource")
	else:
		var opens_fungus: bool = false
		for inter: NPCInteraction in keeper_res.interactions:
			if inter is DungeonInteraction:
				var dres: DungeonResource = (inter as DungeonInteraction).dungeon
				if dres != null and dres.instance_name == &"fungus_dungeon":
					opens_fungus = true
		if not opens_fungus:
			failures.append("Fungal Keeper has no DungeonInteraction for fungus_dungeon")

	# --- Dungeon lobby: left panel is a blurb + Solo Bonus, not a loot table -
	var menu_src: String = FileAccess.get_file_as_string(
		"res://source/client/ui/menus/dungeon/dungeon_menu.gd"
	)
	if menu_src.find("\"Solo Bonus:\"") < 0:
		failures.append("dungeon menu no longer labels the Solo Bonus")
	if menu_src.find("\"Reward: %s\"") >= 0 or menu_src.find("\"Hard: %s\"") >= 0:
		failures.append("dungeon menu still recites the Normal/Hard drop tables")
	if menu_src.find("_open_lobby_chat") < 0:
		failures.append("dungeon menu has no share-code-to-chat path")
	var hud_src: String = FileAccess.get_file_as_string(
		"res://source/client/ui/hud/hud.gd"
	)
	if hud_src.find("_menu_allows_chat") < 0 or hud_src.find("CHAT_ABOVE_MENU_Z") < 0:
		failures.append("HUD must keep chat usable over the dungeon lobby")

	if failures.is_empty():
		print("VERIFY_PASS guild_dungeon_npcs")
		quit(0)
	else:
		print("VERIFY_FAIL")
		for line: String in failures:
			print("  - ", line)
		quit(1)
