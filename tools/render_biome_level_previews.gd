extends SceneTree
## Zoomed-out overviews of the six biome sub-levels, for eyeballing layout and
## palette without launching the client into each one.
##
## Output goes to `user://biome_levels/` unless `--outdir=<path>` is passed, so
## it works the same on a workstation and on the CI box.
##
##   godot --path . -s tools/render_biome_level_previews.gd
##   godot --path . -s tools/render_biome_level_previews.gd -- --outdir=C:/tmp/shots

const MAPS := "res://source/common/gameplay/maps/maps/"

const SHOTS: Array[Dictionary] = [
	{"name": "sunspire-terraces", "path": MAPS + "desert/sunspire_terraces.tscn", "size": Vector2i(100, 74)},
	{"name": "sunken-tombs", "path": MAPS + "desert/sunken_tombs.tscn", "size": Vector2i(108, 84)},
	{"name": "gutterworks", "path": MAPS + "sewers/gutterworks.tscn", "size": Vector2i(104, 78)},
	{"name": "drowned-cistern", "path": MAPS + "sewers/drowned_cistern.tscn", "size": Vector2i(112, 86)},
	{"name": "bellows-gallery", "path": MAPS + "fire_forge/bellows_gallery.tscn", "size": Vector2i(104, 78)},
	{"name": "cinder-deeps", "path": MAPS + "fire_forge/cinder_deeps.tscn", "size": Vector2i(112, 86)},
]

const VIEW := Vector2i(1400, 1100)

var _outdir: String = "user://biome_levels"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--outdir="):
			_outdir = arg.substr("--outdir=".length())
	call_deferred(&"_go")


func _go() -> void:
	root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var dir := ProjectSettings.globalize_path(_outdir) if _outdir.begins_with("user://") else _outdir
	DirAccess.make_dir_recursive_absolute(dir)
	for shot in SHOTS:
		await _shot(shot, dir)
	print("BIOME_LEVEL_PREVIEW_PASS dir=", dir)
	quit(0)


func _shot(shot: Dictionary, dir: String) -> void:
	var packed: PackedScene = load(shot["path"])
	var sub := SubViewport.new()
	sub.size = VIEW
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	sub.world_2d = World2D.new()
	root.add_child(sub)

	var map: Node2D = packed.instantiate() as Node2D
	sub.add_child(map)

	# Frame the whole map: fit its tile extent into the viewport with a margin.
	var cells: Vector2i = shot["size"]
	var world := Vector2(cells) * 16.0
	var zoom: float = minf(float(VIEW.x) / world.x, float(VIEW.y) / world.y) * 0.96
	var cam := Camera2D.new()
	cam.position = world * 0.5
	cam.zoom = Vector2(zoom, zoom)
	cam.make_current()
	map.add_child(cam)

	for _i in 20:
		await process_frame

	var out := "%s/%s.png" % [dir, shot["name"]]
	sub.get_texture().get_image().save_png(out)
	print("SAVED ", out)
	sub.queue_free()
	await process_frame
