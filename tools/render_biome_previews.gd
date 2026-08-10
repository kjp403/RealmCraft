extends SceneTree
## Render Desert / Fire Forge / Sewers for review.
## Overviews show the whole map; close-ups run at 2x so 16px art appears at a
## comparable on-screen scale to the 32px reference screenshots.
##   godot --path . --mode=client -s tools/render_biome_previews.gd

const OUT_DIR := "/opt/cursor/artifacts/screenshots"

const MAPS := {
	"desert": "res://source/common/gameplay/maps/maps/desert/desert.tscn",
	"fire_forge": "res://source/common/gameplay/maps/maps/fire_forge/fire_forge.tscn",
	"sewers": "res://source/common/gameplay/maps/maps/sewers/sewers.tscn",
}


func _initialize() -> void:
	call_deferred(&"_go")


func _go() -> void:
	root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	await _shot("desert", "biome-desert-overview", Vector2(832, 608), 0.42, Vector2i(1100, 820))
	await _shot("desert", "biome-desert-basin", Vector2(832, 800), 2.0, Vector2i(1024, 576))
	await _shot("desert", "biome-desert-mesa", Vector2(832, 512), 2.0, Vector2i(1024, 576))

	await _shot("fire_forge", "biome-forge-overview", Vector2(896, 672), 0.42, Vector2i(1100, 820))
	await _shot("fire_forge", "biome-forge-foundry", Vector2(400, 384), 2.0, Vector2i(1024, 576))
	await _shot("fire_forge", "biome-forge-hall", Vector2(896, 672), 2.0, Vector2i(1024, 576))

	await _shot("sewers", "biome-sewers-overview", Vector2(896, 672), 0.42, Vector2i(1100, 820))
	await _shot("sewers", "biome-sewers-cistern", Vector2(384, 800), 2.0, Vector2i(1024, 576))
	await _shot("sewers", "biome-sewers-junction", Vector2(896, 704), 2.0, Vector2i(1024, 576))

	print("BIOME_PREVIEW_PASS")
	quit(0)


func _shot(map_key: String, name: String, cam_pos: Vector2, zoom: float, size: Vector2i) -> void:
	var packed: PackedScene = load(MAPS[map_key])
	var sv := SubViewport.new()
	sv.size = size
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	sv.world_2d = World2D.new()
	root.add_child(sv)
	var map: Node2D = packed.instantiate() as Node2D
	sv.add_child(map)
	var cam := Camera2D.new()
	cam.position = cam_pos
	cam.zoom = Vector2(zoom, zoom)
	map.add_child(cam)
	cam.make_current()
	for _i in 14:
		await process_frame
	var out := "%s/%s.png" % [OUT_DIR, name]
	sv.get_texture().get_image().save_png(out)
	print("SAVED ", out)
	sv.queue_free()
	await process_frame
