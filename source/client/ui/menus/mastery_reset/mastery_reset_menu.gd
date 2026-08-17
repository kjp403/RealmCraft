extends Control
## Weapon-mastery re-spec picker — reached from Horizon's MasteryResetInteraction.
## Lists one button per tree the player has actually spent nodes in, plus an
## Everything option, so redoing Bow no longer wipes Sword too. Same compact card
## as attribute / skill-perk reset; the reset itself is server-authoritative
## (mastery.respec), which re-checks the scope and the fee.


const TITLE_COLOR: Color = Color(1.0, 0.95, 0.8)
const BODY_COLOR: Color = Color(0.85, 0.86, 0.92)
const ALL_COLOR: Color = Color(1.0, 0.72, 0.6)

var _cost: int = 0
var _list: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func open(arg: Variant) -> void:
	for child: Node in get_children():
		child.queue_free()
	_cost = int(arg) if arg != null else 0

	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.04, 0.05, 0.08, 0.4)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(380, 0)
	center.add_child(card)

	var pad: MarginContainer = MarginContainer.new()
	pad.add_theme_constant_override(&"margin_left", 16)
	pad.add_theme_constant_override(&"margin_right", 16)
	pad.add_theme_constant_override(&"margin_top", 14)
	pad.add_theme_constant_override(&"margin_bottom", 14)
	card.add_child(pad)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 12)
	pad.add_child(box)

	var title: Label = Label.new()
	title.text = "Respec mastery points"
	title.add_theme_color_override(&"font_color", TITLE_COLOR)
	title.add_theme_font_size_override(&"font_size", 20)
	box.add_child(title)

	var body: Label = Label.new()
	body.text = (
		"Pick a tree to refund its mastery points, or refund every tree at once.\n"
		+ "Either way costs %d gold. Refunding a tree also clears its Q / E picks."
	) % _cost
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override(&"font_color", BODY_COLOR)
	box.add_child(body)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", 6)
	box.add_child(_list)

	var loading: Label = Label.new()
	loading.text = "Loading your trees…"
	loading.add_theme_color_override(&"font_color", BODY_COLOR)
	_list.add_child(loading)

	var cancel: Button = Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(110, 36)
	cancel.pressed.connect(hide)
	box.add_child(cancel)

	_fill_options()


## One button per tree with spent nodes, then Everything. Built from mastery.get
## so the list only ever offers scopes that would actually refund something —
## the server rejects the rest with "nothing", and a button that always fails is
## worse than no button.
func _fill_options() -> void:
	var result: Array = await Client.request_data_await(
		&"mastery.get", {}, InstanceClient.current.name
	)
	if not is_inside_tree():
		return # menu closed while the fetch was in flight
	for child: Node in _list.get_children():
		child.queue_free()
	if result.size() < 2 or result[1] != OK:
		_show_note("Couldn't read your trees right now.")
		return

	var masteries: Dictionary = (result[0] as Dictionary).get("masteries", {})
	var total: int = 0
	var rows: Array[Dictionary] = []
	for slug: Variant in masteries:
		var spent: int = ((masteries[slug] as Dictionary).get("spent", []) as Array).size()
		if spent <= 0:
			continue
		total += spent
		rows.append({
			"slug": String(slug),
			"name": _tree_name(String(slug)),
			"spent": spent,
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name < b.name)

	if rows.is_empty():
		_show_note("You haven't spent any mastery points yet.")
		return

	for row: Dictionary in rows:
		_add_option(
			"%s — %d %s" % [row.name, row.spent, "node" if row.spent == 1 else "nodes"],
			row.slug,
			BODY_COLOR
		)
	# Only worth offering once more than one tree is in play.
	if rows.size() > 1:
		_add_option("Everything — %d nodes" % total, "", ALL_COLOR)


## "Archery" rather than "bow" — trees are common/ content the client holds, so
## the display name never has to cross the wire.
func _tree_name(slug: String) -> String:
	var tree: MasteryTreeResource = MasteryService.tree_for(StringName(slug))
	if tree != null and not tree.display_name.is_empty():
		return tree.display_name
	return slug.capitalize()


func _add_option(label: String, category: String, color: Color) -> void:
	var button: Button = Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(300, 36)
	button.add_theme_color_override(&"font_color", color)
	button.pressed.connect(_on_pick.bind(category))
	_list.add_child(button)


func _show_note(text: String) -> void:
	var note: Label = Label.new()
	note.text = text
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override(&"font_color", BODY_COLOR)
	_list.add_child(note)


## [param category] empty = every tree (the server's all-scope).
func _on_pick(category: String) -> void:
	var args: Dictionary = {}
	if not category.is_empty():
		args["category"] = category
	var result: Array = await Client.request_data_await(
		&"mastery.respec", args, InstanceClient.current.name
	)
	hide()
	if result[1] != OK:
		return
	var data: Dictionary = result[0]
	if data.get("ok", false):
		Toaster.toast(
			"%d mastery nodes refunded. Spend them again in Character → Mastery."
			% int(data.get("refunded_nodes", 0))
		)
		return
	match str(data.get("reason", "")):
		"gold":
			Toaster.toast("Not enough gold to respec mastery.")
		"nothing":
			Toaster.toast("You haven't spent any mastery points there yet.")
		"no_tree":
			Toaster.toast("That weapon has no mastery tree.")
		_:
			Toaster.toast("Couldn't respec mastery right now.")
