class_name SettingsCommandsActions
extends RefCounted
## Opens the role-filtered Chat Commands overlay from any Settings surface.

const COMMANDS_PANEL_SCRIPT: Script = preload(
	"res://source/client/ui/menus/settings/commands_panel.gd"
)


static func open_commands_panel(from: Node) -> void:
	if from == null:
		return
	var host: Control = _find_overlay_host(from)
	if host == null:
		return
	var panel: Control = host.get_node_or_null("CommandsPanel") as Control
	if panel == null:
		panel = COMMANDS_PANEL_SCRIPT.new() as Control
		panel.name = "CommandsPanel"
		panel.z_index = 40
		host.add_child(panel)
	if panel.has_method(&"open"):
		panel.call(&"open")
	panel.move_to_front()


static func _find_overlay_host(from: Node) -> Control:
	var node: Node = from
	while node != null:
		if node.get_script() != null and String(node.get_script().resource_path).ends_with("hud.gd"):
			return node as Control
		# Full Settings menu is a Navigator Control named "Settings".
		if node.name == &"Settings" and node is Control:
			return node as Control
		node = node.get_parent()
	var tree: SceneTree = from.get_tree()
	if tree == null:
		return null
	return tree.current_scene as Control
