extends SceneTree
## Verify Desert / Fire Forge / Sewers: warpers, walkability, NO attackable NPCs.
##   godot --headless --path . -s tools/verify_stub_biomes.gd


func _initialize() -> void:
	var checks := [
		{"path": "res://source/common/gameplay/maps/maps/desert/desert.tscn", "entrance": 25, "portal": 125, "min_props": 40},
		{"path": "res://source/common/gameplay/maps/maps/fire_forge/fire_forge.tscn", "entrance": 26, "portal": 126, "min_props": 20},
		{"path": "res://source/common/gameplay/maps/maps/sewers/sewers.tscn", "entrance": 28, "portal": 128, "min_props": 20},
	]
	for c in checks:
		var packed: PackedScene = load(c["path"])
		assert(packed != null, "missing %s" % c["path"])
		var map: Node = packed.instantiate()
		assert(map.get("replicated_props_container") != null)

		var ground := map.get_node("Tiles/Ground") as TileMapLayer
		var walls := map.get_node("Tiles/Walls") as TileMapLayer
		var props := map.get_node("Tiles/Props") as TileMapLayer
		assert(ground != null and walls != null and props != null)
		assert(ground.get_used_cells().size() > 200, "too few ground cells %s" % c["path"])
		assert(walls.get_used_cells().size() > 40, "too few wall cells %s" % c["path"])
		assert(props.get_used_cells().size() >= int(c["min_props"]), "too few props %s" % c["path"])

		var entrance := map.get_node("Entrance")
		var portal := map.get_node("Portal")
		assert(int(entrance.get("warper_id")) == int(c["entrance"]))
		assert(int(portal.get("warper_id")) == int(c["portal"]))
		assert(int(portal.get("target_id")) == int(c["entrance"]))

		# Spawn / portal tiles must be clear of walls.
		var ent_cell := Vector2i(int(entrance.position.x / 16.0), int(entrance.position.y / 16.0))
		var por_cell := Vector2i(int(portal.position.x / 16.0), int(portal.position.y / 16.0))
		assert(ground.get_cell_source_id(ent_cell) >= 0, "entrance not on ground %s" % c["path"])
		assert(ground.get_cell_source_id(por_cell) >= 0, "portal not on ground %s" % c["path"])
		assert(walls.get_cell_source_id(ent_cell) < 0, "entrance blocked by wall %s" % c["path"])
		assert(walls.get_cell_source_id(por_cell) < 0, "portal blocked by wall %s" % c["path"])

		# No attackable NPCs in ReplicatedPropsContainer.
		var container := map.get_node("ReplicatedPropsContainer")
		assert(container.get_child_count() == 0, "hostiles still present in %s" % c["path"])

		# BFS connectivity entrance -> portal on ground tiles (not walls).
		var walk: Dictionary = {}
		for cell in ground.get_used_cells():
			if walls.get_cell_source_id(cell) < 0:
				walk[cell] = true
		assert(walk.has(ent_cell) and walk.has(por_cell), "spawn cells not walkable %s" % c["path"])
		var seen: Dictionary = {}
		var q: Array = [ent_cell]
		seen[ent_cell] = true
		var qi := 0
		while qi < q.size():
			var cur: Vector2i = q[qi]
			qi += 1
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = cur + d
				if walk.has(n) and not seen.has(n):
					seen[n] = true
					q.append(n)
		assert(seen.has(por_cell), "portal unreachable from entrance %s" % c["path"])

		var scene_props := map.get_node("SceneProps")
		var ambient := 0
		for child in scene_props.get_children():
			if String(child.name).begins_with("Stag") or String(child.name).begins_with("Boar") \
				or String(child.name).begins_with("Badger") or String(child.name).begins_with("Wolf") \
				or String(child.name).contains("Torch") or String(child.name).contains("Candle") \
				or String(child.name).contains("Spike") or String(child.name).contains("Light"):
				ambient += 1

		print(
			"OK ", c["path"].get_file(),
			" ground=", ground.get_used_cells().size(),
			" walls=", walls.get_used_cells().size(),
			" props=", props.get_used_cells().size(),
			" ambient=", ambient,
			" reachable=", seen.size()
		)
		map.free()
	print("STUB_BIOMES_VERIFY_PASS")
	quit(0)
