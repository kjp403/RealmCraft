extends Node
## Screenshot the three-dots overlay at the shipping 960x540 client size, with a
## stand-in minimap block in the top-right so overlap is obvious.
##   godot --path . --mode=client res://tools/render_menu_overlay_preview.tscn

const OVERLAY_SCRIPT: String = "res://source/client/ui/hud/menu_overlay.gd"
const OUT_DIR: String = "res://previews"
const W: int = 960
const H: int = 540


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var out_abs: String = ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_abs)

	var sv := SubViewport.new()
	sv.size = Vector2i(W, H)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	sv.disable_3d = true
	get_tree().root.add_child(sv)

	var ground := ColorRect.new()
	ground.size = Vector2(W, H)
	ground.color = Color(0.30, 0.22, 0.16)
	sv.add_child(ground)

	var hud := Control.new()
	hud.size = Vector2(W, H)
	sv.add_child(hud)

	# Minimap stand-in: same corner and rough size as the real one.
	var minimap := ColorRect.new()
	minimap.size = Vector2(150, 150)
	minimap.position = Vector2(W - 162, 12)
	minimap.color = Color(0.10, 0.12, 0.16, 0.9)
	hud.add_child(minimap)
	var label := Label.new()
	label.text = "MINIMAP"
	label.position = Vector2(W - 150, 70)
	label.add_theme_color_override(&"font_color", Color(0.6, 0.7, 0.85))
	hud.add_child(label)

	var overlay := Control.new()
	overlay.set_script(load(OVERLAY_SCRIPT))
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.add_child(overlay)

	await get_tree().process_frame
	await get_tree().process_frame
	if overlay.has_method("open"):
		overlay.call("open")
	for _i: int in 20:
		await get_tree().process_frame

	var image: Image = sv.get_texture().get_image()
	image.resize(W * 2, H * 2, Image.INTERPOLATE_NEAREST)
	var dest: String = out_abs.path_join("menu-overlay.png")
	image.save_png(dest)
	print("SAVED ", dest)
	get_tree().quit(0)
