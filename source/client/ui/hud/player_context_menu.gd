class_name PlayerContextMenu
extends Node
## HUD-owned social actions for remote players. World hitboxes only emit a peer id;
## this node owns all presentation and network requests.

const ACTION_EXAMINE: int = 0
const ACTION_FOLLOW: int = 1
const ACTION_TRADE: int = 2
const ACTION_KICK: int = 3
const ACTION_BAN: int = 4
const ACTION_IP_BAN: int = 5
const TARGET_HEADING_ID: int = 100

var _menu: PopupMenu
var _invite_dialog: ConfirmationDialog
var _mod_dialog: ConfirmationDialog
var _target_peer_id: int = 0
var _target_name: String = ""
var _target_player_id: int = 0
var _invite_id: int = 0
var _pending_mod_action: int = -1


func _ready() -> void:
	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_action)
	add_child(_menu)

	_invite_dialog = ConfirmationDialog.new()
	_invite_dialog.title = "Trade request"
	_invite_dialog.ok_button_text = "Accept"
	_invite_dialog.cancel_button_text = "Decline"
	_invite_dialog.confirmed.connect(_respond_to_invite.bind(true))
	_invite_dialog.canceled.connect(_respond_to_invite.bind(false))
	add_child(_invite_dialog)

	_mod_dialog = ConfirmationDialog.new()
	_mod_dialog.title = "Confirm"
	_mod_dialog.ok_button_text = "Confirm"
	_mod_dialog.cancel_button_text = "Cancel"
	_mod_dialog.confirmed.connect(_confirm_mod_action)
	_mod_dialog.canceled.connect(func() -> void: _pending_mod_action = -1)
	add_child(_mod_dialog)

	ClientState.player_context_requested.connect(_open_for_peer)
	Client.subscribe(&"trade.invite", _on_trade_invite)
	Client.subscribe(&"trade.open", _on_trade_open)
	Client.subscribe(&"trade.invite_result", _on_invite_result)


func _open_for_peer(peer_id: int) -> void:
	if InstanceClient.current == null:
		return
	var target: Player = InstanceClient.current.players_by_peer_id.get(peer_id, null)
	if target == null or target == ClientState.local_player:
		return
	_target_peer_id = peer_id
	_target_name = str(target.display_name)
	_target_player_id = int(target.player_id)
	_menu.clear()
	_menu.add_item(_target_name, TARGET_HEADING_ID)
	_menu.set_item_disabled(0, true)
	_menu.add_separator()
	_menu.add_item("Examine", ACTION_EXAMINE)
	_menu.add_item("Follow", ACTION_FOLLOW)
	_menu.add_item("Trade", ACTION_TRADE)
	# Admin+ only (synced staff_role; owner/senior_admin are mapped to "admin").
	# Menu is shown even on other staff — owners need to right-click-ban a rogue
	# senior_admin. Server enforces rank (admin cannot punish admin+).
	var me: Player = ClientState.local_player
	if me != null and me.staff_role == "admin":
		_menu.add_separator()
		_menu.add_item("Kick", ACTION_KICK)
		_menu.add_item("Ban", ACTION_BAN)
		_menu.add_item("IP Ban", ACTION_IP_BAN)
	_menu.position = Vector2i(get_viewport().get_mouse_position())
	_menu.popup()


func _on_action(action_id: int) -> void:
	match action_id:
		ACTION_EXAMINE:
			ClientState.player_profile_by_peer_requested.emit(_target_peer_id)
		ACTION_FOLLOW:
			var local_player: LocalPlayer = ClientState.local_player
			if local_player != null and local_player.follow_peer(_target_peer_id):
				Toaster.toast("Following %s. Move manually to stop." % _target_name)
		ACTION_TRADE:
			_request_trade()
		ACTION_KICK, ACTION_BAN, ACTION_IP_BAN:
			_ask_mod_action(action_id)


func _ask_mod_action(action_id: int) -> void:
	if _target_player_id <= 0:
		Toaster.toast("Can't moderate that player yet (missing id).")
		return
	_pending_mod_action = action_id
	var ok_label: String = "Confirm"
	match action_id:
		ACTION_KICK:
			_mod_dialog.title = "Confirm kick"
			_mod_dialog.dialog_text = (
				"Kick %s (#%d) from the world?\n\nThey can reconnect unless you also ban them."
				% [_target_name, _target_player_id]
			)
			ok_label = "Kick"
		ACTION_BAN:
			_mod_dialog.title = "Confirm account ban"
			_mod_dialog.dialog_text = (
				"Permanently ban %s's account (#%d)?\n\n"
				+ "This blocks them even while offline. This cannot be undone from here."
			) % [_target_name, _target_player_id]
			ok_label = "Ban account"
		ACTION_IP_BAN:
			_mod_dialog.title = "Confirm IP ban"
			_mod_dialog.dialog_text = (
				"Permanently IP-ban %s (#%d)?\n\n"
				+ "Their current IP will be blocked from joining. This cannot be undone from here."
			) % [_target_name, _target_player_id]
			ok_label = "IP ban"
		_:
			_pending_mod_action = -1
			return
	_mod_dialog.ok_button_text = ok_label
	_mod_dialog.cancel_button_text = "Cancel"
	# Chat LineEdit steals Enter — release it, then focus Cancel so a stray
	# Enter/Space after the right-click menu does NOT confirm the ban/kick.
	var focused: Control = get_viewport().gui_get_focus_owner() as Control
	if focused != null:
		focused.release_focus()
	_mod_dialog.popup_centered(Vector2i(440, 180))
	var cancel_btn: Button = _mod_dialog.get_cancel_button()
	if cancel_btn != null:
		cancel_btn.grab_focus()


func _confirm_mod_action() -> void:
	var action_id: int = _pending_mod_action
	_pending_mod_action = -1
	if action_id < 0 or _target_player_id <= 0 or InstanceClient.current == null:
		return
	var cmd: String = ""
	match action_id:
		ACTION_KICK:
			cmd = "kick"
		ACTION_BAN:
			cmd = "ban"
		ACTION_IP_BAN:
			cmd = "ipban"
		_:
			return
	var target_token: String = "#%d" % _target_player_id
	Client.request_data(
		&"chat.command.exec",
		Callable(),
		{"cmd": cmd, "params": PackedStringArray([cmd, target_token])},
		InstanceClient.current.name
	)
	match action_id:
		ACTION_KICK:
			Toaster.toast("Kick requested for %s." % _target_name)
		ACTION_BAN:
			Toaster.toast("Ban requested for %s." % _target_name)
		ACTION_IP_BAN:
			Toaster.toast("IP ban requested for %s." % _target_name)


func _request_trade() -> void:
	if InstanceClient.current == null or _target_peer_id <= 0:
		return
	var result: Array = await Client.request_data_await(
		&"trade.request",
		{"peer_id": _target_peer_id},
		InstanceClient.current.name
	)
	if result.size() < 2 or result[1] != OK:
		Toaster.toast("Trade request failed.")
		return
	var payload: Dictionary = result[0]
	if bool(payload.get("ok", false)):
		Toaster.toast("Trade request sent to %s." % _target_name)
		return
	match str(payload.get("reason", "")):
		"too_far": Toaster.toast("Move closer before requesting a trade.")
		"busy": Toaster.toast("One of you is already trading.")
		"combat": Toaster.toast("You cannot trade during combat.")
		"rate_limited": Toaster.toast("Please wait before sending another request.")
		_: Toaster.toast("That player is not available to trade.")


func _on_trade_invite(payload: Dictionary) -> void:
	_invite_id = int(payload.get("invite", 0))
	if _invite_id <= 0:
		return
	# Chat LineEdit steals Enter / focus — release it so Accept is unambiguous.
	var focused: Control = get_viewport().gui_get_focus_owner() as Control
	if focused != null:
		focused.release_focus()
	_invite_dialog.dialog_text = "%s wants to trade with you." % str(
		payload.get("from_name", "Another player")
	)
	_invite_dialog.popup_centered(Vector2i(380, 150))
	_invite_dialog.grab_focus()


func _respond_to_invite(accepted: bool) -> void:
	if _invite_id <= 0 or InstanceClient.current == null:
		return
	var invite_id: int = _invite_id
	_invite_id = 0
	var focused: Control = get_viewport().gui_get_focus_owner() as Control
	if focused != null:
		focused.release_focus()
	var result: Array = await Client.request_data_await(
		&"trade.respond",
		{"invite": invite_id, "accepted": accepted},
		InstanceClient.current.name
	)
	if result.size() < 2 or result[1] != OK:
		Toaster.toast("Could not answer the trade request.")
		return
	var payload: Dictionary = result[0]
	if not bool(payload.get("ok", false)) and accepted:
		Toaster.toast("That trade request is no longer available.")
		return
	# Open immediately from the respond reply so the accepter never depends on
	# a separate trade.open push landing while chat/HUD is reshuffling.
	if accepted and bool(payload.get("ok", false)):
		var trade_id: int = int(payload.get("trade", 0))
		if trade_id > 0:
			ClientState.set_viewed_trade(trade_id)


func _on_trade_open(payload: Dictionary) -> void:
	var trade_id: int = int(payload.get("trade", 0))
	if trade_id > 0:
		ClientState.set_viewed_trade(trade_id)


func _on_invite_result(payload: Dictionary) -> void:
	if bool(payload.get("incoming", false)) \
			and int(payload.get("invite", 0)) == _invite_id:
		_invite_id = 0
		_invite_dialog.hide()
	if bool(payload.get("accepted", false)):
		return
	match str(payload.get("reason", "")):
		"declined": Toaster.toast("%s declined the trade request." % str(payload.get("name", "Player")))
		"expired": Toaster.toast("The trade request expired.")
		_: Toaster.toast("The trade request could not be completed.")
