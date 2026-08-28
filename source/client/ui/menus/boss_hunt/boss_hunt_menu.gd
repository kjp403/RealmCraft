extends MenuShell
## Full-screen Boss Hunt contract board. Opened by talking to a Hunt Broker
## (open_menu_requested(&"boss_hunt", station)).
##
## LEFT: the roster of huntable bosses — one card each, cheapest first, priced in
## gold. Picking one is a SHARED choice: the server broadcasts it to everyone in
## the lobby, so the party agrees on the target before anyone pays.
## RIGHT: the party (up to 4) and the buttons. Whoever presses Open Contract pays
## the whole fee; everyone in the queue rides in free.

const COLOR_GOLD: Color = Color(1.0, 0.92, 0.55)
const COLOR_MUTED: Color = Color(0.75, 0.78, 0.85)
const COLOR_BAD: Color = Color(0.92, 0.55, 0.45)

var _station: String = ""
var _contracts: Array = []
var _selected: String = ""
## Live confirm dialog, rebuilt per press so stale ones cannot stack up.
var _confirm: ConfirmationDialog
var _members: Array = []
var _capacity: int = 4
var _in_queue: bool = false
var _gold: int = 0
var _duration_s: int = 1800

var _list_host: VBoxContainer
var _right: PanelContainer


func _ready() -> void:
	build_shell("Boss Contracts", null, true)
	Client.subscribe(&"boss_hunt.lobby.update", _on_lobby_update)
	_build_layout()
	visibility_changed.connect(func() -> void:
		if visible:
			_refresh())


func open(station: String) -> void:
	_station = station
	_in_queue = false
	_refresh()


# --- layout ------------------------------------------------------------------

func _build_layout() -> void:
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override(&"separation", 14)
	content.add_child(hbox)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 1.6
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hbox.add_child(scroll)

	_list_host = VBoxContainer.new()
	_list_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_host.add_theme_constant_override(&"separation", 8)
	scroll.add_child(_list_host)

	_right = PanelContainer.new()
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(_right)


# --- data --------------------------------------------------------------------

func _refresh() -> void:
	if _list_host == null:
		return
	Client.request_data(
		&"boss_hunt.info", _apply_state, {"station": _station},
		String(InstanceClient.current.name) if InstanceClient.current else ""
	)


func _apply_state(response: Dictionary) -> void:
	if not bool(response.get("ok", false)):
		Toaster.toast(_reason_text(response))
		hide()
		return
	if bool(response.get("started", false)):
		hide()
		return
	if response.has("contracts"):
		_contracts = response["contracts"]
	_selected = str(response.get("selected", _selected))
	_members = response.get("members", _members)
	_capacity = int(response.get("capacity", _capacity))
	_in_queue = bool(response.get("in_queue", _in_queue))
	_gold = int(response.get("gold", _gold))
	_duration_s = int(response.get("duration_s", _duration_s))
	_render_board()
	_render_party()


## Server push: someone else joined/left the lobby or re-picked the target.
func _on_lobby_update(payload: Dictionary) -> void:
	if not visible or str(payload.get("station", "")) != _station:
		return
	_members = payload.get("members", [])
	_capacity = int(payload.get("capacity", _capacity))
	_selected = str(payload.get("selected", _selected))
	_render_board()
	_render_party()


# --- board -------------------------------------------------------------------

func _render_board() -> void:
	for child: Node in _list_host.get_children():
		child.queue_free()

	var blurb: Label = Label.new()
	blurb.text = (
		"Pay the fee, get a private room with one boss in it for %d minutes. "
		+ "It respawns every time you kill it and every drop goes into your Hunt Chest.\n"
		+ "Loot rates are full, but XP is cut — killing a boss out in the world is "
		+ "still worth more. This is the faster farm, not the better one."
	) % int(_duration_s / 60.0)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_font_size_override(&"font_size", 12)
	blurb.add_theme_color_override(&"font_color", COLOR_MUTED)
	_list_host.add_child(blurb)

	var purse: Label = Label.new()
	purse.text = "Your gold: %s" % _fmt_gold(_gold)
	purse.add_theme_font_size_override(&"font_size", 13)
	purse.add_theme_color_override(&"font_color", COLOR_GOLD)
	_list_host.add_child(purse)
	_list_host.add_child(HSeparator.new())

	for contract: Variant in _contracts:
		if contract is Dictionary:
			_list_host.add_child(_contract_card(contract as Dictionary))


## One selectable contract row: name + price on the top line, level and respawn
## cadence under it, the pitch below that. Unaffordable cards stay clickable (the
## party can still agree on a target someone else pays for) but read as red.
func _contract_card(contract: Dictionary) -> Control:
	var id: String = str(contract.get("id", ""))
	var cost: int = int(contract.get("cost", 0))
	var affordable: bool = _gold >= cost

	var button: Button = Button.new()
	button.toggle_mode = true
	button.button_pressed = id == _selected
	button.custom_minimum_size = Vector2(0, 78)
	button.pressed.connect(func() -> void: _select(id))

	var pad: MarginContainer = MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override(&"margin_left", 12)
	pad.add_theme_constant_override(&"margin_right", 12)
	pad.add_theme_constant_override(&"margin_top", 8)
	pad.add_theme_constant_override(&"margin_bottom", 8)
	button.add_child(pad)

	var rows: VBoxContainer = VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override(&"separation", 2)
	pad.add_child(rows)

	var top: HBoxContainer = HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(top)
	var name_label: Label = Label.new()
	name_label.text = str(contract.get("name", "?"))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override(&"font_size", 15)
	top.add_child(name_label)
	var price: Label = Label.new()
	price.text = "%s g" % _fmt_gold(cost)
	price.add_theme_font_size_override(&"font_size", 15)
	price.add_theme_color_override(&"font_color", COLOR_GOLD if affordable else COLOR_BAD)
	top.add_child(price)

	var meta: Label = Label.new()
	meta.text = "Level %d  ·  respawns every %ds  ·  %d%% XP  ·  %s–%s HP by party size" % [
		int(contract.get("level", 1)),
		int(contract.get("respawn_s", 12)),
		int(contract.get("xp_pct", 100)),
		_fmt_gold(int(contract.get("hp_solo", 0))),
		_fmt_gold(int(contract.get("hp_full", 0))),
	]
	meta.add_theme_font_size_override(&"font_size", 11)
	meta.add_theme_color_override(&"font_color", COLOR_MUTED)
	rows.add_child(meta)

	var desc: String = str(contract.get("description", ""))
	if not desc.is_empty():
		var pitch: Label = Label.new()
		pitch.text = desc
		pitch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pitch.add_theme_font_size_override(&"font_size", 11)
		pitch.modulate.a = 0.7
		rows.add_child(pitch)

	return button


# --- party panel --------------------------------------------------------------

func _render_party() -> void:
	for child: Node in _right.get_children():
		child.queue_free()

	var pad: MarginContainer = MarginContainer.new()
	pad.add_theme_constant_override(&"margin_left", 14)
	pad.add_theme_constant_override(&"margin_right", 14)
	pad.add_theme_constant_override(&"margin_top", 12)
	pad.add_theme_constant_override(&"margin_bottom", 12)
	_right.add_child(pad)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override(&"separation", 10)
	pad.add_child(vbox)

	var chosen: Dictionary = _selected_contract()
	var target: Label = Label.new()
	target.text = str(chosen.get("name", "No contract selected"))
	target.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	target.add_theme_font_size_override(&"font_size", 16)
	target.add_theme_color_override(&"font_color", COLOR_GOLD if not chosen.is_empty() else COLOR_MUTED)
	vbox.add_child(target)

	var cost: int = int(chosen.get("cost", 0))
	if not chosen.is_empty():
		var fee: Label = Label.new()
		fee.text = "Fee %s gold  ·  %d minutes" % [_fmt_gold(cost), int(_duration_s / 60.0)]
		fee.add_theme_font_size_override(&"font_size", 12)
		fee.add_theme_color_override(&"font_color", COLOR_MUTED)
		vbox.add_child(fee)

	vbox.add_child(HSeparator.new())

	var header: Label = Label.new()
	header.text = "Party  (%d/%d)" % [_members.size(), _capacity]
	header.add_theme_font_size_override(&"font_size", 14)
	header.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.5))
	vbox.add_child(header)
	for member: Variant in _members:
		var row: Label = Label.new()
		row.text = "• " + str(member)
		vbox.add_child(row)
	for _i: int in range(_members.size(), _capacity):
		var slot: Label = Label.new()
		slot.text = "• —"
		slot.modulate.a = 0.35
		vbox.add_child(slot)

	var note: Label = Label.new()
	note.text = "Whoever opens the contract pays the whole fee. Everyone else joins free.\nThe boss gets tougher for every player in the room — no bonus for going alone."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override(&"font_size", 11)
	note.modulate = Color(1, 1, 1, 0.55)
	vbox.add_child(note)

	vbox.add_child(HSeparator.new())
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 10)
	vbox.add_child(buttons)
	buttons.add_child(_action_button("Leave" if _in_queue else "Join Party",
		_on_leave if _in_queue else _on_join))

	var start: Button = _action_button("Open Contract", _on_start)
	start.disabled = chosen.is_empty() or _gold < cost
	if start.disabled and not chosen.is_empty():
		start.tooltip_text = "You need %s gold." % _fmt_gold(cost)
	buttons.add_child(start)


# --- requests -----------------------------------------------------------------

func _select(contract_id: String) -> void:
	_selected = contract_id
	_send("select", {"contract": contract_id})


func _on_join() -> void:
	_send("join")


func _on_leave() -> void:
	_in_queue = false
	_send("leave")


func _on_start() -> void:
	# The fee is spent the moment the contract opens and the party only gets
	# BossHuntService.CONTRACT_LIVES deaths, so this is the last point where a
	# player can back out. Confirm in the clearest terms the cost and the
	# consequence.
	if _confirm != null and is_instance_valid(_confirm):
		_confirm.queue_free()
	_confirm = ConfirmationDialog.new()
	_confirm.title = "Open Contract"
	_confirm.ok_button_text = "Pay and start"
	_confirm.cancel_button_text = "Not yet"
	var cost: int = int(_contract_cost())
	_confirm.dialog_text = (
		"Open this contract for %s gold?

"
		+ "Your party shares %d lives, however many of you go in. Spend the
"
		+ "last one and the contract fails. Leave the arena and you are out of
"
		+ "this hunt. The gold is not refunded either way.

"
		+ "Bring food."
	) % [_fmt_gold(cost), BossHuntService.CONTRACT_LIVES]
	_confirm.confirmed.connect(func() -> void: _send("start"))
	add_child(_confirm)
	_confirm.popup_centered()


## Fee for the selected contract, for the confirm prompt.
func _contract_cost() -> int:
	for contract: Dictionary in _contracts:
		if str(contract.get("id", "")) == _selected:
			return int(contract.get("cost", 0))
	return 0


func _send(action: String, extra: Dictionary = {}) -> void:
	var args: Dictionary = {"station": _station, "action": action}
	args.merge(extra)
	Client.request_data(
		&"boss_hunt.queue", _apply_state, args,
		String(InstanceClient.current.name) if InstanceClient.current else ""
	)


# --- helpers ------------------------------------------------------------------

func _selected_contract() -> Dictionary:
	for contract: Variant in _contracts:
		if contract is Dictionary and str((contract as Dictionary).get("id", "")) == _selected:
			return contract
	return {}


func _reason_text(response: Dictionary) -> String:
	if response.has("message"):
		return str(response["message"])
	return {
		"too_far": "You're too far from the broker.",
		"no_broker": "No contract board here.",
		"no_contract": "Pick a boss first.",
		"in_run": "Finish what you're in first.",
		"full": "The party is full.",
		"poor": "You can't afford that contract.",
	}.get(str(response.get("reason", "")), "The broker isn't taking that.")


static func _fmt_gold(amount: int) -> String:
	if amount >= 1000:
		return "%s,%03d" % [str(int(amount / 1000.0)), amount % 1000]
	return str(amount)


func _action_button(text: String, callback: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(110, 40)
	b.pressed.connect(callback)
	return b
