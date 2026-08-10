extends SceneTree
## Smoke-check Desert / Fire Forge / Sewers maps after fill.
##   godot --headless --path . -s tools/verify_stub_biomes.gd

func _initialize() -> void:
	var checks := [
		{
			"path": "res://source/common/gameplay/maps/maps/desert/desert.tscn",
			"entrance": 25,
			"portal": 125,
			"min_mobs": 3,
		},
		{
			"path": "res://source/common/gameplay/maps/maps/fire_forge/fire_forge.tscn",
			"entrance": 26,
			"portal": 126,
			"min_mobs": 3,
		},
		{
			"path": "res://source/common/gameplay/maps/maps/sewers/sewers.tscn",
			"entrance": 28,
			"portal": 128,
			"min_mobs": 3,
		},
	]
	for c in checks:
		var packed: PackedScene = load(c["path"])
		assert(packed != null, "missing %s" % c["path"])
		var map: Node = packed.instantiate()
		assert(map.get("replicated_props_container") != null)
		var ground := map.get_node("Tiles/Ground") as TileMapLayer
		var walls := map.get_node("Tiles/Walls") as TileMapLayer
		assert(ground != null and walls != null)
		assert(ground.get_used_cells().size() > 100, "too few ground cells %s" % c["path"])
		assert(walls.get_used_cells().size() > 20, "too few wall cells %s" % c["path"])
		var entrance := map.get_node("Entrance")
		var portal := map.get_node("Portal")
		assert(int(entrance.get("warper_id")) == int(c["entrance"]))
		assert(int(portal.get("warper_id")) == int(c["portal"]))
		assert(int(portal.get("target_id")) == int(c["entrance"]))
		var container := map.get_node("ReplicatedPropsContainer")
		var mobs := 0
		for child in container.get_children():
			if child is Node:
				mobs += 1
		assert(mobs >= int(c["min_mobs"]), "expected mobs in %s" % c["path"])
		# No stub hint labels
		assert(map.get_node_or_null("Hint") == null, "stub Hint still present %s" % c["path"])
		print(
			"OK ",
			c["path"].get_file(),
			" ground=",
			ground.get_used_cells().size(),
			" walls=",
			walls.get_used_cells().size(),
			" mobs=",
			mobs
		)
		map.free()
	print("STUB_BIOMES_VERIFY_PASS")
	quit(0)
