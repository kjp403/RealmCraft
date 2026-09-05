extends MenuShell
## Personal bank vault. Left = bag, right = vault behind a category tab rail.
##
## Both panes behave IDENTICALLY: click selects, the amount row (1 / 5 / 10 /
## All / X) applies to whatever is selected, and the transfer button flips
## between Deposit and Withdraw. The old menu only gave the vault side an
## amount — bag clicks either banked one item or banked a whole stack — which
## is why "you can't deposit X or Max" was true from the player's chair even
## though the spinner was on screen.
##
## Tabs and sorting are pure VIEW state (see [BankOrder]): the server keeps
## sending one flat vault dictionary, the menu decides how to show it. Gold is
## never a vault stack — it lives in the pouch chip in the header.


## Sentinel tab that shows every vault stack. Sits outside [enum Item.InventoryTab].
const TAB_ALL: int = -1
## Tab rail in render order: [id, label]. Derived from Item.inventory_tab(), so a
## new item category lands in the right tab with no work here.
const TABS: Array[Array] = [
	[TAB_ALL, "All"],
	[Item.InventoryTab.WEAPON, "Weapons"],
	[Item.InventoryTab.ARMOR, "Armor"],
	[Item.InventoryTab.CONSUMABLE, "Consumables"],
	[Item.InventoryTab.MATERIAL, "Materials"],
	[Item.InventoryTab.QUEST, "Quest"],
	[Item.InventoryTab.OTHER, "Misc"],
]

const BAG_COLUMNS: int = 6
const VAULT_COLUMNS: int = 11
## The bag pane is exactly six 44px columns plus chrome — it never earns more, so
## it takes a fixed width and the vault pane absorbs the rest of the card. Sharing
## the width by ratio instead left the vault at eight columns and clipped the last
## two tabs off the rail.
const BAG_PANE_WIDTH: float = 302.0
## 44 not 48: eight vault columns + six bag columns + chrome still has to fit the
## 960×540 client without the card clipping Close or the transfer row.
const SLOT_SIZE: Vector2 = Vector2(44, 44)
## Quantity chips, shared by both directions. -1 = "All" (as much as will move).
const QUANTITY_CHIPS: Array[Array] = [[1, "1"], [5, "5"], [10, "10"], [-1, "All"]]

const COL_TEXT: Color = Color(0.90, 0.92, 0.96)
const COL_MUTED: Color = Color(0.58, 0.61, 0.70)
const COL_ACCENT: Color = Color(0.93, 0.80, 0.52)
const COL_GOLD: Color = Color(1.0, 0.85, 0.45)
const COL_PANEL: Color = Color(0.075, 0.085, 0.115, 0.98)
const COL_INNER: Color = Color(0.105, 0.115, 0.155, 1.0)
const COL_LINE: Color = Color(0.24, 0.26, 0.34, 1.0)
const COL_SLOT: Color = Color(0.145, 0.155, 0.205, 1.0)
const COL_SLOT_EMPTY: Color = Color(0.095, 0.10, 0.135, 1.0)

## Slot frame tint per category. Doubles as the tab rail's underline colour, so a
## stack's frame tells you which tab it lives in without reading the label.
const TAB_ACCENTS: Dictionary = {
	Item.InventoryTab.WEAPON: Color(0.89, 0.44, 0.38),
	Item.InventoryTab.ARMOR: Color(0.46, 0.67, 0.93),
	Item.InventoryTab.CONSUMABLE: Color(0.48, 0.83, 0.56),
	Item.InventoryTab.MATERIAL: Color(0.91, 0.73, 0.37),
	Item.InventoryTab.QUEST: Color(0.75, 0.56, 0.95),
	Item.InventoryTab.OTHER: Color(0.63, 0.67, 0.77),
}

var _inventory: Dictionary = {}
var _bank: Dictionary = {}
var _bank_slots: int = BankInteraction.STARTING_SLOTS
var _inventory_bags: int = 1
var _active_bag: int = 0
var _busy: bool = false
var _gold_id: int = 0

var _tab: int = TAB_ALL
var _sort: BankOrder.Sort = BankOrder.Sort.CUSTOM

var _bag_grid: GridContainer
var _vault_grid: GridContainer
var _bag_count: Label
var _vault_count: Label
var _capacity_bar: ProgressBar
var _capacity_label: Label
var _gold_label: Label
## Hoverable shell around [member _gold_label] — holds the exact-balance tooltip.
var _gold_pouch: Control
var _upgrade_button: Button
var _upgrade_count_spin: SpinBox
var _upgrade_x_button: Button
var _sort_picker: OptionButton
var _deposit_all_button: Button
var _search_field: LineEdit
var _tab_buttons: Dictionary = {}
var _tab_group: ButtonGroup = ButtonGroup.new()

var _selection_icon: TextureRect
var _selection_name: Label
var _selection_where: Label
var _amount_spin: SpinBox
var _transfer_button: Button
## The 1 / 5 / 10 / All chips plus the X button — every control that only means
## something with a stack selected, so they can be disabled as one group. A
## button that silently no-ops is exactly how "Deposit X does nothing" reads.
var _amount_controls: Array[Button] = []

var _selected_uid: int = -1
var _selected_from_bag: bool = true
var _selected_item_id: int = 0
var _selected_name: String = ""
var _selected_icon: Texture2D = null


func _ready() -> void:
	_gold_id = Economy.gold_id()
	_sort = BankOrder.load_sort()
	_tab = BankOrder.load_tab(TAB_ALL)
	build_shell("Bank", null, true)
	if backdrop != null:
		backdrop.color = Color(0.03, 0.04, 0.06, 0.86)
	_style_card()
	_build_header_extras()
	_build_body()
	visibility_changed.connect(func() -> void:
		if visible:
			if _search_field != null:
				_search_field.text = ""
			_refresh())
	_refresh.call_deferred()


func open(_arg: Variant = null) -> void:
	if _search_field != null:
		_search_field.text = ""
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_close_pressed()


# --- Chrome -----------------------------------------------------------------


## The fullscreen MenuShell deliberately drops its card frame; the vault needs one
## back, or the grids sit unreadable straight on a bright outdoor scene.
func _style_card() -> void:
	var node: Node = content
	var card: PanelContainer = null
	while node != null:
		if node is PanelContainer:
			card = node as PanelContainer
			break
		node = node.get_parent()
	if card != null:
		card.add_theme_stylebox_override(&"panel", _panel_style(COL_PANEL, COL_LINE, 12))
		card.clip_contents = true
	# Tighten the shell's outer margins — the tab rail and transfer bar are new
	# vertical chrome, and 540px of client height has none to spare.
	for child: Node in get_children():
		if child is MarginContainer and child != content:
			var margin: MarginContainer = child as MarginContainer
			margin.add_theme_constant_override(&"margin_left", 10)
			margin.add_theme_constant_override(&"margin_right", 10)
			margin.add_theme_constant_override(&"margin_top", 10)
			margin.add_theme_constant_override(&"margin_bottom", 12)
			break


## Carved 9-slice, not a rounded flat panel. The signature is kept so the five
## call sites read unchanged; `bg`/`radius`/`border_width` are now decorative
## history — the frame texture carries all of that — and only the border COLOUR
## still does anything, as a modulate over the iron frame.
func _panel_style(_bg: Color, border: Color, _radius: int, _border_width: int = 1) -> StyleBoxTexture:
	var style: StyleBoxTexture = PixelUI.frame("frame_iron", 8)
	# COL_LINE and friends are near-neutral; modulating by them keeps each panel's
	# existing tint relationship without reintroducing a vector border.
	if border != Color.BLACK:
		style.modulate_color = Color(border.r + 0.55, border.g + 0.55, border.b + 0.55, 1.0)
	return style


## Gold pouch chip + a search box that filters BOTH panes, dropped into the shell
## header beside Close.
func _build_header_extras() -> void:
	_search_field = LineEdit.new()
	_search_field.placeholder_text = "Search bag and vault…"
	_search_field.clear_button_enabled = true
	_search_field.custom_minimum_size = Vector2(200, 30)
	# Without this the field stretches to the header bar's full height.
	_search_field.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_search_field.add_theme_font_size_override(&"font_size", 13)
	_search_field.caret_blink = true
	_search_field.text_changed.connect(func(_t: String) -> void: _rebuild_grids())
	header_center.add_child(_search_field)

	var pouch := PanelContainer.new()
	pouch.add_theme_stylebox_override(&"panel", _panel_style(COL_INNER, COL_LINE, 8))
	pouch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# The Label ignores the mouse, so the pouch shell carries the exact-balance
	# tooltip — see _set_gold_display().
	pouch.mouse_filter = Control.MOUSE_FILTER_STOP
	_gold_pouch = pouch
	var pouch_row := HBoxContainer.new()
	pouch_row.add_theme_constant_override(&"separation", 6)
	pouch.add_child(pouch_row)
	var gold_icon := TextureRect.new()
	# EXPAND_IGNORE_SIZE is the whole fix: without it a TextureRect reports the
	# full texture as its minimum size, custom_minimum_size is ignored, and the
	# coin draws at its native art resolution — a 45px coin in a 30px header.
	gold_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gold_icon.custom_minimum_size = Vector2(18, 18)
	gold_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gold_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gold_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var gold: Item = ContentRegistryHub.load_by_id(&"items", _gold_id) as Item
	if gold != null:
		gold_icon.texture = gold.item_icon
	pouch_row.add_child(gold_icon)
	_gold_label = Label.new()
	# font_color is owned by _set_gold_display() — it grades with the balance.
	_gold_label.add_theme_font_size_override(&"font_size", 14)
	_gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_gold_label.clip_text = false
	_gold_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	pouch_row.add_child(_gold_label)
	_set_gold_display(0)
	header_right.add_child(pouch)
	header_right.move_child(pouch, 0)


func _build_body() -> void:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override(&"separation", 8)
	content.add_child(root)

	var sides := HBoxContainer.new()
	sides.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sides.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sides.add_theme_constant_override(&"separation", 8)
	root.add_child(sides)
	sides.add_child(_build_bag_pane())
	sides.add_child(_build_vault_pane())

	root.add_child(_build_transfer_bar())
	root.add_child(_build_hint_bar())


func _pane_shell(fixed_width: float) -> PanelContainer:
	var pane := PanelContainer.new()
	pane.add_theme_stylebox_override(&"panel", _panel_style(COL_INNER, COL_LINE, 10))
	pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if fixed_width > 0.0:
		pane.custom_minimum_size = Vector2(fixed_width, 0)
		pane.size_flags_horizontal = Control.SIZE_FILL
	else:
		pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return pane


func _pane_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override(&"font_color", COL_ACCENT)
	label.add_theme_font_size_override(&"font_size", 14)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _count_label() -> Label:
	var label := Label.new()
	label.add_theme_color_override(&"font_color", COL_MUTED)
	label.add_theme_font_size_override(&"font_size", 12)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _build_bag_pane() -> PanelContainer:
	var pane: PanelContainer = _pane_shell(BAG_PANE_WIDTH)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	pane.add_child(col)

	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 6)
	col.add_child(header)
	header.add_child(_pane_title("YOUR BAG"))
	_bag_count = _count_label()
	header.add_child(_bag_count)
	col.add_child(_rule())

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Never let the grid's own height set the card's minimum — that is what used
	# to push the shell past 540px and crop the title and Close button.
	scroll.custom_minimum_size = Vector2(0, 80)
	col.add_child(scroll)
	DragScroll.enable(scroll)
	_bag_grid = GridContainer.new()
	_bag_grid.columns = BAG_COLUMNS
	_bag_grid.add_theme_constant_override(&"h_separation", 4)
	_bag_grid.add_theme_constant_override(&"v_separation", 4)
	_bag_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	scroll.add_child(_bag_grid)

	_deposit_all_button = Button.new()
	_deposit_all_button.text = "Deposit All"
	_deposit_all_button.focus_mode = Control.FOCUS_NONE
	_deposit_all_button.custom_minimum_size = Vector2(0, 28)
	_deposit_all_button.add_theme_font_size_override(&"font_size", 13)
	_deposit_all_button.tooltip_text = "Move every bag item into the vault. Gold stays in your pouch."
	_deposit_all_button.pressed.connect(_on_deposit_all_pressed)
	col.add_child(_deposit_all_button)
	return pane


func _build_vault_pane() -> PanelContainer:
	var pane: PanelContainer = _pane_shell(0.0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	pane.add_child(col)

	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 6)
	col.add_child(header)
	header.add_child(_pane_title("BANK VAULT"))
	_vault_count = _count_label()
	header.add_child(_vault_count)
	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_spacer)
	_upgrade_count_spin = SpinBox.new()
	_upgrade_count_spin.min_value = 1
	_upgrade_count_spin.max_value = BankInteraction.MAX_UPGRADE_COUNT
	_upgrade_count_spin.value = 1
	_upgrade_count_spin.rounded = true
	_upgrade_count_spin.custom_minimum_size = Vector2(72, 28)
	_upgrade_count_spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_upgrade_count_spin.tooltip_text = "How many slot packs to buy at once"
	var upgrade_spin_edit: LineEdit = _upgrade_count_spin.get_line_edit()
	upgrade_spin_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	upgrade_spin_edit.select_all_on_focus = true
	upgrade_spin_edit.text_submitted.connect(func(_text: String) -> void:
		_on_upgrade_pressed())
	_upgrade_count_spin.value_changed.connect(func(_v: float) -> void:
		_sync_upgrade_controls())
	header.add_child(_upgrade_count_spin)
	_upgrade_x_button = Button.new()
	_upgrade_x_button.text = "X"
	_upgrade_x_button.focus_mode = Control.FOCUS_NONE
	_upgrade_x_button.custom_minimum_size = Vector2(34, 28)
	_upgrade_x_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_upgrade_x_button.add_theme_font_size_override(&"font_size", 13)
	_upgrade_x_button.tooltip_text = "Type how many packs to buy, then press Enter"
	_style_chip_button(_upgrade_x_button)
	_upgrade_x_button.pressed.connect(_on_upgrade_custom_amount_pressed)
	header.add_child(_upgrade_x_button)
	_upgrade_button = Button.new()
	_upgrade_button.text = "Buy +%d" % BankInteraction.UPGRADE_SLOTS
	_upgrade_button.focus_mode = Control.FOCUS_NONE
	_upgrade_button.add_theme_font_size_override(&"font_size", 12)
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	header.add_child(_upgrade_button)

	col.add_child(_build_tab_rail())

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override(&"separation", 6)
	col.add_child(tools)
	var sort_label := Label.new()
	sort_label.text = "Sort"
	sort_label.add_theme_color_override(&"font_color", COL_MUTED)
	sort_label.add_theme_font_size_override(&"font_size", 12)
	sort_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tools.add_child(sort_label)
	_sort_picker = OptionButton.new()
	_sort_picker.focus_mode = Control.FOCUS_NONE
	_sort_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sort_picker.custom_minimum_size = Vector2(0, 26)
	_sort_picker.add_theme_font_size_override(&"font_size", 13)
	for mode: int in BankOrder.SORT_LABELS:
		_sort_picker.add_item(String(BankOrder.SORT_LABELS[mode]), mode)
	_sort_picker.item_selected.connect(_on_sort_selected)
	tools.add_child(_sort_picker)
	_sync_sort_picker()

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 80)
	col.add_child(scroll)
	DragScroll.enable(scroll)
	_vault_grid = GridContainer.new()
	_vault_grid.columns = VAULT_COLUMNS
	_vault_grid.add_theme_constant_override(&"h_separation", 4)
	_vault_grid.add_theme_constant_override(&"v_separation", 4)
	_vault_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	scroll.add_child(_vault_grid)

	col.add_child(_build_capacity_row())
	return pane


func _rule() -> Control:
	var rule := Panel.new()
	rule.custom_minimum_size = Vector2(0, 1)
	var style := StyleBoxFlat.new()
	style.bg_color = COL_LINE
	rule.add_theme_stylebox_override(&"panel", style)
	return rule


func _build_tab_rail() -> Control:
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.custom_minimum_size = Vector2(0, 28)
	var rail := HBoxContainer.new()
	rail.add_theme_constant_override(&"separation", 3)
	scroll.add_child(rail)
	for entry: Array in TABS:
		var id: int = int(entry[0])
		var button := Button.new()
		button.text = String(entry[1])
		button.toggle_mode = true
		button.button_group = _tab_group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, 24)
		button.add_theme_font_size_override(&"font_size", 12)
		_style_tab_button(button, _accent_for_tab(id))
		button.pressed.connect(_on_tab_pressed.bind(id))
		rail.add_child(button)
		_tab_buttons[id] = button
	return scroll


## Flat chips with a coloured underline when active — the tab's colour is the same
## one its stacks are framed in, so the rail reads as a legend too.
## Tab rail chrome, now the shared pixel tab style: transparent at rest, a filled
## square on hover, an accent underline when active. The tab's colour is the same
## one its stacks are framed in, so the rail reads as a legend too.
##
## Deliberately the LIGHT half of the chrome hierarchy rather than a carved
## frame — eight carved boxes in a row above the grid would fight the panels
## beneath them and read as clutter. See PixelUI.tab_button.
func _style_tab_button(button: Button, accent: Color) -> void:
	PixelUI.tab_button(button, accent)


func _build_capacity_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	_capacity_bar = ProgressBar.new()
	_capacity_bar.show_percentage = false
	_capacity_bar.custom_minimum_size = Vector2(0, 8)
	_capacity_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_capacity_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	PixelUI.progress_bar(_capacity_bar, COL_ACCENT, 10)
	row.add_child(_capacity_bar)
	_capacity_label = Label.new()
	_capacity_label.add_theme_color_override(&"font_color", COL_MUTED)
	_capacity_label.add_theme_font_size_override(&"font_size", 11)
	row.add_child(_capacity_label)
	return row


## The one row both directions share. Everything in it acts on the current
## selection, whichever pane it came from — that symmetry IS the fix.
func _build_transfer_bar() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override(&"panel", _panel_style(COL_INNER, COL_LINE, 10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	bar.add_child(row)

	_selection_icon = TextureRect.new()
	_selection_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_selection_icon.custom_minimum_size = Vector2(30, 30)
	_selection_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_selection_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_selection_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_selection_icon)

	var names := VBoxContainer.new()
	names.add_theme_constant_override(&"separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(names)
	_selection_name = Label.new()
	_selection_name.clip_text = true
	_selection_name.add_theme_color_override(&"font_color", COL_TEXT)
	_selection_name.add_theme_font_size_override(&"font_size", 13)
	names.add_child(_selection_name)
	_selection_where = Label.new()
	_selection_where.clip_text = true
	_selection_where.add_theme_color_override(&"font_color", COL_MUTED)
	_selection_where.add_theme_font_size_override(&"font_size", 11)
	names.add_child(_selection_where)

	for chip: Array in QUANTITY_CHIPS:
		var value: int = int(chip[0])
		var button := Button.new()
		button.text = String(chip[1])
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(38, 30)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.add_theme_font_size_override(&"font_size", 13)
		_style_chip_button(button)
		button.tooltip_text = (
			"Move as many as will fit"
			if value < 0
			else "Move %d" % value
		)
		button.pressed.connect(_on_chip_pressed.bind(value))
		row.add_child(button)
		_amount_controls.append(button)

	_amount_spin = SpinBox.new()
	_amount_spin.min_value = 1
	_amount_spin.max_value = 1
	_amount_spin.value = 1
	_amount_spin.rounded = true
	_amount_spin.custom_minimum_size = Vector2(84, 30)
	_amount_spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_amount_spin.editable = false
	# Whatever gives the field focus selects what's in it, so the first digit typed
	# REPLACES the amount instead of appending to it. Appending silently overshot the
	# stack and clamped back to "all of it" — indistinguishable from the typed amount
	# being thrown away.
	var spin_edit: LineEdit = _amount_spin.get_line_edit()
	spin_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var spin_box := StyleBoxFlat.new()
	spin_box.bg_color = Color(0.085, 0.095, 0.125)
	spin_box.set_border_width_all(1)
	spin_box.border_color = Color(0.30, 0.33, 0.42)
	spin_box.content_margin_left = 6
	spin_box.content_margin_right = 6
	var spin_focus := spin_box.duplicate() as StyleBoxFlat
	spin_focus.border_color = COL_GOLD
	spin_edit.add_theme_stylebox_override(&"normal", spin_box)
	spin_edit.add_theme_stylebox_override(&"read_only", spin_box)
	spin_edit.add_theme_stylebox_override(&"focus", spin_focus)
	spin_edit.select_all_on_focus = true
	# Enter is what people press after typing a number. Commit and send, rather than
	# leaving them hunting for the transfer button.
	spin_edit.text_submitted.connect(func(_text: String) -> void:
		_on_transfer_pressed())
	row.add_child(_amount_spin)

	var x_button := Button.new()
	x_button.text = "X"
	x_button.focus_mode = Control.FOCUS_NONE
	x_button.custom_minimum_size = Vector2(34, 30)
	x_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	x_button.add_theme_font_size_override(&"font_size", 13)
	x_button.tooltip_text = "Type a custom amount, then press Enter"
	_style_chip_button(x_button)
	x_button.pressed.connect(_on_custom_amount_pressed)
	row.add_child(x_button)
	_amount_controls.append(x_button)

	_transfer_button = Button.new()
	_transfer_button.text = "Transfer"
	_transfer_button.focus_mode = Control.FOCUS_NONE
	_transfer_button.disabled = true
	_transfer_button.custom_minimum_size = Vector2(124, 32)
	_transfer_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_transfer_button.add_theme_font_size_override(&"font_size", 14)
	_style_primary_button(_transfer_button)
	_transfer_button.pressed.connect(_on_transfer_pressed)
	row.add_child(_transfer_button)

	_set_amount_controls_enabled(false)
	return bar


## Quantity chips keep a visible frame even while disabled. Without one they drew
## as bare numerals with nothing around them, so at rest the whole transfer row
## read as a caption and Deposit All looked like the menu's only button.
func _style_chip_button(button: Button) -> void:
	PixelUI.button_frame(button, "frame_iron", 6)
	PixelUI.button_font(button, PixelUI.SIZE_CAPTION, PixelUI.INK)


## The one gold button in the menu — Transfer. Gold is reserved for the action
## that commits, exactly as it is on the daily board's Open Chest.
func _style_primary_button(button: Button) -> void:
	PixelUI.button_frame(button, "frame_gold", 8)
	PixelUI.button_font(button, PixelUI.SIZE_BODY, PixelUI.INK_GOLD)


func _build_hint_bar() -> Control:
	var hint := Label.new()
	hint.text = "Click a stack to select  ·  Double-click to move it  ·  Drag to rearrange  ·  Enter confirms a typed amount"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override(&"font_color", Color(0.44, 0.47, 0.56))
	hint.add_theme_font_size_override(&"font_size", 10)
	return hint


# --- Data -------------------------------------------------------------------


func _refresh() -> void:
	if InstanceClient.current == null or not visible:
		return
	var result: Array = await Client.request_data_await(
		&"bank.get",
		{},
		InstanceClient.current.name
	)
	if not is_instance_valid(self) or not visible:
		return
	if result.size() < 2 or result[1] != OK or not (result[0] is Dictionary):
		Toaster.toast("Could not open the bank.")
		return
	var payload: Dictionary = result[0]
	if not bool(payload.get("ok", false)):
		Toaster.toast("Could not open the bank.")
		return
	_apply_payload(payload)
	_clear_selection()
	_rebuild_grids()


func _apply_payload(payload: Dictionary) -> void:
	if payload.has("inventory"):
		_inventory = payload.get("inventory", {}) as Dictionary
	if payload.has("bank"):
		_bank = payload.get("bank", {}) as Dictionary
	if payload.has("inventory_bags"):
		_inventory_bags = clampi(int(payload.get("inventory_bags", 1)), 1, Inventory.MAX_BAGS)
	if payload.has("active_bag"):
		_active_bag = clampi(int(payload.get("active_bag", 0)), 0, _inventory_bags - 1)
	if payload.has("bank_slots"):
		_bank_slots = maxi(
			BankInteraction.STARTING_SLOTS,
			int(payload.get("bank_slots", _bank_slots))
		)


func _item_of(store: Dictionary, uid: int) -> Item:
	if not store.has(uid):
		return null
	return ContentRegistryHub.load_by_id(&"items", int(store[uid].get("id", 0))) as Item


## Vault/bag stacks that occupy a square. Gold is filtered out everywhere — it
## lives in the header pouch and is never a bankable stack.
func _stack_uids(store: Dictionary) -> Array:
	var uids: Array = []
	for uid: Variant in store.keys():
		var data: Dictionary = store[uid]
		if int(data.get("id", 0)) <= 0 or int(data.get("a", 0)) <= 0:
			continue
		var item: Item = ContentRegistryHub.load_by_id(&"items", int(data.get("id", 0))) as Item
		if item != null and item.is_currency:
			continue
		uids.append(int(uid))
	return uids


func _tab_of(item: Item) -> int:
	return int(item.inventory_tab()) if item != null else int(Item.InventoryTab.OTHER)


func _accent_for_tab(tab: int) -> Color:
	if tab == TAB_ALL:
		return COL_ACCENT
	return TAB_ACCENTS.get(tab, COL_MUTED)


func _query() -> String:
	if _search_field == null:
		return ""
	return _search_field.text.strip_edges().to_lower()


func _matches_query(item: Item, query: String) -> bool:
	if query.is_empty():
		return true
	if item == null:
		return false
	return String(item.item_name).to_lower().contains(query)


## Vault uids in display order. [param filtered] applies the tab + search; the
## unfiltered list is what a drag freezes into the manual order, so rearranging
## inside one tab never scrambles the stacks hidden behind the others.
func _vault_uids(filtered: bool) -> Array:
	var uids: Array = _stack_uids(_bank)
	var order: Array = BankOrder.sync_with_uids(uids)
	uids = _apply_sort(uids, _bank, order)
	if not filtered:
		return uids
	var query: String = _query()
	var out: Array = []
	for uid: Variant in uids:
		var item: Item = _item_of(_bank, int(uid))
		if _tab != TAB_ALL and _tab_of(item) != _tab:
			continue
		if not _matches_query(item, query):
			continue
		out.append(int(uid))
	return out


func _bag_uids() -> Array:
	var uids: Array = _stack_uids(_inventory)
	var order: Array = BagOrder.sync_with_entries(_bag_entries_for_order(uids))
	uids.sort_custom(func(a: Variant, b: Variant) -> bool:
		return BagOrder.index_of(order, int(a)) < BagOrder.index_of(order, int(b)))
	var query: String = _query()
	if query.is_empty():
		return uids
	var out: Array = []
	for uid: Variant in uids:
		if _matches_query(_item_of(_inventory, int(uid)), query):
			out.append(int(uid))
	return out


func _bag_entries_for_order(uids: Array) -> Array:
	var entries: Array = []
	for uid: Variant in uids:
		entries.append({"uid": int(uid)})
	return entries


## Sort key builder. Every mode falls through to name then uid so the order is
## total — two stacks that tie never swap places between rebuilds.
func _apply_sort(uids: Array, store: Dictionary, manual_order: Array) -> Array:
	var keyed: Array = []
	for uid: Variant in uids:
		var id: int = int(uid)
		var item: Item = _item_of(store, id)
		var amount: int = int(store[id].get("a", 0))
		var name_key: String = String(item.item_name).to_lower() if item != null else "~unknown"
		keyed.append({
			"uid": id,
			"name": name_key,
			"amount": amount,
			"value": (item.vendor_value if item != null else 0) * amount,
			"tab": _tab_of(item),
			"tier": _tier_of(item),
			"manual": BankOrder.index_of(manual_order, id),
		})
	var mode: BankOrder.Sort = _sort
	keyed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		match mode:
			BankOrder.Sort.NAME_DESC:
				if a["name"] != b["name"]:
					return a["name"] > b["name"]
			BankOrder.Sort.QUANTITY:
				if a["amount"] != b["amount"]:
					return a["amount"] > b["amount"]
			BankOrder.Sort.VALUE:
				if a["value"] != b["value"]:
					return a["value"] > b["value"]
			BankOrder.Sort.CATEGORY:
				if a["tab"] != b["tab"]:
					return a["tab"] < b["tab"]
			BankOrder.Sort.TIER:
				if a["tier"] != b["tier"]:
					return a["tier"] > b["tier"]
			BankOrder.Sort.CUSTOM:
				return a["manual"] < b["manual"]
		if a["name"] != b["name"]:
			return a["name"] < b["name"]
		return a["uid"] < b["uid"])
	var out: Array = []
	for entry: Dictionary in keyed:
		out.append(int(entry["uid"]))
	return out


## Rough "how endgame is this" rank for the Tier sort. Gear carries a real gate;
## everything else falls back to vendor value, which tracks material tier closely
## enough to keep runite above bronze.
func _tier_of(item: Item) -> int:
	var gear: GearItem = item as GearItem
	if gear != null:
		return maxi(gear.required_mastery_level, gear.required_level) * 1000
	return item.vendor_value if item != null else 0


# --- Rendering --------------------------------------------------------------


func _rebuild_grids() -> void:
	_rebuild_tab_rail()
	_fill_grid(_bag_grid, _inventory, _bag_uids(), true)
	_fill_grid(_vault_grid, _bank, _vault_uids(true), false)

	var bag_used: int = _stack_uids(_inventory).size()
	var vault_used: int = _stack_uids(_bank).size()
	# Capacity is per-bag x bags owned. Printing MAX_SLOTS flat showed a player
	# with two bags "56 / 28", which reads as an overflowing bag rather than a
	# miscounted header.
	_bag_count.text = "%d / %d" % [bag_used, Inventory.MAX_SLOTS * maxi(1, _inventory_bags)]
	_vault_count.text = "%d / %d" % [vault_used, _bank_slots]
	if _gold_label != null:
		_set_gold_display(Inventory.count(_inventory, _gold_id))
	if _capacity_bar != null:
		_capacity_bar.max_value = maxf(1.0, float(_bank_slots))
		_capacity_bar.value = float(vault_used)
		var used_ratio: float = float(vault_used) / maxf(1.0, float(_bank_slots))
		var fill: StyleBoxTexture = _capacity_bar.get_theme_stylebox(&"fill") as StyleBoxTexture
		if fill != null:
			# Amber past 80%, red when full: "your bank is full" should be visible
			# before a deposit bounces off it. The bar art is neutral grey, so the
			# warning colour rides modulate_color instead of a flat bg_color.
			fill.modulate_color = (
				Color(0.87, 0.36, 0.33) if used_ratio >= 0.995
				else (Color(0.93, 0.66, 0.32) if used_ratio >= 0.8 else COL_ACCENT)
			)
		_capacity_label.text = "%d free" % maxi(0, _bank_slots - vault_used)
	if _deposit_all_button != null:
		_deposit_all_button.disabled = _busy or bag_used <= 0
	_sync_upgrade_controls()
	_sync_selection_highlights()


## Rail labels carry live counts, and a tab with nothing in it disables itself
## rather than vanishing — a rail that reflows as you deposit is disorienting.
func _rebuild_tab_rail() -> void:
	var counts: Dictionary = {}
	var total: int = 0
	for uid: Variant in _stack_uids(_bank):
		var tab: int = _tab_of(_item_of(_bank, int(uid)))
		counts[tab] = int(counts.get(tab, 0)) + 1
		total += 1
	for entry: Array in TABS:
		var id: int = int(entry[0])
		var button: Button = _tab_buttons.get(id)
		if button == null:
			continue
		var count: int = total if id == TAB_ALL else int(counts.get(id, 0))
		button.text = "%s  %d" % [String(entry[1]), count]
		button.disabled = count <= 0 and id != TAB_ALL
		if button.disabled and _tab == id:
			_tab = TAB_ALL
	var active: Button = _tab_buttons.get(_tab)
	if active == null or active.disabled:
		_tab = TAB_ALL
	for id: Variant in _tab_buttons:
		(_tab_buttons[id] as Button).set_pressed_no_signal(int(id) == _tab)


func _fill_grid(grid: GridContainer, store: Dictionary, uids: Array, is_bag: bool) -> void:
	for child: Node in grid.get_children():
		child.queue_free()
	for uid: Variant in uids:
		grid.add_child(_build_slot(store, int(uid), is_bag))
	# Pad out to a full, even grid. An MMO bank that shows its empty squares reads
	# as "this is how much room you have"; a ragged last row just reads as a bug.
	var columns: int = grid.columns
	var placeholders: int = 0
	if is_bag and _query().is_empty():
		placeholders = maxi(0, Inventory.MAX_SLOTS * maxi(1, _inventory_bags) - uids.size())
	elif uids.size() % columns != 0:
		placeholders = columns - (uids.size() % columns)
	elif uids.is_empty():
		placeholders = columns
	for _i: int in placeholders:
		grid.add_child(_build_empty_slot())


func _build_empty_slot() -> Control:
	var slot := Panel.new()
	slot.custom_minimum_size = SLOT_SIZE
	# The same recessed square the inventory grid, the equipment panel and the
	# reward window use — an empty slot should not be a different shape here.
	slot.add_theme_stylebox_override(&"panel", PixelUI.slot_style())
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return slot


func _build_slot(store: Dictionary, uid: int, is_bag: bool) -> Button:
	var data: Dictionary = store[uid]
	var amount: int = int(data.get("a", 0))
	var item: Item = _item_of(store, uid)
	var accent: Color = _accent_for_tab(_tab_of(item))

	var button := Button.new()
	button.custom_minimum_size = SLOT_SIZE
	button.clip_contents = true
	button.focus_mode = Control.FOCUS_NONE
	button.toggle_mode = true
	button.set_meta(&"bank_uid", uid)
	button.set_meta(&"from_bag", is_bag)
	_style_slot_button(button, accent)
	button.set_pressed_no_signal(uid == _selected_uid and is_bag == _selected_from_bag)

	if item != null:
		PixelIcon.mount(button, item.item_icon)
		var tip: String = ItemTooltip.hover_text(item)
		tip += "\n\nClick: select  ·  Double-click: %s  ·  Drag: rearrange" % (
			"deposit" if is_bag else "withdraw"
		)
		button.tooltip_text = tip
	else:
		button.tooltip_text = "Unknown item"

	if amount > 1:
		# Display only: `amount` stays the raw count the transfer spinbox and
		# the server both work from. Past 100k the badge abbreviates, so the
		# exact figure moves into the slot tooltip.
		var stack: Dictionary = NumberFormat.format_stack_size(amount)
		var stack_color: Color = stack["color"]
		if amount >= NumberFormat.ABBREVIATE_FROM:
			button.tooltip_text += "\n\nYou have %s." % stack["exact_text"]

		var badge := Label.new()
		badge.text = stack["text"]
		# Short by design — never wrap or ellipsize the abbreviation.
		badge.clip_text = false
		badge.autowrap_mode = TextServer.AUTOWRAP_OFF
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_font_size_override(&"font_size", 11)
		badge.add_theme_color_override(&"font_color", stack_color)
		badge.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.9))
		badge.add_theme_constant_override(&"outline_size", 5)
		badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.offset_left -= 2
		badge.offset_top -= 2
		badge.offset_right -= 3
		badge.offset_bottom -= 1
		button.add_child(badge)

	button.pressed.connect(_on_stack_pressed.bind(uid, is_bag))
	button.gui_input.connect(_on_slot_gui_input.bind(uid, is_bag))
	_wire_slot_drag(button, uid, is_bag, item)
	return button


## A filled stack's square. The same recessed pixel slot the empty squares use —
## an occupied and an empty cell in one grid must not be different SHAPES — with
## the category accent carried on modulate instead of a coloured vector border.
func _style_slot_button(button: Button, accent: Color) -> void:
	var normal: StyleBoxTexture = PixelUI.slot_style()
	normal.modulate_color = Color(0.55 + accent.r, 0.55 + accent.g, 0.55 + accent.b, 1.0)
	var hover: StyleBoxTexture = PixelUI.slot_style()
	# Hover lifts the same tint rather than swapping colours, so the accent keeps
	# reading as the category legend it is.
	hover.modulate_color = Color(0.85 + accent.r, 0.85 + accent.g, 0.85 + accent.b, 1.0)
	var pressed: StyleBoxTexture = PixelUI.slot_style()
	pressed.modulate_color = Color(COL_GOLD.r + 0.5, COL_GOLD.g + 0.5, COL_GOLD.b + 0.5, 1.0)
	button.add_theme_stylebox_override(&"normal", normal)
	button.add_theme_stylebox_override(&"hover", hover)
	button.add_theme_stylebox_override(&"pressed", pressed)
	button.add_theme_stylebox_override(&"hover_pressed", pressed)
	button.add_theme_stylebox_override(&"focus", normal)


func _wire_slot_drag(button: Button, uid: int, is_bag: bool, item: Item) -> void:
	if item == null:
		return
	button.set_drag_forwarding(
		func(_at: Vector2) -> Variant:
			BagOrder.elevate_drag_preview(
				button,
				BagOrder.make_drag_preview(item.item_icon, Vector2(52, 52))
			)
			return {
				"bank_uid": uid,
				"from_bag": is_bag,
				"item_id": int(item.get_meta(&"id", 0)),
			},
		func(_at: Vector2, data: Variant) -> bool:
			if data is not Dictionary:
				return false
			var dict: Dictionary = data
			if not dict.has("bank_uid"):
				return false
			# Only rearrange within the same pane (bag↔bag or vault↔vault).
			return bool(dict.get("from_bag", false)) == is_bag,
		func(_at: Vector2, data: Variant) -> void:
			if data is not Dictionary:
				return
			var from_uid: int = int((data as Dictionary).get("bank_uid", -1))
			if from_uid < 0 or from_uid == uid:
				return
			var from_id: int = int((data as Dictionary).get("item_id", 0))
			var to_id: int = int(item.get_meta(&"id", 0))
			if from_id > 0 and from_id == to_id:
				var moved: int = await StackMerge.try_merge(from_uid, uid, not is_bag)
				if moved > 0:
					_refresh()
					return
			if is_bag:
				BagOrder.move_before(BagOrder.load_order(), from_uid, uid)
			else:
				# A derived sort would just undo the drop on the next rebuild, so
				# freeze what's on screen into Custom first and say so.
				if _sort != BankOrder.Sort.CUSTOM:
					BankOrder.adopt_order(_vault_uids(false))
					_set_sort(BankOrder.Sort.CUSTOM)
					Toaster.toast("Switched to Custom layout so your arrangement sticks.")
				BankOrder.move_before(BankOrder.load_order(), from_uid, uid)
			_rebuild_grids()
	)


# --- Selection + amounts ----------------------------------------------------


func _on_tab_pressed(tab: int) -> void:
	_tab = tab
	BankOrder.save_tab(tab)
	_rebuild_grids()


func _on_sort_selected(index: int) -> void:
	_set_sort(_sort_picker.get_item_id(index) as BankOrder.Sort)
	_rebuild_grids()


func _set_sort(mode: BankOrder.Sort) -> void:
	_sort = mode
	BankOrder.save_sort(mode)
	_sync_sort_picker()


func _sync_sort_picker() -> void:
	if _sort_picker == null:
		return
	var index: int = _sort_picker.get_item_index(int(_sort))
	if index >= 0:
		_sort_picker.select(index)
	_sort_picker.tooltip_text = String(BankOrder.SORT_HINTS.get(_sort, ""))


func _on_slot_gui_input(event: InputEvent, uid: int, is_bag: bool) -> void:
	var mouse := event as InputEventMouseButton
	if mouse == null or not mouse.double_click or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	# Double-click moves the amount that's already in the box, so it obeys the
	# chips exactly like the transfer button does.
	if uid != _selected_uid or is_bag != _selected_from_bag:
		_select_stack(uid, is_bag)
	_on_transfer_pressed()


func _on_stack_pressed(uid: int, is_bag: bool) -> void:
	_select_stack(uid, is_bag)


func _select_stack(uid: int, is_bag: bool) -> void:
	var store: Dictionary = _inventory if is_bag else _bank
	if not store.has(uid):
		return
	var item: Item = _item_of(store, uid)
	_selected_uid = uid
	_selected_from_bag = is_bag
	_selected_item_id = int(store[uid].get("id", 0))
	_selected_name = String(item.item_name) if item != null else "Item"
	_selected_icon = item.item_icon if item != null else null

	var movable: int = _max_transferable()
	_amount_spin.editable = true
	_amount_spin.min_value = 1
	_amount_spin.max_value = maxi(1, movable)
	_amount_spin.value = maxi(1, mini(int(store[uid].get("a", 0)), movable))
	_transfer_button.disabled = movable <= 0
	_transfer_button.text = "Deposit  ▶" if is_bag else "◀  Withdraw"
	_set_amount_controls_enabled(movable > 0)
	_selection_icon.texture = _selected_icon
	_selection_name.text = _selected_name
	_selection_where.text = "%s in bag  ·  %s in vault%s" % [
		_fmt_gold(Inventory.count(_inventory, _selected_item_id)),
		_fmt_gold(Inventory.count(_bank, _selected_item_id)),
		"" if movable > 0 else ("  ·  vault full" if is_bag else "  ·  bag full"),
	]
	_sync_selection_highlights()


## How many units the selection can actually move right now: everything held on
## the source side, capped by what the destination can accept. Both directions
## use it — that is what makes All / X mean the same thing either way.
func _max_transferable() -> int:
	if _selected_item_id <= 0:
		return 0
	if _selected_from_bag:
		var held: int = Inventory.count(_inventory, _selected_item_id)
		var capacity: int = maxi(BankInteraction.STARTING_SLOTS, _bank_slots)
		return mini(held, Inventory.max_fit(_bank, _selected_item_id, capacity, true))
	var banked: int = Inventory.count(_bank, _selected_item_id)
	return mini(banked, Inventory.max_fit(
		_inventory, _selected_item_id, Inventory.MAX_SLOTS,
		false, _active_bag, _inventory_bags
	))


func _sync_selection_highlights() -> void:
	for grid_pair: Array in [[_bag_grid, true], [_vault_grid, false]]:
		var grid: GridContainer = grid_pair[0]
		var is_bag: bool = grid_pair[1]
		if grid == null:
			continue
		for child: Node in grid.get_children():
			if child is not Button:
				continue
			var button: Button = child as Button
			var uid: int = int(button.get_meta(&"bank_uid", -1))
			button.set_pressed_no_signal(uid == _selected_uid and is_bag == _selected_from_bag)


func _clear_selection() -> void:
	_selected_uid = -1
	_selected_item_id = 0
	_selected_name = ""
	_selected_icon = null
	if _amount_spin != null:
		_amount_spin.editable = false
		_amount_spin.max_value = 1
		_amount_spin.value = 1
	if _transfer_button != null:
		_transfer_button.disabled = true
		_transfer_button.text = "Transfer"
	_set_amount_controls_enabled(false)
	if _selection_icon != null:
		_selection_icon.texture = null
	if _selection_name != null:
		_selection_name.text = "Nothing selected"
	if _selection_where != null:
		_selection_where.text = "Click a stack in either panel"


## The chips, X and the spinner only mean something with a stack selected.
## Disabling them says so up front — a control that silently no-ops is exactly
## what "Deposit X does nothing" looked like from the player's side.
func _set_amount_controls_enabled(enabled: bool) -> void:
	for button: Button in _amount_controls:
		if is_instance_valid(button):
			button.disabled = not enabled


func _on_chip_pressed(value: int) -> void:
	if _selected_uid < 0:
		return
	var movable: int = _max_transferable()
	if movable <= 0:
		return
	_amount_spin.max_value = movable
	_amount_spin.value = movable if value < 0 else mini(value, movable)


func _on_custom_amount_pressed() -> void:
	if _selected_uid < 0:
		return
	_amount_spin.editable = true
	# grab_focus + select_all_on_focus: the field opens with its value highlighted.
	_amount_spin.get_line_edit().grab_focus()
	_amount_spin.get_line_edit().select_all()


func _on_transfer_pressed() -> void:
	if _selected_uid < 0 or _busy:
		return
	# The spinner only commits typed text on submit/focus-loss, and every button in
	# this row is FOCUS_NONE — so without apply() a typed "80" is still read as the
	# previous value.
	_amount_spin.apply()
	var requested: int = int(_amount_spin.value)
	var movable: int = _max_transferable()
	if movable <= 0:
		Toaster.toast(
			"Your bank is full. Buy more slots or withdraw something."
			if _selected_from_bag
			else "Your bag is full. Deposit or drop something first."
		)
		return
	if requested > movable:
		# Saying so matters: silently moving a different amount is indistinguishable
		# from the typed one having been thrown away.
		Toaster.toast("Only %s %s will move right now." % [_fmt_gold(movable), _selected_name])
		requested = movable
	# Let go of the field before the request: leaving it focused meant the next
	# keystroke went on editing a stale amount for a selection that no longer exists.
	_amount_spin.get_line_edit().release_focus()
	_transfer_stack(_selected_uid, _selected_from_bag, requested)


func _transfer_stack(uid: int, from_bag: bool, amount: int) -> void:
	if _busy or InstanceClient.current == null or uid < 0 or amount <= 0:
		return
	_busy = true
	_set_busy_chrome(true)
	var wanted_id: int = _selected_item_id
	var wanted_name: String = _selected_name
	var type: StringName = &"bank.deposit" if from_bag else &"bank.withdraw"
	var result: Array = await Client.request_data_await(
		type,
		{"uid": uid, "amount": amount},
		InstanceClient.current.name
	)
	_busy = false
	if not is_instance_valid(self) or not visible:
		return
	if result.size() < 2 or result[1] != OK or not (result[0] is Dictionary):
		Toaster.toast("That transfer failed.")
		_set_busy_chrome(false)
		_rebuild_grids()
		return
	var payload: Dictionary = result[0]
	if not bool(payload.get("ok", false)):
		_apply_payload(payload)
		_toast_failure(str(payload.get("reason", "")))
		_set_busy_chrome(false)
		_clear_selection()
		_rebuild_grids()
		return
	_apply_payload(payload)
	var moved: int = int(payload.get("moved", amount))
	Toaster.toast("%s %s %s." % [
		"Deposited" if from_bag else "Withdrew",
		_fmt_gold(moved),
		wanted_name,
	])
	_set_busy_chrome(false)
	# Keep the selection alive on the same side when a pile survives — banking 100
	# of 400 ore and having the menu forget what you were doing is the single most
	# annoying thing a bank can do.
	_clear_selection()
	_rebuild_grids()
	_reselect_item(wanted_id, from_bag)
	ClientState.inventory_changed.emit({"quiet": true})


func _toast_failure(reason: String) -> void:
	match reason:
		"currency":
			Toaster.toast("Gold stays in your currency pouch.")
		"inventory_full":
			Toaster.toast("Your bag is full. Deposit or drop something first.")
		"full":
			Toaster.toast("Your bank is full. Buy more slots or withdraw something.")
		"dead":
			Toaster.toast("You can't bank while dead.")
		_:
			Toaster.toast("That transfer failed.")


func _reselect_item(item_id: int, from_bag: bool) -> void:
	if item_id <= 0:
		return
	var store: Dictionary = _inventory if from_bag else _bank
	for uid: Variant in _stack_uids(store):
		if int(store[int(uid)].get("id", 0)) == item_id:
			_select_stack(int(uid), from_bag)
			return


func _set_busy_chrome(busy: bool) -> void:
	if _deposit_all_button != null:
		_deposit_all_button.disabled = busy
	if _upgrade_button != null:
		_upgrade_button.disabled = busy
	if _upgrade_count_spin != null:
		_upgrade_count_spin.editable = not busy
	if _upgrade_x_button != null:
		_upgrade_x_button.disabled = busy
	if _transfer_button != null and busy:
		_transfer_button.disabled = true


# --- Bulk actions -----------------------------------------------------------


func _on_deposit_all_pressed() -> void:
	if _busy or InstanceClient.current == null:
		return
	if _stack_uids(_inventory).is_empty():
		Toaster.toast("Your bag has nothing to deposit.")
		return
	_busy = true
	_set_busy_chrome(true)
	var result: Array = await Client.request_data_await(
		&"bank.deposit_all",
		{},
		InstanceClient.current.name
	)
	_busy = false
	if not is_instance_valid(self) or not visible:
		return
	if result.size() < 2 or result[1] != OK or not (result[0] is Dictionary):
		Toaster.toast("Deposit All failed.")
		_set_busy_chrome(false)
		_rebuild_grids()
		return
	var payload: Dictionary = result[0]
	_apply_payload(payload)
	if not bool(payload.get("ok", false)):
		_toast_failure(str(payload.get("reason", "")))
	else:
		var stacks: int = int(payload.get("stacks", 0))
		if stacks <= 0:
			Toaster.toast("Your bag has nothing to deposit.")
		else:
			Toaster.toast("Deposited %d stack%s into the vault." % [
				stacks,
				"" if stacks == 1 else "s",
			])
	_set_busy_chrome(false)
	_clear_selection()
	_rebuild_grids()
	ClientState.inventory_changed.emit({"quiet": true})


func _upgrade_count() -> int:
	if _upgrade_count_spin == null:
		return 1
	return clampi(int(_upgrade_count_spin.value), 1, BankInteraction.MAX_UPGRADE_COUNT)


func _sync_upgrade_controls() -> void:
	var maxed: bool = _bank_slots >= BankInteraction.MAX_BANK_SLOTS
	var count: int = _upgrade_count()
	var slots: int = BankInteraction.UPGRADE_SLOTS * count
	var cost: int = BankInteraction.UPGRADE_COST * count
	if _upgrade_button != null:
		_upgrade_button.disabled = _busy or maxed
		_upgrade_button.text = "Vault maxed" if maxed else "Buy +%d" % slots
		_upgrade_button.tooltip_text = (
			"Your vault is already at the %d-slot maximum." % BankInteraction.MAX_BANK_SLOTS
			if maxed
			else "Expand your vault by %d slots for %s gold. Caps at %d slots total." % [
				slots,
				_fmt_gold(cost),
				BankInteraction.MAX_BANK_SLOTS,
			]
		)
	if _upgrade_count_spin != null:
		_upgrade_count_spin.editable = not _busy and not maxed
	if _upgrade_x_button != null:
		_upgrade_x_button.disabled = _busy or maxed


func _on_upgrade_custom_amount_pressed() -> void:
	if _busy or _upgrade_count_spin == null:
		return
	_upgrade_count_spin.editable = true
	_upgrade_count_spin.get_line_edit().grab_focus()
	_upgrade_count_spin.get_line_edit().select_all()


func _on_upgrade_pressed() -> void:
	if _busy or InstanceClient.current == null:
		return
	if _upgrade_count_spin != null:
		_upgrade_count_spin.apply()
	var count: int = _upgrade_count()
	_busy = true
	_set_busy_chrome(true)
	var result: Array = await Client.request_data_await(
		&"bank.upgrade",
		{"count": count},
		InstanceClient.current.name
	)
	_busy = false
	if not is_instance_valid(self) or not visible:
		return
	if result.size() < 2 or result[1] != OK or not (result[0] is Dictionary):
		Toaster.toast("Could not buy bank slots.")
		_set_busy_chrome(false)
		_rebuild_grids()
		return
	var payload: Dictionary = result[0]
	_apply_payload(payload)
	if not bool(payload.get("ok", false)):
		match str(payload.get("reason", "")):
			"gold":
				var needed: int = int(payload.get("cost", BankInteraction.UPGRADE_COST * count))
				Toaster.toast("You need %s gold." % _fmt_gold(needed))
			"max_slots":
				Toaster.toast("Your vault is already at the %d-slot maximum." % BankInteraction.MAX_BANK_SLOTS)
			_:
				Toaster.toast("Could not buy bank slots.")
	else:
		Toaster.toast("Bank expanded to %d slots." % _bank_slots)
	_set_busy_chrome(false)
	_rebuild_grids()
	ClientState.inventory_changed.emit({"quiet": true})


# --- Formatting -------------------------------------------------------------


## Exact figures for prose — toasts, the selection line, prices. The badge
## abbreviation is [NumberFormat.format_stack_size]'s job; a sentence has room
## for the whole number and reads wrong without it.
func _fmt_gold(amount: int) -> String:
	return NumberFormat.with_commas(amount)


## Paints the purse. Read-only: the balance itself is the server's inventory
## count and is never written back from here. The readout abbreviates past 100k
## so a seven-figure vault cannot push the header apart, and the pouch shell
## keeps the exact figure in its tooltip for anyone pricing a transfer.
func _set_gold_display(gold: int) -> void:
	if _gold_label == null:
		return
	var purse: Dictionary = NumberFormat.format_stack_size(gold)
	var purse_color: Color = purse["color"]
	_gold_label.text = purse["text"]
	_gold_label.add_theme_color_override(&"font_color", purse_color)
	if _gold_pouch != null:
		_gold_pouch.tooltip_text = "%s gold" % purse["exact_text"]
