extends VBoxContainer
## Quest log (Character → Quests tab). Split view: quest list on the left,
## selected-quest details on the right with a pinned Track/Untrack button.
## Replaces the older list-only + modal-popup design.

## Latest quest data from the server.
var _quests: Array
var _selected_id: int
## While set, the server ships the WHOLE quest catalog (not just this
## character's), so the list can show a "Not Started" section — every quest in
## the game, including ones the player has never met the giver for.
var _show_all: bool = false

# Layout, built once in _ready.
var _list_vbox: VBoxContainer
var _show_all_button: Button
var _detail_title: Label
var _track_button: Button
var _detail_body: QuestDetailBody
var _row_buttons: Dictionary[int, Button]


func _ready() -> void:
	_build_layout()
	visibility_changed.connect(_on_visibility_changed)
	ClientState.tracked_quest_changed.connect(func(_id: int): _refresh())
	Client.subscribe(&"quest.update", func(_data: Dictionary): _refresh())
	_refresh()


func _build_layout() -> void:
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override(&"separation", 12)
	add_child(hbox)

	# Left: quest list, under a toggle that folds in the unstarted ones.
	var left_col: VBoxContainer = VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.size_flags_stretch_ratio = 0.85
	left_col.add_theme_constant_override(&"separation", 6)
	hbox.add_child(left_col)

	_show_all_button = Button.new()
	_show_all_button.toggle_mode = true
	_show_all_button.text = "Show Not Started"
	_show_all_button.custom_minimum_size = Vector2(0, 34)
	_show_all_button.tooltip_text = (
		"List every quest in the game, including ones you haven't picked up."
	)
	_show_all_button.toggled.connect(_on_show_all_toggled)
	left_col.add_child(_show_all_button)

	var left_scroll: ScrollContainer = ScrollContainer.new()
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_col.add_child(left_scroll)

	_list_vbox = VBoxContainer.new()
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_vbox.add_theme_constant_override(&"separation", 4)
	left_scroll.add_child(_list_vbox)

	# Right: details column. Header (title + track) pinned, body scrolls.
	var right_col: VBoxContainer = VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.size_flags_stretch_ratio = 1.3
	right_col.add_theme_constant_override(&"separation", 8)
	hbox.add_child(right_col)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 8)
	right_col.add_child(header)

	_detail_title = Label.new()
	_detail_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_title.add_theme_font_size_override(&"font_size", 18)
	_detail_title.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.75))
	_detail_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_detail_title)

	_track_button = Button.new()
	_track_button.custom_minimum_size = Vector2(96, 36)
	_track_button.visible = false
	header.add_child(_track_button)

	var body_scroll: ScrollContainer = ScrollContainer.new()
	body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_col.add_child(body_scroll)

	# Shared with the quest-giver menu — description / objectives / rewards
	# render identically in both quest screens by construction.
	_detail_body = QuestDetailBody.new()
	body_scroll.add_child(_detail_body)


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_refresh()


func _on_show_all_toggled(pressed: bool) -> void:
	_show_all = pressed
	_show_all_button.text = "Hide Not Started" if pressed else "Show Not Started"
	_refresh()


func _refresh() -> void:
	if not is_visible_in_tree():
		return
	Client.request_data(
		&"quest.list", _on_received, {"all": _show_all}, InstanceClient.current.name
	)


func _on_received(data: Dictionary) -> void:
	_quests = data.get("quests", [])
	# Keep the current selection if it still exists; else pick a sensible
	# default (tracked quest first, then the first active one).
	if _selected_id == 0 or _find_quest(_selected_id).is_empty():
		_selected_id = _default_selection()
	_rebuild_list()
	_rebuild_detail()


func _default_selection() -> int:
	if ClientState.tracked_quest_id > 0 and not _find_quest(ClientState.tracked_quest_id).is_empty():
		return ClientState.tracked_quest_id
	for quest: Dictionary in _quests:
		if str(quest.get("state", "")) == "active":
			return int(quest.get("id", 0))
	if not _quests.is_empty():
		return int(_quests[0].get("id", 0))
	return 0


# --- List ---

func _rebuild_list() -> void:
	for child in _list_vbox.get_children():
		child.queue_free()
	_row_buttons.clear()

	var active: Array = []
	var done: Array = []
	var not_started: Array = []
	for quest: Dictionary in _quests:
		match str(quest.get("state", "")):
			"active":
				active.append(quest)
			"turned_in":
				done.append(quest)
			_:
				not_started.append(quest)
	# Catalog order is registry order (arbitrary); sort the browse list by name
	# so the same quest sits in the same place every time it's opened.
	not_started.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")).nocasecmp_to(str(b.get("name", ""))) < 0)

	if active.is_empty() and done.is_empty() and not_started.is_empty():
		var empty: Label = Label.new()
		empty.text = "No quests yet."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.modulate.a = 0.55
		_list_vbox.add_child(empty)
		return

	if not active.is_empty():
		_list_vbox.add_child(_make_header("Active"))
		for quest: Dictionary in active:
			_add_row(quest, true)
	if not done.is_empty():
		_list_vbox.add_child(_make_header("Completed"))
		for quest: Dictionary in done:
			_add_row(quest, false)
	if not not_started.is_empty():
		_list_vbox.add_child(_make_header("Not Started (%d)" % not_started.size()))
		for quest: Dictionary in not_started:
			_add_unstarted_row(quest)

	# Touch/mouse drag-to-scroll for the quest list.
	DragScroll.enable(_list_vbox.get_parent() as ScrollContainer)


func _make_header(text: String) -> Label:
	var header: Label = Label.new()
	header.text = text
	header.add_theme_font_size_override(&"font_size", 13)
	header.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.5))
	return header


func _add_row(quest: Dictionary, is_active: bool) -> void:
	var quest_id: int = int(quest.get("id", 0))
	var button: Button = Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.toggle_mode = true
	button.button_pressed = (quest_id == _selected_id)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 38)
	button.text = str(quest.get("name", "?"))
	if not is_active:
		button.text += "  ✓"
		button.add_theme_color_override(&"font_color", Color(0.6, 0.75, 0.6))
	button.pressed.connect(_select_quest.bind(quest_id))
	_list_vbox.add_child(button)
	_row_buttons[quest_id] = button


## A quest the player hasn't picked up: same row, plus the gate that's currently
## in the way (level / skill / an earlier quest in the chain) so the list reads
## as "what's next", not just "what exists".
func _add_unstarted_row(quest: Dictionary) -> void:
	var quest_id: int = int(quest.get("id", 0))
	var locked: bool = (
		not bool(quest.get("meets_prereq", true))
		or not bool(quest.get("meets_level", true))
		or not bool(quest.get("meets_skill", true))
	)
	var button: Button = Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.toggle_mode = true
	button.button_pressed = (quest_id == _selected_id)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 38)
	button.clip_text = true
	button.text = str(quest.get("name", "?"))
	var tag: String = _lock_tag(quest)
	if not tag.is_empty():
		button.text += "   ·  " + tag
	button.add_theme_color_override(
		&"font_color",
		Color(0.7, 0.5, 0.5) if locked else Color(0.85, 0.87, 0.92),
	)
	button.pressed.connect(_select_quest.bind(quest_id))
	_list_vbox.add_child(button)
	_row_buttons[quest_id] = button


## Shortest honest reason a quest isn't available yet. Chain lock outranks the
## level chip — "do the earlier quest" is the actionable half. Mirrors the
## quest-giver menu's tags so the two screens agree.
func _lock_tag(quest: Dictionary) -> String:
	if not bool(quest.get("meets_prereq", true)):
		return "LOCKED"
	if not bool(quest.get("meets_level", true)):
		return "LV %d" % int(quest.get("min_level", 0))
	if not bool(quest.get("meets_skill", true)):
		return str(quest.get("skill_req", "")).to_upper()
	return "AVAILABLE"


func _select_quest(quest_id: int) -> void:
	_selected_id = quest_id
	for qid in _row_buttons:
		_row_buttons[qid].button_pressed = (qid == quest_id)
	_rebuild_detail()


# --- Detail ---

func _rebuild_detail() -> void:
	var quest: Dictionary = _find_quest(_selected_id)
	if quest.is_empty():
		_detail_title.text = ""
		_track_button.visible = false
		_detail_body.clear()
		var hint: Label = Label.new()
		hint.text = "Select a quest on the left."
		hint.modulate.a = 0.55
		_detail_body.add_child(hint)
		return

	var is_active: bool = str(quest.get("state", "")) == "active"
	_detail_title.text = str(quest.get("name", "?"))

	# Track / Untrack — only for active quests.
	_track_button.visible = is_active
	if is_active:
		var quest_id: int = int(quest.get("id", 0))
		for conn in _track_button.pressed.get_connections():
			_track_button.pressed.disconnect(conn["callable"])
		if ClientState.tracked_quest_id == quest_id:
			_track_button.text = "Untrack"
			_track_button.pressed.connect(func(): ClientState.set_tracked_quest(-1))
		else:
			_track_button.text = "Track"
			_track_button.pressed.connect(func(): ClientState.set_tracked_quest(quest_id))

	# Description / objectives / rewards — shared renderer (QuestDetailBody),
	# identical to the giver menu by construction.
	_detail_body.render(quest)


func _find_quest(quest_id: int) -> Dictionary:
	for quest: Dictionary in _quests:
		if int(quest.get("id", 0)) == quest_id:
			return quest
	return {}
