extends SceneTree
## Headless checks for Fire and Flames (third dungeon).
## Run: godot --headless --path . -s tools/verify_hell_dungeon.gd
## Expect: VERIFY_PASS

func _init() -> void:
	var failures: PackedStringArray = PackedStringArray()

	var map: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/maps/maps/hell_dungeon/hell_dungeon.tscn"
	)
	if map.is_empty():
		failures.append("hell_dungeon.tscn missing — run tools/build_hell_dungeon.gd")
	else:
		if map.find("node_paths=PackedStringArray(\"replicated_props_container\")") < 0:
			failures.append("map root missing replicated_props_container node_paths")
		if map.find("id_to_node") < 0 or map.find("node_to_id") < 0:
			failures.append("ReplicatedPropsContainer missing baked door ids")
		if map.find("warper.tscn") < 0:
			failures.append("entry Warper missing")
		if map.find("lost_soul.tres") < 0:
			failures.append("Lost Soul exit NPC missing")
		if map.find("final_room = true") < 0:
			failures.append("FinalRoom not marked final_room")
		if map.find("hell_vault_queen.tres") < 0:
			failures.append("Vault Queen spawn missing")
		if map.find("hell_giant.tres") < 0:
			failures.append("Hell Giant mini-boss spawn missing")
		if map.find("wave = 2") < 0:
			failures.append("rooms need a third wave (wave = 2 markers)")
		var room_count := 0
		for name: String in ["Room1", "Room2", "Room3", "Room4", "Room5", "FinalRoom"]:
			if map.find("[node name=\"%s\"" % name) >= 0:
				room_count += 1
		if room_count < 6:
			failures.append("expected 5 combat rooms + FinalRoom, found %d" % room_count)

	var ts: TileSet = load("res://source/common/gameplay/maps/tilesets/hell_tileset.tres") as TileSet
	if ts == null:
		failures.append("hell_tileset.tres failed to load")
	elif ts.tile_size != Vector2i(32, 32):
		failures.append("hell tileset is not 32×32")
	else:
		var src := ts.get_source(0) as TileSetAtlasSource
		if src == null:
			failures.append("hell tileset missing atlas source 0")
		else:
			var void_td := src.get_tile_data(Vector2i(1, 1), 0)
			if void_td == null or void_td.get_collision_polygons_count(0) < 1:
				failures.append("well void tile (1,1) must collide — players were walking into the hole")
			var floor_td := src.get_tile_data(Vector2i(8, 8), 0)
			if floor_td != null and floor_td.get_collision_polygons_count(0) > 0:
				failures.append("floor fill (8,8) must not collide")
			var worn_block := src.get_tile_data(Vector2i(5, 8), 0)
			if worn_block != null and worn_block.get_collision_polygons_count(0) < 1:
				failures.append("oval rim (5,8) should stay blocking — do not reuse it as floor")

	var builder: String = FileAccess.get_file_as_string("res://tools/build_hell_dungeon.gd")
	if builder.find("const VOID_PIT") < 0 or builder.find("set_cell(cell, 0, VOID_PIT)") < 0:
		failures.append("dungeon builder must paint the well with VOID_PIT, not a floor fill")
	if builder.find("Vector2i(5, 8)") >= 0:
		failures.append("dungeon builder still uses blocking oval rim (5,8) as worn floor")
	if map.find("[node name=\"Camp4\"") < 0:
		failures.append("Room 4 is missing a campfire")
	var camp3_at: int = map.find("[node name=\"Camp3\"")
	if camp3_at >= 0:
		var camp3_chunk: String = map.substr(camp3_at, 180)
		if camp3_chunk.find("-2224") >= 0 or camp3_chunk.find("-2134") >= 0:
			failures.append("Camp3 still sits in the brimstone well")
	var r3_at: int = map.find("[node name=\"Room3\"")
	var r4_at: int = map.find("[node name=\"Room4\"")
	if r3_at >= 0 and r4_at > r3_at:
		var r3: String = map.substr(r3_at, r4_at - r3_at)
		var search_from := 0
		while true:
			var p: int = r3.find("position = Vector2(", search_from)
			if p < 0:
				break
			search_from = p + 19
			var endp: int = r3.find(")", search_from)
			if endp < 0:
				break
			var pair: PackedStringArray = r3.substr(search_from, endp - search_from).split(",")
			if pair.size() < 2:
				continue
			var mx: float = float(pair[0].strip_edges())
			var my: float = float(pair[1].strip_edges())
			if absf(mx - 336.0) < 0.1 and absf(my + 2224.0) < 0.1:
				continue
			if absf(mx) < 200.0 and absf(my) < 145.0:
				failures.append("Room3 spawn at (%s, %s) sits in the well" % [mx, my])
				break

	var dungeon: DungeonResource = load(
		"res://source/common/gameplay/maps/instance/instance_collection/dungeons/hell_dungeon.tres"
	) as DungeonResource
	if dungeon == null:
		failures.append("hell_dungeon.tres failed to load")
	else:
		if dungeon.instance_name != &"hell_dungeon":
			failures.append("instance_name must be hell_dungeon")
		if dungeon.recommended_level < 90:
			failures.append("recommended_level must sit at Necromancer gear (99), not Cave/Domain")
		if dungeon.normal_health_mult < 22.0:
			failures.append("normal_health_mult should crush Dark Cave (14)")
		if dungeon.hard_health_mult < 40.0:
			failures.append("hard_health_mult should crush Dark Cave (22)")
		if dungeon.boss_health_by_party.size() < 4:
			failures.append("boss_health_by_party needs 1–4 player entries")
		elif dungeon.boss_health_by_party[0] < 45000.0:
			failures.append("1-man Queen HP must outlast the Ossuary Necromancer (40000)")
		elif dungeon.boss_health_by_party[3] < 170000.0:
			failures.append("4-man Queen HP should still be a Necromancer-gear raid check")
		if dungeon.boss_slam_damage < 400.0:
			failures.append("boss_slam_damage should punish Wyrmguard, not tickle")
		if dungeon.reward == null or dungeon.hard_reward == null:
			failures.append("normal/hard DungeonReward missing")
		elif dungeon.hard_reward.gold_min < 18000:
			failures.append("hard gold_min should beat fungus/cave hard (10000)")
		elif dungeon.hard_reward.ornate_chest_count < 3:
			failures.append("hard ornate_chest_count should be 3")
		elif dungeon.reward.ornate_chest_count < 2:
			failures.append("normal ornate_chest_count should be 2 (Hard is 3)")
		else:
			var nloot := FileAccess.get_file_as_string(
				"res://source/common/gameplay/dungeon/hell_reward_normal.tres"
			)
			var hloot := FileAccess.get_file_as_string(
				"res://source/common/gameplay/dungeon/hell_reward_hard.tres"
			)
			if nloot.find("sword_sunsteel") >= 0 or hloot.find("sword_sunsteel") >= 0:
				failures.append("Vault rewards still drop Sunsteel — that is Cave-tier, not Necromancer")
			if nloot.find("bone.tres") < 0 or nloot.find("adamant_bar") < 0 or nloot.find("health_potion") < 0:
				failures.append("Normal Vault rewards need a common layer (bone / bars / potions)")
			if nloot.find("sword_wyrmguard") < 0 or nloot.find("wand_astral") < 0:
				failures.append("Normal Vault rewards must include Wyrmguard / Astral weapons")
			if hloot.find("sword_godsteel") < 0 or hloot.find("godsteel_chest") < 0:
				failures.append("Hard Vault rewards must drip Godsteel weapons and plate")

	var queen: EnemyTypeResource = load(
		"res://source/common/gameplay/characters/npc/types/hell/hell_vault_queen.tres"
	) as EnemyTypeResource
	if queen == null:
		failures.append("hell_vault_queen.tres failed to load")
	else:
		if not queen.is_boss:
			failures.append("Vault Queen must be is_boss")
		if queen.combat_level < 95:
			failures.append("Vault Queen combat_level must meet Necromancer (99)")
		if queen.armor < 140.0:
			failures.append("Vault Queen armor must check Wyrmguard, not Runite")
		if queen.slam_damage < 400.0:
			failures.append("Queen slam_damage must match dungeon slam (Wyrmguard-scale), not the 90 default")
		if queen.meteor_count < 6 or queen.meteor_damage < 200.0:
			failures.append("Queen meteor volley must be on and hit for real")
		if queen.sweep_arc_deg <= 0.0 or queen.sweep_damage < 200.0:
			failures.append("Queen cinder lash must be on and hit for real")
		if queen.chain_targets < 3 or queen.chain_damage < 180.0:
			failures.append("Queen chain must be on and hit for real")
		if queen.sear_wound_duration_s <= 0.0 or queen.sear_wound_damage < 200.0:
			failures.append("Queen sear must impact AND mark, not a heal-only no-op")
		if queen.add_enemy_slug != &"hell_imp" or queen.add_count < 6:
			failures.append("Queen enrage must summon Ash Imps")
		if queen.distance_to_attack < 50:
			failures.append("Queen melee reach must cover the 1.45× skull")
		if queen.loot.is_empty():
			failures.append("Vault Queen loot array is empty")
		if queen.skin == null:
			failures.append("Vault Queen has no skin")
		else:
			for anim: StringName in [&"idle", &"run", &"death"]:
				if not queen.skin.has_animation(anim):
					failures.append("Vault Queen skin missing %s" % anim)

	var burning: EnemyTypeResource = load(
		"res://source/common/gameplay/characters/npc/types/hell/hell_burning.tres"
	) as EnemyTypeResource
	if burning == null:
		failures.append("hell_burning.tres failed to load")
	else:
		var has_burst := false
		for behavior: MobBehavior in burning.behaviors:
			if behavior is DeathBurstBehavior:
				has_burst = true
		if not has_burst:
			failures.append("Cinder Damned must leave a fire pool (DeathBurstBehavior)")

	var bloated: EnemyTypeResource = load(
		"res://source/common/gameplay/characters/npc/types/hell/hell_bloated.tres"
	) as EnemyTypeResource
	if bloated == null:
		failures.append("hell_bloated.tres failed to load")
	else:
		var has_burst := false
		for behavior: MobBehavior in bloated.behaviors:
			if behavior is DeathBurstBehavior:
				has_burst = true
		if not has_burst:
			failures.append("Bloated Damned must leave a fire pool (DeathBurstBehavior)")

	var imp: EnemyTypeResource = load(
		"res://source/common/gameplay/characters/npc/types/hell/hell_imp.tres"
	) as EnemyTypeResource
	if imp == null:
		failures.append("hell_imp.tres failed to load")
	else:
		var has_lunge := false
		for behavior: MobBehavior in imp.behaviors:
			if behavior is LungeBehavior:
				has_lunge = true
		if not has_lunge:
			failures.append("Ash Imp must lunge so autos actually connect")

	var keeper: NPCResource = load(
		"res://source/common/gameplay/characters/npc/npcs/brimstone_keeper.tres"
	) as NPCResource
	if keeper == null:
		failures.append("brimstone_keeper.tres failed to load")
	else:
		var opens := false
		for inter: NPCInteraction in keeper.interactions:
			if inter is DungeonInteraction:
				var dres: DungeonResource = (inter as DungeonInteraction).dungeon
				if dres != null and dres.instance_name == &"hell_dungeon":
					opens = true
		if not opens:
			failures.append("Brimstone Keeper has no DungeonInteraction for hell_dungeon")

	var title_dungeon: DungeonResource = load(
		"res://source/common/gameplay/maps/instance/instance_collection/dungeons/hell_dungeon.tres"
	) as DungeonResource
	if title_dungeon == null:
		failures.append("hell_dungeon.tres failed to load (title check)")
	elif title_dungeon.display_name != "Fire and Flames" or title_dungeon.zone_title != "Fire and Flames":
		failures.append("hell dungeon title must be Fire and Flames")

	var hall: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/maps/maps/guild_house/inside_map.tscn"
	)
	if hall.find("npcs/brimstone_keeper.tres") < 0:
		failures.append("Guild Hall does not reference brimstone_keeper.tres")
	if hall.find("[node name=\"BrimstoneKeeper\"") < 0:
		failures.append("BrimstoneKeeper node missing from the Guild Hall")

	var lb: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/leaderboard/leaderboard_service.gd"
	)
	if lb.find('"dungeon:hell_dungeon"') < 0:
		failures.append("PUBLIC_BOARDS missing dungeon:hell_dungeon")
	var menu: String = FileAccess.get_file_as_string(
		"res://source/client/ui/menus/leaderboard/leaderboard_menu.gd"
	)
	if menu.find("dungeon:hell_dungeon") < 0 or menu.find("Fire and Flames") < 0:
		failures.append("leaderboard menu missing Fire and Flames board")
	var site: String = FileAccess.get_file_as_string("res://website/src/leaderboards.js")
	if site.find("dungeon:hell_dungeon") < 0 or site.find("Fire and Flames") < 0:
		failures.append("website leaderboards.js missing Fire and Flames board")

	if failures.is_empty():
		print("VERIFY_PASS hell_dungeon")
		quit(0)
	else:
		print("VERIFY_FAIL")
		for line: String in failures:
			print("  - ", line)
		quit(1)
