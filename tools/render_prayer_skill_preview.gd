extends Node
## Screenshot the Skills dock panel on the Prayer skill, to confirm it lists the
## prayers rather than the bone catalogue.
##   godot --path . --mode=client res://tools/render_prayer_skill_preview.tscn

const PANEL_SCENE: String = "res://source/client/ui/compact_menus/compact_skills_host.tscn"
const OUT_DIR: String = "res://previews"
const W: int = 960
const H: int = 540

var _sv: SubViewport
var _panel: Control
var _out_abs: String


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	_out_abs = ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(_out_abs)

	_sv = SubViewport.new()
	_sv.size = Vector2i(W, H)
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_sv.transparent_bg = false
	_sv.disable_3d = true
	get_tree().root.add_child(_sv)

	var ground := ColorRect.new()
	ground.size = Vector2(W, H)
	ground.color = Color(0.30, 0.22, 0.16)
	_sv.add_child(ground)

	var hud := Control.new()
	hud.size = Vector2(W, H)
	_sv.add_child(hud)

	_panel = (load(PANEL_SCENE) as PackedScene).instantiate() as Control
	hud.add_child(_panel)

	await get_tree().process_frame
	await get_tree().process_frame
	_panel.show()
	ClientState.skill_levels["prayer"] = 43
	_panel._skills["prayer"] = {
		"display_name": "Prayer",
		"level": 43,
		"xp": 2047,
		"xp_to_next": 57079,
		"total_xp": 550000,
	}
	_panel._show_detail("prayer")

	for _i: int in 10:
		await get_tree().process_frame

	var image: Image = _sv.get_texture().get_image()
	image.resize(W * 2, H * 2, Image.INTERPOLATE_NEAREST)
	var dest: String = _out_abs.path_join("prayer-skill.png")
	image.save_png(dest)
	print("SAVED ", dest)
	get_tree().quit(0)
