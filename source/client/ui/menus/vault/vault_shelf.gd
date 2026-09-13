extends PanelContainer
## The list down the left of every Vault tab: everything on the shelf at once,
## each row with its price, or Owned / Equipped.
##
## REPLACES THE < > CYCLER. Arrowing one at a time through 26 pets meant a buyer
## could not see what existed, what they already owned or what anything cost
## without visiting every entry. A list answers all three at a glance, and one
## click goes straight to the item they want.

signal picked(index: int)

const VaultStyle := preload("res://source/client/ui/menus/vault/vault_style.gd")

const WIDTH: float = 260.0
const ROW_HEIGHT: float = 30.0
## A whole divisor of the 64px coin source, so NEAREST lands on pixel boundaries.
const COIN_PX: int = 16

var _scroll: ScrollContainer
var _list: VBoxContainer
var _rows: Array[Button] = []
var _tags: Array[Label] = []
var _coins: Array[TextureRect] = []


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override(&"panel", VaultStyle.panel_box(4))

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 2)
	_scroll.add_child(_list)


## [param rows]: Array of {"name": String, "tag": Dictionary from VaultStyle.row_tag}.
func set_rows(rows: Array) -> void:
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows.clear()
	_tags.clear()
	_coins.clear()
	for i: int in rows.size():
		var row: Dictionary = rows[i]
		_add_row(i, str(row.get("name", "")), row.get("tag", {}) as Dictionary)
	# After the rows exist: DragScroll wires the children it finds at call time.
	DragScroll.enable(_scroll)


## Same rows, new tags - a purchase or an equip changed what one of them says.
func set_tags(tags: Array) -> void:
	if tags.size() != _rows.size():
		return
	for i: int in tags.size():
		_apply_tag(i, tags[i] as Dictionary)


func row_count() -> int:
	return _rows.size()


## Highlight [param index] without emitting [signal picked], and scroll it into
## view - opening a tab lands on what the player wears, which may be far down.
func select(index: int) -> void:
	for i: int in _rows.size():
		_rows[i].set_pressed_no_signal(i == index)
	if index >= 0 and index < _rows.size():
		_scroll.ensure_control_visible.call_deferred(_rows[index])


func _add_row(index: int, title: String, tag: Dictionary) -> void:
	var button: Button = Button.new()
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	VaultStyle.style_row(button)
	button.pressed.connect(_on_row_pressed.bind(index))
	_list.add_child(button)

	var line: HBoxContainer = HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 8
	line.offset_right = -8
	line.add_theme_constant_override(&"separation", 4)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(line)

	var title_label: Label = Label.new()
	title_label.text = title
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.add_theme_font_size_override(&"font_size", VaultStyle.SIZE_BODY)
	title_label.add_theme_color_override(&"font_color", VaultStyle.INK)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(title_label)

	var coin: TextureRect = TextureRect.new()
	coin.texture = VaultStyle.COIN_ICON
	coin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.custom_minimum_size = Vector2(COIN_PX, COIN_PX)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(coin)

	var tag_label: Label = Label.new()
	tag_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag_label.add_theme_font_size_override(&"font_size", VaultStyle.SIZE_BODY)
	tag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(tag_label)

	_rows.append(button)
	_coins.append(coin)
	_tags.append(tag_label)
	_apply_tag(index, tag)


func _apply_tag(index: int, tag: Dictionary) -> void:
	var text: String = str(tag.get("text", ""))
	_tags[index].text = text
	_tags[index].visible = not text.is_empty()
	_tags[index].add_theme_color_override(&"font_color", tag.get("color", VaultStyle.INK_DIM) as Color)
	_coins[index].visible = bool(tag.get("coin", false))


## Toggle buttons un-press when clicked twice; a shelf always has one selected.
func _on_row_pressed(index: int) -> void:
	select(index)
	picked.emit(index)
