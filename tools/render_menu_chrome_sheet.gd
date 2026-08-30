extends Node
## Contact sheet of the shared menu chrome across several real menus, so a change
## to MenuShell or the project theme can be SEEN rather than assumed.
##
##   godot --path . --mode=client res://tools/render_menu_chrome_sheet.tscn
##
## Scene mode, not `-s`: every menu here reaches Client / ClientState, which do
## not exist under `-s` (see docs + the memory on scene-mode tools).
##
## Menus are instantiated cold, with no server behind them. Most therefore render
## their empty/loading state — which is exactly what this shot is for. It is a
## check of the SHELL (frame, title type, Close button, backdrop), not of each
## menu's populated body; a menu that fails to instantiate at all is the finding.

const OUT_DIR: String = "res://previews"
const W: int = 960
const H: int = 540

## menu name -> scene path, following the display_menu convention.
const MENUS: Array[Array] = [
	["Bank", "res://source/client/ui/menus/bank/bank_menu.tscn"],
	["Crafting", "res://source/client/ui/menus/crafting/crafting_menu.tscn"],
	["Shop", "res://source/client/ui/menus/shop/shop_menu.tscn"],
	["Friends", "res://source/client/ui/menus/friends/friends_menu.tscn"],
	["Leaderboard", "res://source/client/ui/menus/leaderboard/leaderboard_menu.tscn"],
	["Help", "res://source/client/ui/menus/help/help_menu.tscn"],
]

var _sv: SubViewport
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

	var ground: ColorRect = ColorRect.new()
	ground.size = Vector2(W, H)
	ground.color = Color(0.20, 0.26, 0.20)
	_sv.add_child(ground)

	var failures: PackedStringArray = PackedStringArray()
	for row: Array in MENUS:
		var label: String = str(row[0])
		var path: String = str(row[1])
		if not ResourceLoader.exists(path):
			failures.append("%s: scene missing (%s)" % [label, path])
			continue
		var scene: PackedScene = load(path) as PackedScene
		if scene == null:
			failures.append("%s: scene failed to load" % label)
			continue
		var menu: Control = scene.instantiate() as Control
		if menu == null:
			failures.append("%s: instantiate returned null" % label)
			continue
		_sv.add_child(menu)
		menu.show()
		# Two frames to build, one to lay out.
		for _i: int in 4:
			await get_tree().process_frame
		await _capture("chrome-%s.png" % label.to_lower())
		menu.queue_free()
		await get_tree().process_frame

	if failures.is_empty():
		print("CHROME_SHEET_OK")
	else:
		print("CHROME_SHEET_ISSUES (%d)" % failures.size())
		for f: String in failures:
			print("  - %s" % f)
	get_tree().quit(0)


## MUST be awaited: it waits a frame before sampling, so a bare call lets the
## caller free the very menu being photographed.
func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = _sv.get_texture().get_image()
	image.resize(W * 2, H * 2, Image.INTERPOLATE_NEAREST)
	var path: String = _out_abs.path_join(file_name)
	image.save_png(path)
	print("wrote ", path)
