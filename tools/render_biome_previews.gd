extends SceneTree
## Render Desert / Fire Forge / Sewers to PNGs for review.
##   godot --path . --mode=client -s tools/render_biome_previews.gd


func _initialize() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var peer := OfflineMultiplayerPeer.new()
	root.multiplayer.multiplayer_peer = peer
	DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/screenshots")

	for entry in [
		["desert", "res://source/common/gameplay/maps/maps/desert/desert.tscn", Vector2(512, 384)],
		["fire_forge", "res://source/common/gameplay/maps/maps/fire_forge/fire_forge.tscn", Vector2(512, 384)],
		["sewers", "res://source/common/gameplay/maps/maps/sewers/sewers.tscn", Vector2(512, 384)],
	]:
		await _render(entry[0], entry[1], entry[2])

	print("BIOME_PREVIEW_PASS")
	quit(0)


func _render(name: String, path: String, cam_pos: Vector2) -> void:
	var packed: PackedScene = load(path)
	var sv := SubViewport.new()
	sv.size = Vector2i(960, 720)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	sv.transparent_bg = false
	sv.world_2d = World2D.new()
	root.add_child(sv)

	var map: Node2D = packed.instantiate() as Node2D
	sv.add_child(map)

	var cam := Camera2D.new()
	cam.position = cam_pos
	cam.make_current()
	map.add_child(cam)

	for _i: int in 10:
		await process_frame

	var image: Image = sv.get_texture().get_image()
	var out := "/opt/cursor/artifacts/screenshots/biome-%s-preview.png" % name
	image.save_png(out)
	print("SAVED ", out, " size=", image.get_size())
	sv.queue_free()
	await process_frame
