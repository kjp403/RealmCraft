extends SceneTree
## Headless gate for quest-NPC instance rooms.
##
##   godot --headless --path . -s tools/verify_quest_boss_instances.gd
##
## Checks: givers carry QuestBossInteraction, quest bodies are gone from shared
## maps, world pads remain, and the private arena scene is wired.

const NPCS: Array[Dictionary] = [
	{"path": "res://source/common/gameplay/characters/npc/npcs/woodland/warden_bren.tres", "enemy": "goblin_chief"},
	{"path": "res://source/common/gameplay/characters/npc/npcs/watch_sergeant.tres", "enemy": "bandit_captain"},
	{"path": "res://source/common/gameplay/characters/npc/npcs/rook_hale.tres", "enemy": "bandit_captain"},
	{"path": "res://source/common/gameplay/characters/npc/npcs/forager_maela.tres", "enemy": "fungal_heart"},
	{"path": "res://source/common/gameplay/characters/npc/npcs/lira_voss.tres", "enemy": "fungal_heart"},
	{"path": "res://source/common/gameplay/characters/npc/npcs/sewers/drowned_keeper_vess.tres", "enemy": "cistern_sovereign"},
	{"path": "res://source/common/gameplay/characters/npc/npcs/desert/tomb_delver_asha.tres", "enemy": "sand_king"},
	{"path": "res://source/common/gameplay/characters/npc/npcs/fire_forge/cinderwright_maro.tres", "enemy": "cinderborn"},
	{"path": "res://source/common/gameplay/characters/npc/npcs/hall_keeper.tres", "enemy": "mecha_stone_golem"},
]

const MAPS: Array[Dictionary] = [
	{
		"path": "res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn",
		"gone": [],
		"keep": ["GoblinChief"],
	},
	{
		"path": "res://source/common/gameplay/maps/maps/bandit_hideout/bandit_hideout.tscn",
		"gone": [],
		"keep": ["BanditCaptain"],
	},
	{
		"path": "res://source/common/gameplay/maps/maps/fungus_cave/fungus_cave.tscn",
		"gone": [],
		"keep": ["FungalHeart"],
	},
	{
		"path": "res://source/common/gameplay/maps/maps/sewers/sewers.tscn",
		"gone": [],
		"keep": ["BloatedSovereign"],
	},
	{
		"path": "res://source/common/gameplay/maps/maps/desert/desert.tscn",
		"gone": ["SandKing", "Necromancer"],
		"keep": ["UnboundSandKing"],
	},
	{
		"path": "res://source/common/gameplay/maps/maps/fire_forge/fire_forge.tscn",
		"gone": ["Cinderborn"],
		"keep": ["UnboundCinderborn"],
	},
	{
		"path": "res://source/common/gameplay/maps/maps/the_hollow/the_hollow.tscn",
		"gone": ["MechaGolem"],
		"keep": [],
	},
	{
		"path": "res://source/common/gameplay/maps/maps/forest/forest.tscn",
		"gone": ["BanditCaptain"],
		"keep": [],
	},
	{
		"path": "res://source/common/gameplay/maps/maps/sewers/ossuary.tscn",
		"gone": [],
		"keep": ["Necromancer"],
	},
]


func _init() -> void:
	var fails: PackedStringArray = []

	for cfg: Dictionary in NPCS:
		var path: String = str(cfg["path"])
		var text: String = FileAccess.get_file_as_string(path)
		if text.is_empty():
			fails.append("FAIL load NPC %s" % path)
			continue
		if "quest_boss_interaction.gd" not in text:
			fails.append("FAIL %s missing QuestBossInteraction" % path.get_file())
		var enemy: String = str(cfg["enemy"])
		if 'enemy_type = &"%s"' % enemy not in text:
			fails.append("FAIL %s enemy_type != %s" % [path.get_file(), enemy])
		else:
			print("OK   giver ", path.get_file(), " -> ", enemy)

	for cfg: Dictionary in MAPS:
		var path: String = str(cfg["path"])
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			fails.append("FAIL load map %s" % path)
			continue
		var map: Node = packed.instantiate()
		var container: Node = map.get_node_or_null("ReplicatedPropsContainer")
		if container == null:
			fails.append("FAIL %s has no ReplicatedPropsContainer" % path.get_file())
			map.free()
			continue
		for gone: String in cfg["gone"]:
			if container.get_node_or_null(gone) != null:
				fails.append("FAIL %s still has quest pad %s" % [path.get_file(), gone])
		for keep: String in cfg["keep"]:
			if container.get_node_or_null(keep) == null:
				fails.append("FAIL %s missing world pad %s" % [path.get_file(), keep])
			else:
				print("OK   ", path.get_file(), " world pad ", keep)
		# Sync dictionaries must not name a removed quest body.
		var id_to_node: Variant = container.get("id_to_node")
		var node_to_id: Variant = container.get("node_to_id")
		if id_to_node is Dictionary and node_to_id is Dictionary:
			for gone: String in cfg["gone"]:
				for v: Variant in (id_to_node as Dictionary).values():
					if str(v).contains(gone):
						fails.append("FAIL %s id_to_node still names %s" % [path.get_file(), gone])
				for k: Variant in (node_to_id as Dictionary).keys():
					if str(k).contains(gone):
						fails.append("FAIL %s node_to_id still names %s" % [path.get_file(), gone])
		map.free()

	var arena_res: Resource = load(
		"res://source/common/gameplay/maps/instance/instance_collection/quest_boss_arena.tres"
	)
	if arena_res == null:
		fails.append("FAIL quest_boss_arena instance resource")
	else:
		print("OK   quest_boss_arena instance_name=", arena_res.get("instance_name"))

	var arena_ps: PackedScene = load(
		"res://source/common/gameplay/maps/maps/quest_boss/quest_boss_arena.tscn"
	)
	if arena_ps == null:
		fails.append("FAIL load quest_boss_arena.tscn")
	else:
		var arena: Node = arena_ps.instantiate()
		if arena.get_node_or_null("ReplicatedPropsContainer") == null:
			fails.append("FAIL arena missing ReplicatedPropsContainer")
		if arena.get_node_or_null("Arena/BossSpawn") == null:
			fails.append("FAIL arena missing BossSpawn")
		if arena.get_node_or_null("QuestBossExit") == null:
			fails.append("FAIL arena missing QuestBossExit")
		else:
			print("OK   quest_boss_arena scene")
		arena.free()

	for script_path: String in [
		"res://source/common/gameplay/quest_boss/quest_boss_service.gd",
		"res://source/common/gameplay/characters/npc/interactions/quest_boss_interaction.gd",
		"res://source/server/world/components/data_request_handlers/npc.quest_boss.gd",
		"res://source/server/world/components/data_request_handlers/quest_boss.leave.gd",
	]:
		if load(script_path) == null:
			fails.append("FAIL load %s" % script_path)

	var stub: String = FileAccess.get_file_as_string("res://tools/build_stub_biomes.gd")
	if '"name": "BloatedSovereign"' in stub or '"name": "SandKing"' in stub or '"name": "Cinderborn"' in stub or '"name": "Necromancer"' in stub:
		fails.append("FAIL build_stub_biomes still appends quest pads or the desert Necromancer")
	else:
		print("OK   stub biomes no longer append quest pads")

	if fails.is_empty():
		print("VERIFY_PASS")
		quit(0)
	else:
		for f: String in fails:
			print(f)
		print("VERIFY_FAIL")
		quit(1)
