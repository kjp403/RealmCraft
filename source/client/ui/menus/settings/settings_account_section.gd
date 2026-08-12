extends VBoxContainer
## Account / community actions at the bottom of Settings → General.


@onready var _discord_button: Button = $DiscordButton
@onready var _logout_button: Button = $LogoutButton
@onready var _commands_button: Button = $CommandsButton

var _online_label: Label


func _ready() -> void:
	_discord_button.pressed.connect(SettingsAccountActions.open_discord)
	_logout_button.pressed.connect(_on_logout_pressed)
	_commands_button.pressed.connect(_on_commands_pressed)
	_style_logout_button(_logout_button)
	_build_online_label()
	visibility_changed.connect(_refresh_online_count)
	_refresh_online_count()


func _style_logout_button(button: Button) -> void:
	const RED := Color(0.92, 0.28, 0.28)
	const RED_HOVER := Color(1.0, 0.42, 0.38)
	const RED_PRESSED := Color(0.72, 0.16, 0.16)
	button.add_theme_color_override(&"font_color", Color(1.0, 0.92, 0.92))
	button.add_theme_color_override(&"font_hover_color", Color(1.0, 0.98, 0.98))
	button.add_theme_color_override(&"font_pressed_color", Color(1.0, 0.85, 0.85))
	button.add_theme_color_override(&"font_focus_color", Color(1.0, 0.92, 0.92))
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = (
			RED_PRESSED if state == &"pressed"
			else (RED_HOVER if state == &"hover" else RED)
		)
		box.set_border_width_all(1)
		box.border_color = Color(1.0, 0.55, 0.5)
		box.set_corner_radius_all(2)
		box.content_margin_left = 8
		box.content_margin_right = 8
		box.content_margin_top = 4
		box.content_margin_bottom = 4
		button.add_theme_stylebox_override(state, box)


## Server population, above the account buttons. Built in code (not the scene)
## because it only means anything once we're in a world — Settings also opens
## from the login screen, where there is no instance to ask.
func _build_online_label() -> void:
	_online_label = Label.new()
	_online_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_online_label.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.45))
	_online_label.tooltip_text = "Characters connected to this world right now."
	_online_label.visible = false
	add_child(_online_label)
	move_child(_online_label, 1) # directly under "Account"


func _refresh_online_count() -> void:
	if not is_visible_in_tree() or InstanceClient.current == null:
		return
	Client.request_data(
		&"players.online",
		func(data: Dictionary) -> void:
			if not is_instance_valid(_online_label):
				return
			_online_label.text = "Players online: %d" % int(data.get("count", 0))
			_online_label.visible = true,
		{},
		InstanceClient.current.name
	)


func _on_commands_pressed() -> void:
	const ACTIONS := preload("res://source/client/ui/menus/settings/settings_commands_actions.gd")
	ACTIONS.open_commands_panel(self)


func _on_logout_pressed() -> void:
	var node: Node = self
	while node != null:
		if node.name == &"Settings" and node is CanvasItem:
			(node as CanvasItem).hide()
			break
		node = node.get_parent()
	SettingsAccountActions.logout_to_login()
