extends Node
## Screenshot of the REAL compact settings panel on its Toggles page, which is
## where the HUD lock switch and the "Reset HUD layout" button live.
##
## Runs as a SCENE, not a `-s` tool, and windowed:
##   godot --path . --mode=client res://tools/render_settings_toggles.tscn
##
## The panel is instanced from its own compact_settings_host.tscn rather than
## rebuilt here, so what is shot is the shipping widget - including the rows this
## tool knows nothing about.

const PANEL: String = "res://source/client/ui/compact_menus/compact_settings_host.tscn"
const OUT: String = "res://previews/settings-hud-toggles.png"
## The project stretches canvas_items from a 960x540 base, so shrinking the
## WINDOW to panel size does not give a tight shot - it rescales the whole canvas
## and the panel comes out squashed. Render at the native base and crop instead.
const VIEW: Vector2i = Vector2i(960, 540)
const CROP: Rect2i = Rect2i(12, 12, 200, 372)
## PNGs are saved at the native 960x540 canvas, NOT upscaled.
##
## Image.resize() on a viewport image is not trustworthy here: it invented ghost
## copies of item art at coordinates no live node occupied (verified by dumping
## every Control in the region - nothing was there, and the un-resized shot of
## the same frame was clean). Converting to RGBA8 first did not help. A preview
## whose artifacts have to be explained away is worse than a small one, so these
## ship at 1:1 and are zoomed in an image viewer.



func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	get_window().size = VIEW
	var root: Control = Control.new()
	root.size = VIEW
	add_child(root)

	var ground: ColorRect = ColorRect.new()
	ground.size = VIEW
	ground.color = Color(0.20, 0.24, 0.18)
	root.add_child(ground)

	var panel: PanelContainer = (load(PANEL) as PackedScene).instantiate()
	root.add_child(panel)
	panel.show()
	# _show_toggles_view is what the "Toggles" button on the main page calls.
	panel.call(&"_show_toggles_view")

	for _i: int in 6:
		await get_tree().process_frame

	# AFTER the frames, not before: the host pins itself bottom-right through a
	# call_deferred(_place_panel) in its own _ready, which would otherwise walk
	# the panel straight back out of the crop.
	panel.position = Vector2(12, 12)
	for _j: int in 2:
		await get_tree().process_frame

	_report(panel)
	var image: Image = get_viewport().get_texture().get_image().get_region(CROP)
	image.save_png(ProjectSettings.globalize_path(OUT))
	print("wrote ", OUT)
	get_tree().quit()


## List the rows actually on the page, so a row that silently failed to build
## shows up as a missing line rather than as something subtly absent in a PNG.
func _report(panel: Node) -> void:
	print("--- toggles page rows ---")
	for node: Node in panel.find_children("*", "", true, false):
		if node is CheckButton or node is Button:
			var control: Control = node as Control
			if control.is_visible_in_tree():
				print("  %-12s %s" % [node.get_class(), (node as Button).text])
