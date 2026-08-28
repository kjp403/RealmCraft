extends Node
## Screenshot the Ossuran encounter so the rooms can be REVIEWED AS PICTURES
## rather than as assertions. The verifier can prove a pad exists at a
## coordinate; only a render shows whether the room reads.
##
##   godot --path . --mode=client res://tools/render_ossuran_preview.tscn
##
## Must run WINDOWED, not --headless: the dummy renderer draws no tilemaps and
## runs no shaders, so a headless capture is a blank image that looks like a
## broken map.
##
## Four frames, which together cover everything the fight changes:
##   forge    the room as you walk in, pads dormant
##   charged  both pads at full charge — the two shaders at their loudest
##   frozen   phase 3: ice layer up, frost overlay at freeze = 1
##   chamber  the summoning room the waves run in

const MAP: String = "res://source/common/gameplay/maps/maps/ossuran/ossuran_arena.tscn"
const OUT_DIR: String = "res://previews/ossuran"

## Framing per shot: [name, centre, viewport size].
const SHOTS: Array = [
	["forge", Vector2(384, 272), Vector2i(768, 544)],
	["charged", Vector2(384, 272), Vector2i(768, 544)],
	["frozen", Vector2(384, 272), Vector2i(768, 544)],
	["chamber", Vector2(1296, 272), Vector2i(544, 416)],
]


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for shot: Array in SHOTS:
		await _render(str(shot[0]), shot[1], shot[2])
	get_tree().quit(0)


func _render(shot: String, centre: Vector2, size: Vector2i) -> void:
	var sv := SubViewport.new()
	sv.size = size
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# NEAREST or the whole point of the pixel art is lost to bilinear smear.
	sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	sv.disable_3d = true
	sv.transparent_bg = false
	get_tree().root.add_child(sv)

	var map: Node = (load(MAP) as PackedScene).instantiate()
	sv.add_child(map)

	var cam := Camera2D.new()
	cam.position = centre
	sv.add_child(cam)
	cam.make_current()

	_stage(map, shot)

	# The pad shaders animate on TIME and the frost tween needs a beat; a dozen
	# frames lets everything settle instead of catching frame zero.
	for _i: int in 16:
		await get_tree().process_frame

	var out: String = ProjectSettings.globalize_path(OUT_DIR).path_join("%s.png" % shot)
	sv.get_texture().get_image().save_png(out)
	print("SAVED ", out)
	sv.queue_free()
	await get_tree().process_frame


## Put the map into the state this shot is meant to show.
func _stage(map: Node, shot: String) -> void:
	var encounter: Node = map.get_node_or_null(^"Encounter")
	var ice: CanvasItem = map.get_node_or_null(^"Tiles/Ice")
	var frost: CanvasItem = map.get_node_or_null(^"FrostOverlay")

	if shot == "charged" or shot == "frozen":
		for pad_name: String in ["EmberPad", "StormPad"]:
			var pad: Node = encounter.get_node_or_null(NodePath(pad_name))
			if pad == null:
				continue
			var fill: CanvasItem = pad.get_node_or_null(^"Fill")
			if fill == null:
				continue
			var mat: ShaderMaterial = fill.material as ShaderMaterial
			if mat != null:
				mat.set_shader_parameter(&"charge", 1.0)
				mat.set_shader_parameter(&"active", 1.0)
			fill.visible = true

	if shot == "frozen":
		if ice != null:
			ice.visible = true
			# The arena's own end-state tint, not white — a preview that stages
			# the freeze differently from _freeze_environment is a preview of a
			# room that does not exist.
			ice.modulate = OssuranArena.ICE_LAYER_TINT
		if frost != null:
			frost.visible = true
			var mat: ShaderMaterial = frost.material as ShaderMaterial
			if mat != null:
				mat.set_shader_parameter(&"freeze", 1.0)
