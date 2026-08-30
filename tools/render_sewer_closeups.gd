extends SceneTree
## Gameplay-zoom crops of the three sewer levels, for judging tile art and prop
## density at the scale a player actually sees. Overview shots render each tile
## at ~2px and cannot answer that question.
##
##   godot --path . -s tools/render_sewer_closeups.gd -- --outdir=C:/tmp/shots

const MAPS := "res://source/common/gameplay/maps/maps/sewers/"
const VIEW := Vector2i(1280, 800)
const ZOOM := 3.0

const SHOTS: Array[Dictionary] = [
	{"name": "cistern-mid", "path": MAPS + "drowned_cistern.tscn", "at": Vector2(4480, 3440)},
	{"name": "gutterworks-mid", "path": MAPS + "gutterworks.tscn", "at": Vector2(4160, 3120)},
	{"name": "sewers-mid", "path": MAPS + "sewers.tscn", "at": Vector2(1800, 1400)},
	{"name": "ossuary-mid", "path": MAPS + "ossuary.tscn", "at": Vector2(3840, 3040)},
]

var _outdir: String = "user://sewer_closeups"


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
	print("SEWER_CLOSEUP_PASS dir=", dir)
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

	var cam := Camera2D.new()
	cam.position = shot["at"]
	cam.zoom = Vector2(ZOOM, ZOOM)
	map.add_child(cam)
	cam.make_current()

	for _i in 20:
		await process_frame

	var out := "%s/%s.png" % [dir, shot["name"]]
	sub.get_texture().get_image().save_png(out)
	print("SAVED ", out)
	sub.queue_free()
	await process_frame
