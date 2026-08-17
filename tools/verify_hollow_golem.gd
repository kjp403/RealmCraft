extends SceneTree
## Headless gate for Hollow Mecha Golem (safe without full game autoload graph).


func _init() -> void:
	var fails: PackedStringArray = []

	# Scene structure + NodePath exports (the real client sync bug class).
	var ps: PackedScene = load("res://source/common/gameplay/maps/maps/the_hollow/the_hollow.tscn")
	if ps == null:
		print("FAIL load hollow")
		quit(1)
		return
	var hollow: Node = ps.instantiate()
	var rpc: Variant = hollow.get("replicated_props_container")
	print("pre_add container=", rpc)
	if rpc == null:
		fails.append("FAIL pre_add replicated_props_container null (missing node_paths?)")
	var golem: Node = hollow.get_node_or_null("ReplicatedPropsContainer/MechaGolem")
	print("golem=", golem, " pos=", golem.position if golem else null)
	if golem != null:
		fails.append("FAIL MechaGolem still on shared Hollow (story fight is via Hall Keeper)")

	root.add_child(hollow)
	rpc = hollow.get("replicated_props_container")
	print("post_add container=", rpc, " name=", rpc.name if rpc else null)
	if rpc == null:
		fails.append("FAIL post_add container null")
	var cont: Node = hollow.get_node_or_null("ReplicatedPropsContainer")
	if cont == null:
		fails.append("FAIL post_add ReplicatedPropsContainer missing")
	else:
		print("OK hollow container present, children=", cont.get_child_count())

	var ground: TileMapLayer = hollow.get_node("Tiles/Ground") as TileMapLayer
	var bad: Dictionary = {
		Vector2i(11, 15): 1, Vector2i(12, 15): 1, Vector2i(13, 15): 1,
		Vector2i(14, 15): 1, Vector2i(13, 14): 1,
	}
	var bad_count: int = 0
	for cell: Vector2i in ground.get_used_cells():
		if bad.has(ground.get_cell_atlas_coords(cell)):
			bad_count += 1
	print("bad_black_tiles=", bad_count, " ground_cells=", ground.get_used_cells().size())
	if bad_count != 0:
		fails.append("FAIL black tiles")

	# GIF-backed sprite frames + enemy type resource (independent of HostileNPC compile).
	var skin: SpriteFrames = load("res://source/common/gameplay/characters/sprite_frames/mecha_stone_golem.tres") as SpriteFrames
	var etype: Resource = load("res://source/common/gameplay/characters/npc/types/mecha_stone_golem.tres")
	print("skin=", skin, " etype=", etype)
	if skin == null:
		fails.append("FAIL skin resource")
	else:
		for a: String in ["idle", "walk", "run", "attack", "special", "death"]:
			var ok: bool = skin.has_animation(a) and skin.get_frame_count(a) > 0
			print("anim ", a, " ok=", ok, " frames=", skin.get_frame_count(a) if skin.has_animation(a) else -1)
			if not ok:
				fails.append("FAIL anim " + a)
			else:
				var tex: Texture2D = skin.get_frame_texture(a, 0)
				if tex == null:
					fails.append("FAIL texture " + a)
	if etype == null:
		fails.append("FAIL enemy type resource")
	else:
		print("etype.skin=", etype.get("skin"), " visual_scale=", etype.get("visual_scale"), " is_boss=", etype.get("is_boss"))
		if etype.get("skin") == null:
			fails.append("FAIL etype.skin null")
		if float(etype.get("visual_scale")) < 1.0:
			fails.append("FAIL visual_scale too small")

	var laser: Resource = load("res://source/common/gameplay/combat/vfx/mecha_laser.tres")
	print("laser=", laser)
	if laser == null:
		fails.append("FAIL laser vfx")

	var cave: Node = load("res://source/common/gameplay/maps/maps/fungus_cave/fungus_cave.tscn").instantiate()
	root.add_child(cave)
	print("fungus_container=", cave.get("replicated_props_container"))
	if cave.get("replicated_props_container") == null:
		fails.append("FAIL fungus baseline")

	hollow.free()
	cave.free()
	if fails.is_empty():
		print("VERIFY_PASS")
		quit(0)
	else:
		for f: String in fails:
			print(f)
		print("VERIFY_FAIL")
		quit(1)
