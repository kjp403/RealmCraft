extends VBoxContainer
## Account / community actions at the bottom of Settings → General.


@onready var _discord_button: Button = $DiscordButton
@onready var _logout_button: Button = $LogoutButton


func _ready() -> void:
	_discord_button.pressed.connect(SettingsAccountActions.open_discord)
	_logout_button.pressed.connect(_on_logout_pressed)


func _on_logout_pressed() -> void:
	var node: Node = self
	while node != null:
		if node.name == &"Settings" and node is CanvasItem:
			(node as CanvasItem).hide()
			break
		node = node.get_parent()
	SettingsAccountActions.logout_to_login()
