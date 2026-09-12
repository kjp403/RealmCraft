extends MenuShell
## Staff VFX Vault - Titles, Skins, and Cosmetics each get a tab. Opened from
## the Curator. Individual Curator buttons jump to the matching tab via open(arg).
##
## PREMIUM PURCHASING lives here rather than in the three tabs, because all three
## sell the same way and the lockout has to be one state, not three. A tab says
## only "this is selected"; cost, ownership and the buy button are this shell's.
##
## THE BALANCE IS NEVER CACHED ACROSS OPENS. It is fetched on show and replaced by
## whatever the purchase response reports. A number left over from last time is
## worse than no number - it is a number the player will believe.


const TITLES_SCENE: PackedScene = preload("res://source/client/ui/menus/titles/titles_menu.tscn")
const SKINS_SCENE: PackedScene = preload("res://source/client/ui/menus/skins/skins_menu.tscn")
const COSMETICS_SCENE: PackedScene = preload("res://source/client/ui/menus/cosmetics/cosmetics_menu.tscn")

const TAB_TITLES := &"titles"
const TAB_SKINS := &"skins"
const TAB_COSMETICS := &"cosmetics"

## Failure reasons the server and the web backend can return, in player words.
## Anything not listed falls back to a generic line rather than printing a slug.
const REASON_TEXT: Dictionary = {
	"insufficient_funds": "Not enough Arkenelle currency.",
	"already_owned": "You already own that.",
	"in_flight": "A purchase is already going through.",
	"no_account": "Link a website account to buy from the Vault.",
	"no_player": "You are not in the world right now.",
	"not_configured": "The store is offline right now.",
	"unauthorized": "The store rejected this server. Tell a dev.",
	"unknown_item": "That is not for sale.",
	"duplicate": "That purchase already went through.",
	"rate_limited": "Slow down a moment.",
	"backend_error": "The store had a problem. Nothing was charged.",
	"timeout": "The store did not answer. Check your balance before retrying.",
	"network": "Network error. Nothing was charged.",
	"bad_json": "The store sent something unreadable. Nothing was charged.",
}

var _tab: StringName = TAB_TITLES
var _tab_buttons: Dictionary = {}
var _panels: Dictionary = {}

## item_id -> catalog row {label, cost, owned, ...}. Server-sent; the client never
## computes a price.
var _catalog: Dictionary = {}
var _selected: String = ""
var _balance: int = -1        # -1 = not yet known, distinct from a real zero
var _purchasable: bool = false
var _processing: bool = false

var _balance_label: Label
var _buy_button: Button
var _status_label: Label


func _ready() -> void:
	build_shell("The Vault", null, true)
	_build_layout()
	_select_tab(TAB_TITLES)
	# Pushes, not responses: the server acks a purchase immediately and settles it
	# later, so the outcome arrives here and not on the request's callback.
	Client.subscribe(&"vault.balance.result", _on_balance)
	Client.subscribe(&"vault.purchase.result", _on_purchased)
	visibility_changed.connect(func() -> void:
		if visible:
			_refresh())
	_refresh.call_deferred()


func _exit_tree() -> void:
	Client.unsubscribe(&"vault.balance.result", _on_balance)
	Client.unsubscribe(&"vault.purchase.result", _on_purchased)


func open(arg: Variant = null) -> void:
	var key: String = str(arg).strip_edges().to_lower()
	match key:
		"skins":
			_select_tab(TAB_SKINS)
		"cosmetics":
			_select_tab(TAB_COSMETICS)
		_:
			_select_tab(TAB_TITLES)


## Called by a tab when its highlighted entry changes. The token is a VaultGrants
## token built client-side by the tab - it is only ever echoed back to the server,
## which re-resolves it, so a forged one resolves to nothing.
func set_selection(item_id: String) -> void:
	_selected = item_id.strip_edges()
	_update_buy()


func _build_layout() -> void:
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 8)
	content.add_child(col)

	_balance_label = Label.new()
	_balance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_balance_label.add_theme_font_size_override(&"font_size", 14)
	_balance_label.text = "Balance: ..."
	header_right.add_child(_balance_label)

	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override(&"separation", 6)
	col.add_child(tabs)
	_add_tab_button(tabs, TAB_TITLES, "Titles")
	_add_tab_button(tabs, TAB_SKINS, "Skins")
	_add_tab_button(tabs, TAB_COSMETICS, "Cosmetics")

	var body: Control = Control.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	_embed(body, TAB_TITLES, TITLES_SCENE)
	_embed(body, TAB_SKINS, SKINS_SCENE)
	_embed(body, TAB_COSMETICS, COSMETICS_SCENE)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.modulate = Color(1, 1, 1, 0.75)
	_status_label.add_theme_font_size_override(&"font_size", 13)
	col.add_child(_status_label)

	_buy_button = Button.new()
	_buy_button.custom_minimum_size = Vector2(0, 44)
	_buy_button.add_theme_font_size_override(&"font_size", 18)
	_buy_button.disabled = true
	_buy_button.pressed.connect(_on_buy_pressed)
	col.add_child(_buy_button)


func _add_tab_button(row: HBoxContainer, id: StringName, label: String) -> void:
	var b: Button = Button.new()
	b.text = label
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(0, 36)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override(&"font_size", 16)
	b.pressed.connect(_select_tab.bind(id))
	row.add_child(b)
	_tab_buttons[id] = b


func _embed(body: Control, id: StringName, scene: PackedScene) -> void:
	var panel: Control = scene.instantiate()
	panel.set_meta(&"embedded", true)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(panel)
	_panels[id] = panel


func _select_tab(id: StringName) -> void:
	_tab = id
	for key: StringName in _tab_buttons:
		(_tab_buttons[key] as Button).button_pressed = (key == id)
	for key: StringName in _panels:
		var panel: Control = _panels[key]
		panel.visible = (key == id)
	# The new tab re-announces its own selection on show; until it does there is
	# nothing sensible to buy.
	_selected = ""
	_update_buy()


func _refresh() -> void:
	if InstanceClient.current == null:
		return
	# Deliberately NOT cleared to 0 - an unknown balance must not read as broke.
	_balance = -1
	_balance_label.text = "Balance: ..."
	var instance_name: String = String(InstanceClient.current.name)
	Client.request_data(&"vault.catalog", _on_catalog, {}, instance_name)
	Client.request_data(&"vault.balance", _on_balance_ack, {}, instance_name)


func _on_catalog(data: Dictionary) -> void:
	_catalog.clear()
	if not bool(data.get("ok", false)):
		_update_buy()
		return
	_purchasable = bool(data.get("purchasable", false))
	for row: Variant in data.get("items", []):
		var entry: Dictionary = row as Dictionary
		_catalog[str(entry.get("item_id", ""))] = entry
	_update_buy()


## The ack only says the fetch started. The number arrives on the push below.
func _on_balance_ack(data: Dictionary) -> void:
	if bool(data.get("ok", false)):
		return
	_balance_label.text = "Balance: -"
	_status_label.text = _reason_text(str(data.get("reason", "")))


func _on_balance(data: Dictionary) -> void:
	if not bool(data.get("ok", false)):
		_balance_label.text = "Balance: -"
		_status_label.text = _reason_text(str(data.get("reason", "")))
		return
	_balance = int(data.get("balance", 0))
	_balance_label.text = "Balance: %d" % _balance
	_update_buy()


func _on_buy_pressed() -> void:
	if _processing or _selected.is_empty() or InstanceClient.current == null:
		return
	# Locked BEFORE the request goes out, and released only by the settle push or
	# the request's own failure - this is the whole double-click defence on the
	# client side. The server's in-flight guard is the one that actually counts.
	_processing = true
	_status_label.text = "Processing transaction..."
	_update_buy()
	Client.request_data(
		&"vault.purchase",
		_on_purchase_ack,
		{"item_id": _selected},
		String(InstanceClient.current.name)
	)


## Ack, not outcome. A false here means the purchase never started and nothing was
## charged, so the button can come straight back.
func _on_purchase_ack(data: Dictionary) -> void:
	if bool(data.get("ok", false)):
		return
	_processing = false
	_status_label.text = _reason_text(str(data.get("reason", "")))
	_update_buy()


func _on_purchased(data: Dictionary) -> void:
	_processing = false
	var item_id: String = str(data.get("item_id", ""))
	if not bool(data.get("ok", false)):
		_status_label.text = _reason_text(str(data.get("reason", "")))
		_update_buy()
		return
	if _catalog.has(item_id):
		(_catalog[item_id] as Dictionary)["owned"] = true
	if data.has("balance"):
		_balance = int(data.get("balance", 0))
		_balance_label.text = "Balance: %d" % _balance
	_status_label.text = "Unlocked %s. Equip it from this tab." % str(data.get("label", "item"))
	_update_buy()


func _update_buy() -> void:
	if _processing:
		_buy_button.text = "Processing..."
		_buy_button.disabled = true
		return
	var entry: Dictionary = _catalog.get(_selected, {}) as Dictionary
	if entry.is_empty():
		_buy_button.text = "Not for sale"
		_buy_button.disabled = true
		return
	if bool(entry.get("owned", false)):
		_buy_button.text = "Owned"
		_buy_button.disabled = true
		return
	var cost: int = int(entry.get("cost", 0))
	_buy_button.text = "Buy - %d" % cost
	# Unknown balance (-1) still allows the click: the server is the authority on
	# affordability, and greying the button out on a failed fetch would look like
	# the item is unavailable.
	_buy_button.disabled = not _purchasable or (_balance >= 0 and _balance < cost)


func _reason_text(reason: String) -> String:
	return str(REASON_TEXT.get(reason, "Something went wrong. Nothing was charged."))
