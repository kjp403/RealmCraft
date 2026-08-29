extends SceneTree
## Zoomed-out overview of Starfall Grove, for eyeballing the layout, the stand
## placement and the night lighting without launching the client.
##
##   godot --path . -s tools/render_starfall_grove.gd -- --outdir=C:/tmp/shots

const MAP := "res://source/common/gameplay/maps/maps/starfall_grove/starfall_grove.tscn"
const CELLS := Vector2i(160, 112)
const VIEW := Vector2i(1600, 1150)

var _outdir: String = "user://starfall_grove"
## Both overridable so the same framing can shoot a REFERENCE map — eyeballing
## the grove against Goblin Woodland is the only honest quality check.
var _map: String = MAP
var _cells: Vector2i = CELLS
var _origin: Vector2i = Vector2i.ZERO
var _name: String = "starfall_grove"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--outdir="):
			_outdir = arg.substr("--outdir=".length())
		elif arg.begins_with("--map="):
			_map = arg.substr("--map=".length())
		elif arg.begins_with("--name="):
			_name = arg.substr("--name=".length())
		elif arg.begins_with("--rect="):
			var p: PackedStringArray = arg.substr("--rect=".length()).split(",")
			_origin = Vector2i(int(p[0]), int(p[1]))
			_cells = Vector2i(int(p[2]), int(p[3]))
	# Deferred so the autoloads exist before a map script compiles against them.
	call_deferred(&"_go")


func _go() -> void:
	root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var dir := ProjectSettings.globalize_path(_outdir) if _outdir.begins_with("user://") else _outdir
	DirAccess.make_dir_recursive_absolute(dir)

	var sub := SubViewport.new()
	sub.size = VIEW
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	sub.world_2d = World2D.new()
	root.add_child(sub)

	var map: Node2D = (load(_map) as PackedScene).instantiate() as Node2D
	sub.add_child(map)
	# map.gd pushes this to the window clear colour at runtime; a SubViewport
	# gets its own grey unless we paint it, which makes the unpainted deep void
	# (canopy shadow, in game) look like a hole in the map.
	var sky := ColorRect.new()
	sky.color = map.map_background_color
	sky.size = Vector2(_origin + _cells) * 16.0
	sky.z_index = -100
	map.add_child(sky)

	var world := Vector2(_cells) * 16.0
	var zoom: float = minf(float(VIEW.x) / world.x, float(VIEW.y) / world.y) * 0.97
	var cam := Camera2D.new()
	cam.position = Vector2(_origin) * 16.0 + world * 0.5
	cam.zoom = Vector2(zoom, zoom)
	cam.make_current()
	map.add_child(cam)

	for _i in 30:
		await process_frame

	var out := "%s/%s.png" % [dir, _name]
	sub.get_texture().get_image().save_png(out)
	print("SAVED ", out)
	quit(0)
