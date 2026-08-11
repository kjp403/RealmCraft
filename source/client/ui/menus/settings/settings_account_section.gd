extends VBoxContainer
## Account / community actions at the bottom of Settings → General.


@onready var _discord_button: Button = $DiscordButton
@onready var _logout_button: Button = $LogoutButton
@onready var _commands_button: Button = $CommandsButton


func _ready() -> void:
	_discord_button.pressed.connect(SettingsAccountActions.open_discord)
	_logout_button.pressed.connect(_on_logout_pressed)
	_commands_button.pressed.connect(_on_commands_pressed)


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
