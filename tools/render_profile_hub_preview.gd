extends Node
## Screenshot the Profile panel with its new Character / Skins / Guild handoff
## buttons, at the shipping 960x540 client size.
##   godot --path . --mode=client res://tools/render_profile_hub_preview.tscn

const MENU_SCENE: String = "res://source/client/ui/menus/player_profile/player_profile_menu.tscn"
const OUT_DIR: String = "res://previews"
const W: int = 960
const H: int = 540

var _sv: SubViewport
var _menu: Control
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
	ground.color = Color(0.24, 0.30, 0.22)
	_sv.add_child(ground)

	_menu = (load(MENU_SCENE) as PackedScene).instantiate() as Control
	_sv.add_child(_menu)

	await get_tree().process_frame
	await get_tree().process_frame
	_menu.show()
	_menu.apply_profile({
		"self": true,
		"id": 1,
		"name": "Thicc",
		"guild_name": "Sporebane",
		"level": 74,
		"description": "Battlemage. Mostly here for the ore.",
		"titles": ["Emberborn", "Deep Delver"],
		"trophies": ["Emberborn"],
		"equipped_titles": ["Emberborn"],
	})

	for _i: int in 10:
		await get_tree().process_frame

	var image: Image = _sv.get_texture().get_image()
	image.resize(W * 2, H * 2, Image.INTERPOLATE_NEAREST)
	var dest: String = _out_abs.path_join("profile-hub.png")
	image.save_png(dest)
	print("SAVED ", dest)
	get_tree().quit(0)
