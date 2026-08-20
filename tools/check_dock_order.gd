extends Node
## Screenshot the bottom dock row to confirm button order (Settings last).
##   godot --path . --mode=client res://tools/check_dock_order.tscn

const HUD_SCENE: String = "res://source/client/ui/hud/hud.tscn"
const OUT_DIR: String = "res://previews"
const W: int = 960
const H: int = 540


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var out_abs: String = ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_abs)

	var hud: Control = (load(HUD_SCENE) as PackedScene).instantiate() as Control
	get_tree().root.add_child(hud)
	await get_tree().process_frame
	await get_tree().process_frame

	var dock: Node = hud.get_node_or_null("BottomMenuDock")
	if dock == null:
		push_error("no BottomMenuDock")
		get_tree().quit(1)
		return
	var order: PackedStringArray = PackedStringArray()
	for child: Node in dock.get_children():
		var button: Button = child as Button
		if button == null:
			continue
		order.append(button.name if button.tooltip_text.is_empty() else button.tooltip_text)
	print("DOCK ORDER: ", ", ".join(order))
	get_tree().quit(0)
