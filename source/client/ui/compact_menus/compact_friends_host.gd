extends PanelContainer

const PANEL_SIZE := Vector2(180.0, 262.0)
const RIGHT_MARGIN := 12.0
const BOTTOM_CLEARANCE := 52.0

@onready var title_label: Label = (
	$MarginContainer/MainColumn/Header/TitleLabel
)
@onready var header_spacer: Control = (
	$MarginContainer/MainColumn/Header/HeaderSpacer
)
@onready var close_button: Button = (
	$MarginContainer/MainColumn/Header/CloseButton
)
@onready var content: MarginContainer = (
	$MarginContainer/MainColumn/Content
)

var _search_field: LineEdit
var _status_label: Label
var _friend_list: VBoxContainer
var _scroll: ScrollContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE

	content.add_theme_constant_override(&"margin_left", 6)
	content.add_theme_constant_override(&"margin_right", 6)

	header_spacer.hide()
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.text = "Friends"

	for child: Node in content.get_children():
		content.remove_child(child)
		child.queue_free()

	_build_layout()

	close_button.pressed.connect(hide)
	visibility_changed.connect(_on_visibility_changed)

	var hud := get_parent() as Control
	if hud != null:
		hud.resized.connect(_place_panel)

	call_deferred(&"_place_panel")
	hide()


func _build_layout() -> void:
	var main_box := VBoxContainer.new()
	main_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_box.add_theme_constant_override(&"separation", 5)
	content.add_child(main_box)

	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override(&"separation", 4)
	main_box.add_child(search_row)

	_search_field = LineEdit.new()
	_search_field.placeholder_text = "Player name…"
	_search_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_field.custom_minimum_size = Vector2(0.0, 26.0)
	_search_field.clear_button_enabled = true
	_search_field.add_theme_font_size_override(&"font_size", 9)
	_search_field.text_submitted.connect(_on_search_submitted)
	_search_field.text_changed.connect(_on_search_text_changed)
	search_row.add_child(_search_field)

	var search_button := Button.new()
	search_button.text = "Go"
	search_button.custom_minimum_size = Vector2(32.0, 26.0)
	search_button.add_theme_font_size_override(&"font_size", 9)
	search_button.tooltip_text = (
		"Search by character name. Use @ for an account name."
	)
	search_button.pressed.connect(_on_search_button_pressed)
	search_row.add_child(search_button)

	_status_label = Label.new()
	_status_label.visible = false
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override(&"font_size", 8)
	_status_label.add_theme_color_override(
		&"font_color",
		Color(0.68, 0.70, 0.76)
	)
	main_box.add_child(_status_label)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = (
		ScrollContainer.SCROLL_MODE_DISABLED
	)
	main_box.add_child(_scroll)

	_friend_list = VBoxContainer.new()
	_friend_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_friend_list.add_theme_constant_override(&"separation", 3)
	_scroll.add_child(_friend_list)


func _on_visibility_changed() -> void:
	if visible:
		_search_field.text = ""
		_refresh_friends()


func _refresh_friends() -> void:
	if InstanceClient.current == null:
		return

	_set_status("")

	Client.request_data(
		&"friend.list",
		_on_friend_list_received,
		{},
		InstanceClient.current.name
	)


func _on_friend_list_received(payload: Dictionary) -> void:
	_clear_list()
	ClientState.set_friend_ids_from_list(payload)

	if payload.is_empty():
		_add_empty_message(
			"No friends yet.\nSearch above to find players."
		)
		return

	var entries: Array[Dictionary] = []

	for friend_id: Variant in payload:
		var friend_data: Dictionary = payload.get(
			friend_id,
			{}
		)

		entries.append({
			"id": int(friend_id),
			"name": str(friend_data.get("name", "Unknown")),
			"online": bool(friend_data.get("online", false)),
			"subtitle": "",
		})

	entries.sort_custom(_friend_before)

	for entry: Dictionary in entries:
		_add_player_row(entry)

	DragScroll.enable(_scroll)


func _friend_before(
	a: Dictionary,
	b: Dictionary
) -> bool:
	var a_online: bool = bool(a.get("online", false))
	var b_online: bool = bool(b.get("online", false))

	if a_online != b_online:
		return a_online

	return str(a.get("name", "")).naturalnocasecmp_to(
		str(b.get("name", ""))
	) < 0


func _on_search_button_pressed() -> void:
	_on_search_submitted(_search_field.text)


func _on_search_text_changed(new_text: String) -> void:
	if new_text.strip_edges().is_empty() and visible:
		_refresh_friends()


func _on_search_submitted(text: String) -> void:
	var query: String = text.strip_edges()

	if query.is_empty():
		_refresh_friends()
		return

	if InstanceClient.current == null:
		return

	_set_status("Searching…")

	Client.request_data(
		&"friend.search",
		_on_search_results_received,
		{"query": query},
		InstanceClient.current.name
	)


func _on_search_results_received(payload: Dictionary) -> void:
	_clear_list()

	var results: Array = payload.get("results", [])

	if results.is_empty():
		_set_status(
			str(payload.get("msg", "No players found."))
		)
		return

	_set_status(
		"%d result%s" % [
			results.size(),
			"" if results.size() == 1 else "s",
		]
	)

	for result: Dictionary in results:
		var account_name: String = str(
			result.get("account", "")
		)
		var subtitle: String = ""

		if not account_name.is_empty():
			subtitle = "@" + account_name

		if bool(result.get("friend", false)):
			if not subtitle.is_empty():
				subtitle += " · "
			subtitle += "Friend"

		_add_player_row({
			"id": int(result.get("id", 0)),
			"name": str(result.get("name", "Unknown")),
			"online": bool(result.get("online", false)),
			"subtitle": subtitle,
		})

	DragScroll.enable(_scroll)


func _add_player_row(entry: Dictionary) -> void:
	var player_id: int = int(entry.get("id", 0))
	if player_id <= 0:
		return

	var display_name: String = str(
		entry.get("name", "Unknown")
	)
	var subtitle: String = str(
		entry.get("subtitle", "")
	)
	var is_online: bool = bool(
		entry.get("online", false)
	)

	var row := Button.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size = Vector2(0.0, 32.0)
	row.focus_mode = Control.FOCUS_NONE
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_theme_font_size_override(&"font_size", 9)

	if is_online:
		row.text = "●  " + display_name
		row.add_theme_color_override(
			&"font_color",
			Color(0.58, 0.92, 0.58)
		)
	else:
		row.text = "○  " + display_name
		row.add_theme_color_override(
			&"font_color",
			Color(0.64, 0.65, 0.70)
		)

	if not subtitle.is_empty():
		row.tooltip_text = (
			"%s\n%s\n%s"
			% [
				display_name,
				subtitle,
				"Online" if is_online else "Offline",
			]
		)
	else:
		row.tooltip_text = (
			"%s\n%s"
			% [
				display_name,
				"Online" if is_online else "Offline",
			]
		)

	_apply_row_styles(row)
	row.pressed.connect(
		_on_player_pressed.bind(player_id)
	)
	_friend_list.add_child(row)


func _on_player_pressed(player_id: int) -> void:
	hide()
	ClientState.player_profile_requested.emit(player_id)


func _clear_list() -> void:
	for child: Node in _friend_list.get_children():
		_friend_list.remove_child(child)
		child.queue_free()


func _add_empty_message(message: String) -> void:
	var empty := Label.new()
	empty.text = message
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty.add_theme_font_size_override(&"font_size", 9)
	empty.add_theme_color_override(
		&"font_color",
		Color(0.62, 0.64, 0.70)
	)
	_friend_list.add_child(empty)


func _set_status(message: String) -> void:
	_status_label.text = message
	_status_label.visible = not message.is_empty()


func _apply_row_styles(row: Button) -> void:
	row.add_theme_stylebox_override(
		&"normal",
		_make_row_style(
			Color(0.035, 0.03, 0.055, 0.78),
			Color(0.32, 0.23, 0.17, 0.72)
		)
	)
	row.add_theme_stylebox_override(
		&"hover",
		_make_row_style(
			Color(0.10, 0.075, 0.08, 0.94),
			Color(0.86, 0.57, 0.25, 1.0)
		)
	)
	row.add_theme_stylebox_override(
		&"pressed",
		_make_row_style(
			Color(0.16, 0.11, 0.07, 0.96),
			Color(1.0, 0.72, 0.30, 1.0)
		)
	)


func _make_row_style(
	background_color: Color,
	border_color: Color
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color

	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1

	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3

	style.content_margin_left = 7.0
	style.content_margin_right = 5.0

	return style


func _place_panel() -> void:
	var hud := get_parent() as Control
	if hud == null:
		return

	size = PANEL_SIZE
	position = Vector2(
		hud.size.x - PANEL_SIZE.x - RIGHT_MARGIN,
		hud.size.y - PANEL_SIZE.y - BOTTOM_CLEARANCE
	)
