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

var _quests: Array = []
var _selected_id: int = 0
var _showing_completed: bool = false

var _list_view: VBoxContainer
var _quest_list: VBoxContainer
var _detail_view: VBoxContainer
var _detail_title: Label
var _detail_body: VBoxContainer
var _track_button: Button
var _active_tab: Button
var _completed_tab: Button
var _tab_group := ButtonGroup.new()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE

	content.add_theme_constant_override(&"margin_left", 6)
	content.add_theme_constant_override(&"margin_right", 6)

	header_spacer.hide()
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.text = "Quests"

	for child: Node in content.get_children():
		content.remove_child(child)
		child.queue_free()

	_build_layout()

	close_button.pressed.connect(hide)
	visibility_changed.connect(_on_visibility_changed)

	ClientState.tracked_quest_changed.connect(
		_on_tracked_quest_changed
	)
	Client.subscribe(&"quest.update", _on_quest_update)

	var hud := get_parent() as Control
	if hud != null:
		hud.resized.connect(_place_panel)

	call_deferred(&"_place_panel")
	hide()


func _build_layout() -> void:
	var root := Control.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(root)

	_build_list_view(root)
	_build_detail_view(root)

	_show_list()


func _build_list_view(root: Control) -> void:
	_list_view = VBoxContainer.new()
	_list_view.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	_list_view.add_theme_constant_override(&"separation", 5)
	root.add_child(_list_view)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override(&"separation", 4)
	_list_view.add_child(tabs)

	_active_tab = Button.new()
	_active_tab.text = "Active"
	_active_tab.toggle_mode = true
	_active_tab.button_group = _tab_group
	_active_tab.button_pressed = true
	_active_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_active_tab.custom_minimum_size = Vector2(0.0, 25.0)
	_active_tab.add_theme_font_size_override(&"font_size", 9)
	_active_tab.pressed.connect(_show_active_quests)
	tabs.add_child(_active_tab)

	_completed_tab = Button.new()
	_completed_tab.text = "Completed"
	_completed_tab.toggle_mode = true
	_completed_tab.button_group = _tab_group
	_completed_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_completed_tab.custom_minimum_size = Vector2(0.0, 25.0)
	_completed_tab.add_theme_font_size_override(&"font_size", 9)
	_completed_tab.pressed.connect(_show_completed_quests)
	tabs.add_child(_completed_tab)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = (
		ScrollContainer.SCROLL_MODE_DISABLED
	)
	_list_view.add_child(scroll)

	_quest_list = VBoxContainer.new()
	_quest_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quest_list.add_theme_constant_override(&"separation", 3)
	scroll.add_child(_quest_list)


func _build_detail_view(root: Control) -> void:
	_detail_view = VBoxContainer.new()
	_detail_view.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	_detail_view.add_theme_constant_override(&"separation", 5)
	root.add_child(_detail_view)

	var back_button := Button.new()
	back_button.text = "‹ Quest List"
	back_button.custom_minimum_size = Vector2(0.0, 24.0)
	back_button.add_theme_font_size_override(&"font_size", 9)
	back_button.pressed.connect(_show_list)
	_detail_view.add_child(back_button)

	_detail_title = Label.new()
	_detail_title.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_detail_title.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
	)
	_detail_title.add_theme_font_size_override(&"font_size", 11)
	_detail_title.add_theme_color_override(
		&"font_color",
		Color(1.0, 0.88, 0.55)
	)
	_detail_view.add_child(_detail_title)

	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = (
		ScrollContainer.SCROLL_MODE_DISABLED
	)
	_detail_view.add_child(detail_scroll)

	_detail_body = VBoxContainer.new()
	_detail_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_body.add_theme_constant_override(&"separation", 4)
	detail_scroll.add_child(_detail_body)

	_track_button = Button.new()
	_track_button.text = "Track"
	_track_button.custom_minimum_size = Vector2(0.0, 25.0)
	_track_button.add_theme_font_size_override(&"font_size", 9)
	_track_button.pressed.connect(_toggle_tracking)
	_detail_view.add_child(_track_button)


func _on_visibility_changed() -> void:
	if visible:
		_refresh()


func _on_quest_update(_data: Dictionary) -> void:
	if visible:
		_refresh()


func _on_tracked_quest_changed(_quest_id: int) -> void:
	if visible:
		_rebuild_quest_list()

		if _detail_view.visible:
			_rebuild_detail()


func _refresh() -> void:
	if not visible:
		return

	if InstanceClient.current == null:
		return

	Client.request_data(
		&"quest.list",
		_on_quests_received,
		{},
		InstanceClient.current.name
	)


func _on_quests_received(data: Dictionary) -> void:
	_quests = data.get("quests", [])

	if (
		_selected_id > 0
		and _find_quest(_selected_id).is_empty()
	):
		_selected_id = 0
		_show_list()

	_rebuild_quest_list()

	if _detail_view.visible:
		_rebuild_detail()


func _show_active_quests() -> void:
	_showing_completed = false
	_active_tab.button_pressed = true
	_completed_tab.button_pressed = false
	_rebuild_quest_list()


func _show_completed_quests() -> void:
	_showing_completed = true
	_active_tab.button_pressed = false
	_completed_tab.button_pressed = true
	_rebuild_quest_list()


func _show_list() -> void:
	_detail_view.hide()
	_list_view.show()
	title_label.text = "Quests"


func _show_detail(quest_id: int) -> void:
	_selected_id = quest_id
	_list_view.hide()
	_detail_view.show()
	title_label.text = "Quest"
	_rebuild_detail()


func _rebuild_quest_list() -> void:
	for child: Node in _quest_list.get_children():
		_quest_list.remove_child(child)
		child.queue_free()

	var expected_state: String = (
		"turned_in" if _showing_completed else "active"
	)
	var visible_count: int = 0

	for quest: Dictionary in _quests:
		if str(quest.get("state", "")) != expected_state:
			continue

		_quest_list.add_child(_make_quest_row(quest))
		visible_count += 1

	if visible_count == 0:
		var empty := Label.new()
		empty.text = (
			"No completed quests."
			if _showing_completed
			else "No active quests."
		)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override(&"font_size", 9)
		empty.add_theme_color_override(
			&"font_color",
			Color(0.62, 0.64, 0.70)
		)
		_quest_list.add_child(empty)


func _make_quest_row(quest: Dictionary) -> Button:
	var quest_id: int = int(quest.get("id", 0))
	var quest_name: String = str(quest.get("name", "?"))
	var state: String = str(quest.get("state", ""))

	var row := Button.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size = Vector2(0.0, 29.0)
	row.focus_mode = Control.FOCUS_NONE
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_theme_font_size_override(&"font_size", 9)
	row.tooltip_text = quest_name

	if state == "turned_in":
		row.text = "✓  " + quest_name
	elif ClientState.tracked_quest_id == quest_id:
		row.text = "◆  " + quest_name
	else:
		row.text = quest_name

	_apply_row_styles(row)
	row.pressed.connect(_show_detail.bind(quest_id))

	return row


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


func _rebuild_detail() -> void:
	for child: Node in _detail_body.get_children():
		_detail_body.remove_child(child)
		child.queue_free()

	var quest: Dictionary = _find_quest(_selected_id)
	if quest.is_empty():
		_show_list()
		return

	_detail_title.text = str(quest.get("name", "?"))

	var description := Label.new()
	description.text = str(quest.get("description", ""))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_size_override(&"font_size", 8)
	description.add_theme_color_override(
		&"font_color",
		Color(0.72, 0.76, 0.84)
	)
	_detail_body.add_child(description)

	var objective_header := Label.new()
	objective_header.text = "Objectives"
	objective_header.add_theme_font_size_override(&"font_size", 9)
	objective_header.add_theme_color_override(
		&"font_color",
		Color(1.0, 0.84, 0.48)
	)
	_detail_body.add_child(objective_header)

	for objective: Dictionary in quest.get("objectives", []):
		_detail_body.add_child(
			_make_objective_label(objective)
		)

	var rewards_text: String = _reward_text(quest)
	if not rewards_text.is_empty():
		var rewards := Label.new()
		rewards.text = rewards_text
		rewards.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rewards.add_theme_font_size_override(&"font_size", 8)
		rewards.add_theme_color_override(
			&"font_color",
			Color(0.76, 0.86, 0.58)
		)
		_detail_body.add_child(rewards)

	var is_active: bool = (
		str(quest.get("state", "")) == "active"
	)
	_track_button.visible = is_active

	if is_active:
		_track_button.text = (
			"Untrack"
			if ClientState.tracked_quest_id == _selected_id
			else "Track Quest"
		)


func _make_objective_label(objective: Dictionary) -> Label:
	var count: int = int(objective.get("count", 0))
	var required: int = int(objective.get("required", 1))
	var complete: bool = count >= required
	var objective_text: String = str(
		objective.get("desc", "Objective")
	)

	if bool(objective.get("countable", true)):
		objective_text += "  %d/%d" % [count, required]

	var label := Label.new()
	label.text = (
		"✓ " + objective_text
		if complete
		else "• " + objective_text
	)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", 8)
	label.add_theme_color_override(
		&"font_color",
		Color(0.60, 0.82, 0.62)
		if complete
		else Color(0.82, 0.82, 0.86)
	)

	return label


func _reward_text(quest: Dictionary) -> String:
	var rewards := PackedStringArray()

	var reward_xp: int = int(quest.get("reward_xp", 0))
	var reward_gold: int = int(quest.get("reward_gold", 0))

	if reward_xp > 0:
		rewards.append("%d XP" % reward_xp)

	if reward_gold > 0:
		rewards.append("%d Gold" % reward_gold)

	for reward: Dictionary in quest.get("reward_items", []):
		var reward_name: String = str(
			reward.get("name", "Item")
		)
		var amount: int = int(reward.get("amount", 1))

		rewards.append("%s ×%d" % [reward_name, amount])

	if rewards.is_empty():
		return ""

	return "Rewards: " + ", ".join(rewards)


func _toggle_tracking() -> void:
	if _selected_id <= 0:
		return

	if ClientState.tracked_quest_id == _selected_id:
		ClientState.set_tracked_quest(-1)
	else:
		ClientState.set_tracked_quest(_selected_id)


func _find_quest(quest_id: int) -> Dictionary:
	for quest: Dictionary in _quests:
		if int(quest.get("id", 0)) == quest_id:
			return quest

	return {}


func _place_panel() -> void:
	var hud := get_parent() as Control
	if hud == null:
		return

	size = PANEL_SIZE
	position = Vector2(
		hud.size.x - PANEL_SIZE.x - RIGHT_MARGIN,
		hud.size.y - PANEL_SIZE.y - BOTTOM_CLEARANCE
	)
