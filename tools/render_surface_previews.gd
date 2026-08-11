extends SceneTree
## Preview shots of the Fire Forge levels and the three surface maps, for
## reviewing floor material and world scale.
##
## Two passes per level, because they answer different questions:
##   * an overview, which shows whether the paved roads read as a network;
##   * two gameplay-scale crops, which is the only scale at which you can tell
##     whether the floor under a running player has anything to track.
##
##   godot --path . -s tools/render_surface_previews.gd
##   godot --path . -s tools/render_surface_previews.gd -- --outdir=C:/tmp/shots

const MAPS := "res://source/common/gameplay/maps/maps/"

## `size` is in cells of the *emitted* map, which for the two sub-levels is the
## authored grid multiplied by `build_biome_levels.gd`'s SCALE. Detail cameras
## are in world pixels on that same emitted grid.
const LEVELS: Array[Dictionary] = [
	{
		"name": "bellows-gallery", "path": MAPS + "fire_forge/bellows_gallery.tscn",
		"size": Vector2i(520, 390),
		"details": [Vector2(4168, 5448), Vector2(2408, 2408)],  # arrival hall, west hall
	},
	{
		"name": "fire-forge", "path": MAPS + "fire_forge/fire_forge.tscn",
		"size": Vector2i(224, 168),
		"details": [Vector2(1800, 2312), Vector2(1800, 1352)],  # entrance, centre bay
	},
	{
		"name": "cinder-deeps", "path": MAPS + "fire_forge/cinder_deeps.tscn",
		"size": Vector2i(560, 430),
		"details": [Vector2(4488, 6088), Vector2(6984, 3208)],  # landing, east ledge
	},
	{
		"name": "desert", "path": MAPS + "desert/desert.tscn",
		"size": Vector2i(208, 152),
		"details": [Vector2(1672, 2056), Vector2(1672, 1032)],  # oasis camp, north basin
	},
	{
		"name": "sewers", "path": MAPS + "sewers/sewers.tscn",
		"size": Vector2i(224, 168),
		"details": [Vector2(1800, 2312), Vector2(1800, 1416)],  # arrival, central cistern
	},
]

const OVERVIEW := Vector2i(1400, 1100)
## 960x720 at zoom 1 is roughly what the client shows, which is the point.
const DETAIL := Vector2i(960, 720)

var _outdir: String = "user://forge_preview"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--outdir="):
			_outdir = arg.substr("--outdir=".length())
	call_deferred(&"_go")


func _go() -> void:
	root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var dir := ProjectSettings.globalize_path(_outdir) if _outdir.begins_with("user://") else _outdir
	DirAccess.make_dir_recursive_absolute(dir)
	for level in LEVELS:
		await _overview(level, dir)
		var i := 0
		for pos: Vector2 in level["details"]:
			i += 1
			await _detail(level, pos, i, dir)
	print("FORGE_PREVIEW_PASS dir=", dir)
	quit(0)


func _overview(level: Dictionary, dir: String) -> void:
	var world := Vector2(level["size"] as Vector2i) * 16.0
	var zoom: float = minf(float(OVERVIEW.x) / world.x, float(OVERVIEW.y) / world.y) * 0.96
	await _shot(level["path"], OVERVIEW, world * 0.5, zoom,
		"%s/%s-overview.png" % [dir, level["name"]])


func _detail(level: Dictionary, pos: Vector2, index: int, dir: String) -> void:
	await _shot(level["path"], DETAIL, pos, 2.0,
		"%s/%s-floor-%d.png" % [dir, level["name"], index])


func _shot(path: String, size: Vector2i, cam_pos: Vector2, zoom: float, out: String) -> void:
	var packed: PackedScene = load(path)
	var sub := SubViewport.new()
	sub.size = size
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	sub.world_2d = World2D.new()
	root.add_child(sub)

	var map: Node2D = packed.instantiate() as Node2D
	sub.add_child(map)
	var cam := Camera2D.new()
	cam.position = cam_pos
	cam.zoom = Vector2(zoom, zoom)
	cam.make_current()
	map.add_child(cam)

	for _i in 20:
		await process_frame

	sub.get_texture().get_image().save_png(out)
	print("SAVED ", out)
	sub.queue_free()
	await process_frame
