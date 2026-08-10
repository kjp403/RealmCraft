extends SceneTree
## Verify woodland wildlife spread.
## Run: godot --headless --path . -s tools/verify_woodland_wildlife.gd

func _initialize() -> void:
	var map_path := "res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn"
	var packed: PackedScene = load(map_path) as PackedScene
	assert(packed != null)
	var map: Node = packed.instantiate()
	var container: Node = map.get_node("ReplicatedPropsContainer")
	var walls: TileMapLayer = map.get_node("Walls") as TileMapLayer
	var ground: TileMapLayer = map.get_node("Ground") as TileMapLayer

	var counts := {"goblin": 0, "wolf": 0, "rat": 0, "other": 0}
	var on_wall := 0
	var missing_data := 0
	for child in container.get_children():
		if not child.has_method("get") and not ("enemy_data" in child):
			pass
		var data = child.get("enemy_data")
		if data == null:
			missing_data += 1
			continue
		var slug: String = String(data.enemy_type)
		if slug.begins_with("goblin"):
			counts["goblin"] += 1
		elif slug == "wolf":
			counts["wolf"] += 1
		elif slug == "woodland_rat":
			counts["rat"] += 1
		else:
			counts["other"] += 1
		var cell: Vector2i = ground.local_to_map(child.position)
		if walls.get_cell_source_id(cell) >= 0:
			on_wall += 1
			print("ON_WALL ", child.name, " ", child.position)

	var rat: Resource = load("res://source/common/gameplay/characters/npc/types/woodland_rat.tres")
	var wolf: Resource = load("res://source/common/gameplay/characters/npc/types/wolf.tres")
	assert(rat != null and float(rat.get("max_health")) < 50.0)
	assert(float(wolf.get("wander_radius")) > 0.0)
	assert(float(rat.get("wander_radius")) > 0.0)
	# Combat skins must be set — missing skin falls back to knight.
	var wolf_skin: Resource = wolf.get("skin")
	var rat_skin: Resource = rat.get("skin")
	assert(wolf_skin != null, "Wild Wolf missing skin (would render as knight)")
	assert(rat_skin != null, "Woodland Rat missing skin")
	assert(String(wolf_skin.resource_path).ends_with("wolf.tres"), "wolf skin path=%s" % wolf_skin.resource_path)
	assert(String(rat_skin.resource_path).ends_with("woodland_rat.tres"), "rat skin path=%s" % rat_skin.resource_path)
	assert(not String(rat_skin.resource_path).ends_with("rat_base.tres"), "rat must not use bipedal rat_base")


	print("counts=", counts)
	print("on_wall=", on_wall, " missing_data=", missing_data)
	print("children=", container.get_child_count())
	if on_wall > 0 or missing_data > 0 or counts["wolf"] < 6 or counts["rat"] < 10:
		print("VERIFY_FAIL")
		quit(1)
		return
	print("VERIFY_PASS")
	quit(0)
