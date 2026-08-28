extends Node
## Screenshots the first-30-minutes intake flow: the arrow over the Charter Clerk,
## and the guided lesson cards the clerk hands out.
##
## Runs as a SCENE (not `-s`) and windowed — the coach and card scripts reference
## the ClientState autoload, and headless has no rasteriser:
##   godot --path . --mode=client res://tools/render_jail_flow.tscn

const JAIL: String = "res://source/common/gameplay/maps/maps/guild_house/jail_room.tscn"
const COACH: String = "res://source/client/ui/hud/onboarding_coach.gd"
const CARD: String = "res://source/client/ui/hud/tutorial_card.gd"
const OUT_DIR: String = "res://previews"
const W: int = 960
const H: int = 540
## Charter Clerk's position inside jail_room.tscn.
const CLERK: Vector2 = Vector2(328.8, 87.6)

var _sv: SubViewport
var _ui: CanvasLayer
var _coach: Control
var _out_abs: String


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	_out_abs = ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(_out_abs)
	# Maps and characters expect a peer to exist before _ready runs.
	get_tree().root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

	_sv = SubViewport.new()
	_sv.size = Vector2i(W, H)
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_sv.disable_3d = true
	get_tree().root.add_child(_sv)

	var map: Node = (load(JAIL) as PackedScene).instantiate()
	_sv.add_child(map)

	var cam := Camera2D.new()
	cam.position = CLERK + Vector2(-40, 10)
	cam.zoom = Vector2(3.2, 3.2)
	_sv.add_child(cam)
	cam.make_current()

	_ui = CanvasLayer.new()
	_sv.add_child(_ui)

	await _settle(30)
	_save(await _grab(), "jail-intake-arrow.png")

	# Wide shot: the whole cell, so the arrow's job (pick him out of the room) reads.
	cam.position = Vector2(176, 96)
	cam.zoom = Vector2(1.6, 1.6)
	await _settle(10)
	_save(await _grab(), "jail-intake-room.png")

	# The guided lessons.
	_coach = (load(COACH) as GDScript).new()
	_ui.add_child(_coach)
	await _settle(4)

	_coach.start_lesson(&"menus")
	await _settle(4)
	_save(await _grab(), "jail-lesson-prompt.png")

	ClientState.compact_panel_opened.emit(&"inventory")
	await _settle(4)
	_save(await _grab(), "jail-lesson-inventory.png")

	_dismiss_card()
	_coach.start_lesson(&"mastery")
	await _settle(4)
	_save(await _grab(), "jail-lesson-mastery.png")

	_dismiss_card()
	_coach.start_lesson(&"mastery_point")
	await _settle(4)
	_save(await _grab(), "jail-lesson-mastery-point.png")

	print("RENDER_JAIL_FLOW_DONE")
	get_tree().quit(0)


func _dismiss_card() -> void:
	for child: Node in _coach.get_children():
		if child.get_script() == load(CARD):
			child.queue_free()
	_coach._clear_prompt()


func _settle(frames: int) -> void:
	for i: int in frames:
		await get_tree().process_frame


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return _sv.get_texture().get_image()


func _save(image: Image, file_name: String) -> void:
	var dest: String = _out_abs.path_join(file_name)
	image.save_png(dest)
	print("SAVED ", dest, " size=", image.get_size())
