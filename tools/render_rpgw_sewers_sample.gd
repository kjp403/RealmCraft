extends SceneTree
## Paint a small sample from rpgw_sewers_tileset.tres and render it, to prove the
## curated atlas regions are real paintable art rather than caption text or empty
## gutters from the pack's documentation sheet.
##
## Also demonstrates the 4-layer split the overhaul targets: ground + slime on
## Layer 0, decals on 1, the 3-tile wall body on 2, and its top rim on 3.
##
##   godot --path . -s tools/render_rpgw_sewers_sample.gd -- --outdir=C:/tmp

const TS := "res://source/common/gameplay/maps/tilesets/rpgw_sewers_tileset.tres"

const W := 30
const H := 20

# Verified banks (see build_rpgw_sewers_tileset.gd for how they were derived).
const FLOOR: Array[Vector2i] = [
	Vector2i(26, 2), Vector2i(27, 2), Vector2i(28, 2),
	Vector2i(26, 3), Vector2i(27, 3), Vector2i(28, 3),
	Vector2i(26, 4), Vector2i(27, 4), Vector2i(28, 4),
]
const SLIME_SOLID := Vector2i(2, 47)  # author's most-painted slime fill
# Straight 3-tile-tall wall run from wall-1-water: rim, body, base.
const WALL_RIM := Vector2i(3, 9)
const WALL_BODY := Vector2i(3, 10)
const WALL_BASE := Vector2i(3, 11)

var _outdir: String = "user://rpgw_sewers"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--outdir="):
			_outdir = arg.substr("--outdir=".length())
	call_deferred(&"_go")


func _go() -> void:
	root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var dir := ProjectSettings.globalize_path(_outdir) if _outdir.begins_with("user://") else _outdir
	DirAccess.make_dir_recursive_absolute(dir)

	var ts: TileSet = load(TS)
	if ts == null:
		printerr("FAIL could not load ", TS)
		quit(1)
		return

	var sub := SubViewport.new()
	sub.size = Vector2i(W * 32, H * 32)
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	sub.world_2d = World2D.new()
	root.add_child(sub)

	var ground := _layer(sub, ts, -1)
	var decals := _layer(sub, ts, 0)
	var walls := _layer(sub, ts, 1)
	var over := _layer(sub, ts, 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	for y in H:
		for x in W:
			ground.set_cell(Vector2i(x, y), 0, FLOOR[rng.randi() % FLOOR.size()])

	# A slime channel down the middle, and the animated sewage tile beside it so
	# both liquid sources are exercised.
	for y in H:
		for x in range(13, 17):
			ground.set_cell(Vector2i(x, y), 0, SLIME_SOLID)
		ground.set_cell(Vector2i(17, y), 2, Vector2i.ZERO)

	# A 3-tile-tall wall run along the top, split across the layers it belongs to.
	for x in range(2, 12):
		over.set_cell(Vector2i(x, 3), 1, WALL_RIM)
		walls.set_cell(Vector2i(x, 4), 1, WALL_BODY)
		walls.set_cell(Vector2i(x, 5), 1, WALL_BASE)

	# A few props, to confirm the props atlas imported as usable cells.
	# One cell from each curated props band, so a bad region shows up here.
	var picks: Array[Vector2i] = [
		Vector2i(36, 18), Vector2i(28, 24), Vector2i(3, 30), Vector2i(12, 21), Vector2i(40, 42),
	]
	var spots: Array[Vector2i] = [
		Vector2i(4, 10), Vector2i(7, 13), Vector2i(10, 16), Vector2i(22, 8), Vector2i(25, 14),
	]
	for i in picks.size():
		decals.set_cell(spots[i], 3, picks[i])

	var cam := Camera2D.new()
	cam.position = Vector2(W * 32, H * 32) * 0.5
	sub.add_child(cam)
	cam.make_current()

	for _i in 12:
		await process_frame

	var out := "%s/rpgw_sewers_sample.png" % dir
	sub.get_texture().get_image().save_png(out)
	print("SAVED ", out)
	print("RPGW_SEWERS_SAMPLE_OK")
	quit(0)


func _layer(parent: Node, ts: TileSet, z: int) -> TileMapLayer:
	var l := TileMapLayer.new()
	l.tile_set = ts
	l.z_index = z
	l.collision_enabled = false
	parent.add_child(l)
	return l
