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
	_build_online_label()
	visibility_changed.connect(_refresh_online_count)
	_refresh_online_count()


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
