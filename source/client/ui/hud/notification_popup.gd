extends Control


var current_notification_topic: StringName
var current_notification_payload: Dictionary

@onready var cancel_button: Button = $PanelContainer/VBoxContainer/HBoxContainer/CancelButton
@onready var confirm_button: Button = $PanelContainer/VBoxContainer/HBoxContainer/ConfirmButton

@onready var rich_text_label: RichTextLabel = $PanelContainer/VBoxContainer/RichTextLabel


func pop_notification(topic: StringName, payload: Dictionary) -> void:
	current_notification_topic = topic
	current_notification_payload = payload

	rich_text_label.clear()

	match topic:
			&"friend.request":
				friend_request()
			&"guild.invite":
				guild_invite()
			&"party.invite":
				party_invite()

	show()


func _on_cancel_button_pressed() -> void:
	if current_notification_topic == &"party.invite" and InstanceClient.current != null:
		Client.request_data(
			&"party.respond", Callable(),
			{
				"invite": current_notification_payload.get("invite", 0),
				"accepted": false,
			},
			InstanceClient.current.name
		)
	hide()


func _on_confirm_button_pressed() -> void:
	match current_notification_topic:
		&"friend.request":
			Client.request_data(
				&"friend.accept", Callable(),
				{"player_id": current_notification_payload.get("player_id", 0)}
			)
		&"guild.invite":
			Client.request_data(
				&"guild.invite.accept", Callable(),
				{"guild_id": current_notification_payload.get("guild_id", 0)}
			)
		&"party.invite":
			Client.request_data(
				&"party.respond", Callable(),
				{
					"invite": current_notification_payload.get("invite", 0),
					"accepted": true,
				},
				InstanceClient.current.name if InstanceClient.current != null else ""
			)
	hide()


func friend_request() -> void:
	rich_text_label.append_text(
		"You received a friend request from %s" % current_notification_payload.get("player_name", "")
	)
	cancel_button.text = "Refuse"
	confirm_button.text = "Accept"


func guild_invite() -> void:
	rich_text_label.append_text(
		"%s invited you to join the guild [b]%s[/b]" % [
			current_notification_payload.get("from_name", "Someone"),
			current_notification_payload.get("guild_name", ""),
		]
	)
	cancel_button.text = "Refuse"
	confirm_button.text = "Accept"


func party_invite() -> void:
	rich_text_label.append_text(
		"%s invited you to join their party." % current_notification_payload.get("from_name", "Someone")
	)
	cancel_button.text = "Refuse"
	confirm_button.text = "Accept"
