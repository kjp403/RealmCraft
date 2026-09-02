extends MenuShell
## Crafting station UI — fullscreen master-detail on the shared MenuShell
## (mirrors shop_menu): the shell header carries category tabs (centre) and a
## profession chip + XP bar + gold balance (right); the left pane lists every
## recipe with a craftable/locked status glyph; the right pane pins the Craft
## button to the bottom with the station fee + predicted profession XP above it.
## Opened by the station NODE NAME (the server resolves the same station from
## the player's current map). Recipes render from the CraftingStationResource
## carried in the menu arg; only the craft itself is server-validated.

const COLOR_GOLD: Color = Color(1.0, 0.85, 0.45)
const COLOR_OK: Color = Color(0.5, 0.9, 0.5)
const COLOR_BAD: Color = Color(1.0, 0.5, 0.4)
const COLOR_MUTED: Color = Color(0.55, 0.58, 0.66)

## Owning CraftingStation node's name, sent with the craft request.
var _station_key: String
var _station: CraftingStationResource
## item_id -> owned count, from the latest inventory fetch.
var _owned: Dictionary[int, int]
var _golds: int
var _gold_id: int
var _profession_level: int = 1
var _profession_xp: int
var _profession_xp_to_next: int = 100
## Multiplier from xp-effect perks (Apprentice ranks), for the predicted gain.
var _xp_multiplier: float = 1.0

## Level and XP multiplier PER PROFESSION present at this station, not just the
## station's own. A bench can host a second trade's recipes (the Ascended
## Workbench holds the metal ascension sets, which stay Smithing), and those
## rows must gate on the skill that actually unlocks them. Keyed by profession;
## the station's own is always present.
var _skill_levels: Dictionary[StringName, int] = {}
var _skill_xp_multipliers: Dictionary[StringName, float] = {}
## Recipe indices in display order (sorted by gate, then name).
var _order: Array[int] = []
var _selected: int = -1
## Active category tab; empty when the station has a single category (no tabs).
var _tab: StringName = &""
var _has_tabs: bool = false
## Every station auto-loops: one craft every CRAFT_INTERVAL seconds until the
## materials run out (or the player stops / closes the menu). The wait comes
## BEFORE the craft, so a click can never buy an instant item — smelting, armour
## smithing and outfitting all cost real time instead of rewarding spam-clicking.
## `craft.item` enforces the same floor server-side.
const CRAFT_INTERVAL: float = 2.0
var _looping: bool = false
var _loop_generation: int = 0
var _progress_bar: ProgressBar

## How many items one Craft press makes. ALL keeps the original "until the
## materials run out" behaviour (the default, so nothing changes for players who
## already lean on it); ONE and X are the opt-in batch sizes.
enum Qty { ONE, X, ALL }
const QTY_MAX: int = 999
var _qty_mode: Qty = Qty.ALL
var _qty_spin: SpinBox
## Items completed by the run currently in flight (for the "3 / 25" readout).
var _crafted_this_run: int = 0

var _tab_buttons: Dictionary[StringName, Button] = {}
var _tab_group: ButtonGroup = ButtonGroup.new()
var _row_group: ButtonGroup = ButtonGroup.new()
var _prof_name_label: Label
var _prof_level_label: Label
var _xp_bar: ProgressBar
var _golds_label: Label
## Dedicated row under the title — smithing's many metal tabs no longer fight
## the title/close chip for header height (that was clipping the top of the UI).
var _tab_bar: HBoxContainer

@onready var recipe_list: VBoxContainer = %RecipeList
@onready var list_scroll: ScrollContainer = %ScrollContainer
@onready var detail_icon: TextureRect = %DetailIcon
@onready var detail_name_label: Label = %DetailNameLabel
@onready var detail_slot_label: Label = %DetailSlotLabel
@onready var detail_owned_label: Label = %DetailOwnedLabel
@onready var stats_text: RichTextLabel = %StatsText
@onready var materials_list: VBoxContainer = %MaterialsList
@onready var gate_label: Label = %GateLabel
@onready var fee_label: Label = %FeeLabel
@onready var xp_label: Label = %XpLabel
@onready var craft_button: Button = %CraftButton


func _ready() -> void:
	_gold_id = Economy.gold_id()
	var body: HBoxContainer = $Body as HBoxContainer
	build_shell("Crafting", body, true)
	_install_tab_bar()
	_wrap_detail_in_scroll()
	_build_header()
	_build_quantity_row()
	_build_progress_bar()
	craft_button.pressed.connect(_on_craft_pressed)
	visibility_changed.connect(_on_visibility_changed)
	# Both panes must expand vertically so the shell can shrink them on short
	# viewports instead of overflowing past the window/taskbar.
	if body != null:
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		for child: Node in body.get_children():
			if child is Control:
				(child as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	if list_scroll != null:
		list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL


## Detail column (Make / Craft / materials) scrolls when the viewport is short so
## Ascended / Workbench actions are never cropped off the bottom of the screen.
func _wrap_detail_in_scroll() -> void:
	var detail_panel: PanelContainer = null
	if craft_button != null:
		var walk: Node = craft_button
		while walk != null:
			if walk is PanelContainer and walk.name == "DetailPanel":
				detail_panel = walk as PanelContainer
				break
			walk = walk.get_parent()
	if detail_panel == null:
		return
	var margin: MarginContainer = detail_panel.get_node_or_null("Margin") as MarginContainer
	if margin == null:
		return
	var detail_vbox: VBoxContainer = margin.get_node_or_null("DetailVBox") as VBoxContainer
	if detail_vbox == null:
		return

	margin.remove_child(detail_vbox)
	var scroll := ScrollContainer.new()
	scroll.name = "DetailScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	detail_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(detail_vbox)
	margin.add_child(scroll)

	# Slightly tighter chrome so short windows keep Make/Craft reachable.
	craft_button.custom_minimum_size = Vector2(0, 36)
	margin.add_theme_constant_override(&"margin_top", 8)
	margin.add_theme_constant_override(&"margin_bottom", 8)
	margin.add_theme_constant_override(&"margin_left", 12)
	margin.add_theme_constant_override(&"margin_right", 12)


## Wrap the master/detail body in a column with a full-width tab strip on top so
## Bronze…Materials tabs don't share the title row (and get cropped with it).
func _install_tab_bar() -> void:
	if content.get_child_count() == 0:
		return
	var body: Control = content.get_child(0) as Control
	content.remove_child(body)

	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override(&"separation", 8)

	_tab_bar = HBoxContainer.new()
	_tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_tab_bar.add_theme_constant_override(&"separation", 6)
	column.add_child(_tab_bar)

	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	content.add_child(column)


## Hand the crafting menu the station's catalog directly (rendered client-side)
## plus the node name the server resolves the station by.
func open(arg: Dictionary) -> void:
	# Re-opening the station UI cancels any in-flight compact craft session.
	if ClientState.local_player != null:
		ClientState.local_player.cancel_craft_session()
	_stop_loop()
	_station_key = str(arg.get("key", ""))
	_station = arg.get("station") as CraftingStationResource
	if _station == null:
		hide()
		return
	set_title(_station.station_name if not _station.station_name.is_empty() else "Crafting")
	_prof_name_label.text = JobRegistry.display_name(_station.profession)
	_selected = -1
	_tab = &""
	_refresh()


func _on_visibility_changed() -> void:
	if not visible:
		# Compact CraftController owns the live batch — don't kill it just because
		# this fullscreen shell closed after Craft was pressed.
		_stop_loop()
		return
	if _station != null:
		_refresh()


func _is_cooking_station() -> bool:
	return _station != null and _station.profession == &"cooking"


func _is_herblore_station() -> bool:
	return _station != null and _station.profession == &"herblore"


func _action_verb() -> String:
	if _is_cooking_station():
		return "Cook"
	if _is_herblore_station():
		return "Brew"
	return "Craft"


func _stop_loop() -> void:
	_looping = false
	_loop_generation += 1
	_set_progress(0.0)


## "Make: 1 | X | All" above the Craft button. X reveals a spinner the player
## types their own batch size into. The choice sticks while the menu is open, so
## picking a size once covers a whole crafting session.
func _build_quantity_row() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)

	var caption: Label = Label.new()
	caption.text = "Make"
	caption.add_theme_color_override(&"font_color", COLOR_MUTED)
	caption.add_theme_font_size_override(&"font_size", 13)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(caption)

	var group: ButtonGroup = ButtonGroup.new()
	for option: Array in [["1", Qty.ONE], ["X", Qty.X], ["All", Qty.ALL]]:
		var mode: Qty = option[1]
		var button: Button = Button.new()
		button.text = str(option[0])
		button.toggle_mode = true
		button.button_group = group
		button.theme_type_variation = &"SectionTab"
		button.custom_minimum_size = Vector2(42, 26)
		button.button_pressed = (mode == _qty_mode)
		button.pressed.connect(_on_qty_pressed.bind(mode))
		row.add_child(button)

	_qty_spin = SpinBox.new()
	_qty_spin.min_value = 1
	_qty_spin.max_value = QTY_MAX
	_qty_spin.step = 1
	_qty_spin.value = 10
	_qty_spin.custom_minimum_size = Vector2(84, 30)
	_qty_spin.tooltip_text = "How many to make"
	_qty_spin.visible = (_qty_mode == Qty.X)
	_qty_spin.value_changed.connect(func(_value: float) -> void: _render_detail())
	row.add_child(_qty_spin)

	var column: Node = craft_button.get_parent()
	column.add_child(row)
	column.move_child(row, craft_button.get_index())


## Switching batch size mid-run would silently change the target — stop first.
func _on_qty_pressed(mode: Qty) -> void:
	_qty_mode = mode
	_qty_spin.visible = (mode == Qty.X)
	_stop_loop()
	_render_detail()


## Items this Craft press should make; -1 = keep going until something stops us.
func _qty_target() -> int:
	match _qty_mode:
		Qty.ONE:
			return 1
		Qty.X:
			return maxi(1, int(_qty_spin.value)) if _qty_spin != null else 1
		_:
			return -1


## Fill bar for the current item's CRAFT_INTERVAL wait, sitting between the
## fee/xp row and the Craft button so the timer reads as part of the action.
func _build_progress_bar() -> void:
	_progress_bar = ProgressBar.new()
	_progress_bar.theme_type_variation = &"XPBar"
	_progress_bar.custom_minimum_size = Vector2(0, 8)
	_progress_bar.show_percentage = false
	_progress_bar.max_value = 1.0
	_progress_bar.value = 0.0
	_progress_bar.visible = false
	var column: Node = craft_button.get_parent()
	column.add_child(_progress_bar)
	column.move_child(_progress_bar, craft_button.get_index())


func _set_progress(ratio: float) -> void:
	if _progress_bar == null:
		return
	_progress_bar.visible = _looping
	_progress_bar.value = clampf(ratio, 0.0, 1.0)


## Profession chip + XP bar + gold balance, inserted left of the Close button.
func _build_header() -> void:
	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)

	_prof_name_label = Label.new()
	_prof_name_label.add_theme_color_override(&"font_color", COLOR_MUTED)
	_prof_name_label.add_theme_font_size_override(&"font_size", 13)
	_prof_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(_prof_name_label)

	_prof_level_label = Label.new()
	_prof_level_label.add_theme_color_override(&"font_color", COLOR_GOLD)
	_prof_level_label.add_theme_font_size_override(&"font_size", 13)
	_prof_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(_prof_level_label)

	_xp_bar = ProgressBar.new()
	_xp_bar.theme_type_variation = &"XPBar"
	_xp_bar.custom_minimum_size = Vector2(110, 10)
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_xp_bar.show_percentage = false
	box.add_child(_xp_bar)

	var gold_icon: TextureRect = TextureRect.new()
	gold_icon.custom_minimum_size = Vector2(20, 20)
	gold_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	gold_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gold_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var gold: Item = ContentRegistryHub.load_by_id(&"items", _gold_id)
	if gold != null:
		gold_icon.texture = gold.item_icon
	box.add_child(gold_icon)

	_golds_label = Label.new()
	_golds_label.add_theme_color_override(&"font_color", COLOR_GOLD)
	_golds_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(_golds_label)

	header_right.add_child(box)
	header_right.move_child(box, 0)


## Pulls inventory + profession progress, then rebuilds tabs, list, and detail.
func _refresh() -> void:
	var inv_result: Array = await Client.request_data_await(&"inventory.get", {}, InstanceClient.current.name)
	if inv_result[1] == OK:
		_recompute_owned(inv_result[0])

	var skills_result: Array = await Client.request_data_await(&"skills.get", {}, InstanceClient.current.name)
	if skills_result[1] == OK:
		var skills: Dictionary = skills_result[0].get("skills", {})
		var entry: Dictionary = skills.get(String(_station.profession), {})
		_profession_level = int(entry.get("level", 1))
		_profession_xp = int(entry.get("xp", 0))
		_profession_xp_to_next = maxi(1, int(entry.get("xp_to_next", 100)))
		_xp_multiplier = _xp_multiplier_from(entry.get("choices", []))
		# Cache every profession this station's recipes gate on, so an
		# override row reads its own skill rather than the bench's.
		_skill_levels.clear()
		_skill_xp_multipliers.clear()
		for prof: StringName in _professions_present():
			var row: Dictionary = skills.get(String(prof), {})
			_skill_levels[prof] = int(row.get("level", 1))
			_skill_xp_multipliers[prof] = _xp_multiplier_from(row.get("choices", []))

	_update_header()
	_build_tabs()
	_build_list()
	_render_detail()


func _recompute_owned(inventory: Dictionary) -> void:
	_owned.clear()
	for slot_uid in inventory:
		var data: Dictionary = inventory[slot_uid]
		var item_id: int = int(data.get("id", 0))
		if item_id > 0:
			_owned[item_id] = _owned.get(item_id, 0) + int(data.get("a", 0))
	_golds = _owned.get(_gold_id, 0)


## 1.0 + every rank of every xp-effect perk (Apprentice), for predicted gains.
## Every distinct profession the station's recipes gate on, its own included.
func _professions_present() -> Array[StringName]:
	var out: Array[StringName] = []
	if _station == null:
		return out
	out.append(_station.profession)
	for recipe: CraftingRecipe in _station.recipes:
		if recipe == null:
			continue
		var prof: StringName = recipe.profession_for(_station)
		if not out.has(prof):
			out.append(prof)
	return out


## The player's level in the skill THIS recipe gates on.
func _level_for(recipe: CraftingRecipe) -> int:
	if recipe == null:
		return _profession_level
	var prof: StringName = recipe.profession_for(_station)
	if prof == _station.profession:
		return _profession_level
	return int(_skill_levels.get(prof, 1))


## The XP multiplier for the skill THIS recipe pays.
func _xp_multiplier_for(recipe: CraftingRecipe) -> float:
	if recipe == null:
		return _xp_multiplier
	var prof: StringName = recipe.profession_for(_station)
	if prof == _station.profession:
		return _xp_multiplier
	return float(_skill_xp_multipliers.get(prof, 1.0))


func _xp_multiplier_from(choices: Variant) -> float:
	var mult: float = 1.0
	for choice: Variant in (choices if choices is Array else []):
		var c: Dictionary = choice
		if String(c.get("effect", "")) == "xp":
			mult += int(c.get("rank", 0)) * float(c.get("per_rank", 0.0))
	return mult


func _update_header() -> void:
	_prof_level_label.text = "Lv %d" % _profession_level
	_xp_bar.max_value = _profession_xp_to_next
	_xp_bar.value = _profession_xp
	_xp_bar.tooltip_text = "%d / %d xp" % [_profession_xp, _profession_xp_to_next]
	_golds_label.text = str(_golds)


# --- Category tabs -----------------------------------------------------------

## Tab assignment and ordering live in [CraftingCategory], in `common/`, so the
## bench verifier can assert the real rule rather than a copy of it — the tab a
## recipe lands in is derived, never authored, so a duplicated rule would drift
## silently and put recipes back in the wrong tab.
func _category(recipe: CraftingRecipe) -> StringName:
	return CraftingCategory.of(recipe, _station)


func _is_smithing_station() -> bool:
	return _station != null and _station.profession == &"smithing"


func _tab_label(cat: StringName) -> String:
	return CraftingCategory.label(cat)




func _build_tabs() -> void:
	if _tab_bar == null:
		return
	for child: Node in _tab_bar.get_children():
		child.queue_free()
	_tab_buttons.clear()

	var present: Array[StringName] = []
	for recipe: CraftingRecipe in _station.recipes:
		if recipe == null or recipe.output_item == null:
			continue
		var cat: StringName = _category(recipe)
		if not present.has(cat):
			present.append(cat)
	# A lone category needs no tab bar at all (e.g. the Furnace).
	_has_tabs = present.size() > 1
	_tab_bar.visible = _has_tabs
	if not _has_tabs:
		_tab = &""
		return

	var tabs: Array[StringName] = []
	var preferred: Array[StringName] = CraftingCategory.preferred_order(_station)
	for cat: StringName in preferred:
		if present.has(cat):
			tabs.append(cat)
	# Any unexpected category still gets a tab rather than vanishing.
	for cat: StringName in present:
		if not tabs.has(cat):
			tabs.append(cat)
	if not tabs.has(_tab):
		_tab = tabs[0]
	for cat: StringName in tabs:
		var tab: Button = Button.new()
		tab.text = _tab_label(cat)
		tab.toggle_mode = true
		tab.button_group = _tab_group
		tab.theme_type_variation = &"SectionTab"
		tab.custom_minimum_size = Vector2(0, 34)
		tab.clip_text = false
		tab.button_pressed = (cat == _tab)
		tab.pressed.connect(_on_tab_pressed.bind(cat))
		_tab_bar.add_child(tab)
		_tab_buttons[cat] = tab


func _on_tab_pressed(cat: StringName) -> void:
	_tab = cat
	_build_list()
	# Keep the selection if it survived the filter; otherwise pick the first row.
	if not _order.has(_selected):
		_selected = _order[0] if not _order.is_empty() else -1
		_build_list()
	_render_detail()


# --- Recipe list -------------------------------------------------------------

func _build_list() -> void:
	for child: Node in recipe_list.get_children():
		child.queue_free()

	_order.clear()
	for i: int in _station.recipes.size():
		var recipe: CraftingRecipe = _station.recipes[i]
		if recipe == null or recipe.output_item == null:
			continue
		if _has_tabs and _category(recipe) != _tab:
			continue
		_order.append(i)
	_order.sort_custom(func(a: int, b: int) -> bool:
		var ra: CraftingRecipe = _station.recipes[a]
		var rb: CraftingRecipe = _station.recipes[b]
		if ra.required_level != rb.required_level:
			return ra.required_level < rb.required_level
		return String(ra.output_item.item_name) < String(rb.output_item.item_name))

	if _selected == -1 and not _order.is_empty():
		_selected = _order[0]

	for i: int in _order:
		recipe_list.add_child(_make_row(i, _station.recipes[i]))
	DragScroll.enable(list_scroll)


func _make_row(index: int, recipe: CraftingRecipe) -> Button:
	var locked: bool = _level_for(recipe) < recipe.required_level
	var row: Button = Button.new()
	row.toggle_mode = true
	row.button_group = _row_group
	row.button_pressed = (index == _selected)
	row.custom_minimum_size = Vector2(0, 40)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.pressed.connect(_on_row_pressed.bind(index))

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 8.0
	hbox.offset_right = -8.0
	hbox.add_theme_constant_override(&"separation", 8)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hbox)

	var icon: TextureRect = TextureRect.new()
	icon.custom_minimum_size = Vector2(26, 26)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.texture = recipe.output_item.item_icon
	hbox.add_child(icon)

	var name_label: Label = Label.new()
	var out_name: String = str(recipe.output_item.item_name)
	if recipe.output_amount > 1:
		out_name = "%s ×%d" % [out_name, recipe.output_amount]
	name_label.text = out_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hbox.add_child(name_label)

	var status: Label = Label.new()
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if locked:
		status.text = "Lv %d" % recipe.required_level
		status.add_theme_color_override(&"font_color", COLOR_BAD)
		status.add_theme_font_size_override(&"font_size", 12)
		row.modulate = Color(1, 1, 1, 0.55)
	else:
		status.text = UiGlyphs.bullet()
		status.add_theme_color_override(&"font_color", COLOR_OK if _has_ingredients(recipe) else COLOR_MUTED)
	hbox.add_child(status)
	return row


func _on_row_pressed(index: int) -> void:
	if _selected != index:
		_stop_loop()
	_selected = index
	_render_detail()


# --- Detail pane -------------------------------------------------------------

func _render_detail() -> void:
	for child: Node in materials_list.get_children():
		child.queue_free()
	if _selected < 0 or _selected >= _station.recipes.size():
		detail_name_label.text = "Select a recipe"
		detail_slot_label.text = ""
		detail_owned_label.text = ""
		detail_icon.texture = null
		stats_text.text = ""
		gate_label.text = ""
		fee_label.text = ""
		xp_label.text = ""
		craft_button.disabled = true
		craft_button.text = _action_verb()
		_set_progress(0.0)
		return

	var recipe: CraftingRecipe = _station.recipes[_selected]
	var item: Item = recipe.output_item
	detail_icon.texture = item.item_icon
	var detail_name: String = str(item.item_name)
	if recipe.output_amount > 1:
		detail_name = "%s ×%d" % [detail_name, recipe.output_amount]
	detail_name_label.text = detail_name
	detail_slot_label.text = _slot_line(item)
	detail_owned_label.text = _owned_line(item)
	# Craft stations gate on profession level — never show wear-mastery as a
	# craft requirement. Mastery still appears on inventory / equip tooltips.
	stats_text.text = ItemTooltip.body(
		item,
		null,
		recipe.profession_for(_station),
		recipe.required_level,
		_level_for(recipe),
	)

	var has_mats: bool = _has_ingredients(recipe)
	# A smelt names its process above the material list ("Quenched in dragon
	# scale."), so an alloy recipe reads as a method and not just a longer bill.
	var smelt_recipe: SmeltingRecipe = recipe as SmeltingRecipe
	if smelt_recipe != null and not smelt_recipe.flavor.is_empty():
		var flavor_label: Label = Label.new()
		flavor_label.text = smelt_recipe.flavor
		flavor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		flavor_label.add_theme_font_size_override(&"font_size", 12)
		flavor_label.add_theme_color_override(&"font_color", COLOR_MUTED)
		materials_list.add_child(flavor_label)
	for ingredient: CraftIngredient in recipe.required_inputs():
		if ingredient == null or ingredient.item == null:
			continue
		materials_list.add_child(_make_material_row(ingredient, recipe))

	var meets_level: bool = _level_for(recipe) >= recipe.required_level
	if recipe.required_level > 0:
		gate_label.text = "%s Lv %d %s" % [
			JobRegistry.display_name(recipe.profession_for(_station)),
			recipe.required_level,
			"met" if meets_level else "required",
		]
		gate_label.add_theme_color_override(&"font_color", COLOR_OK if meets_level else COLOR_BAD)
	else:
		gate_label.text = ""

	var fee: int = _station.craft_fee
	var can_pay: bool = _golds >= fee
	if fee > 0:
		fee_label.text = "Fee: %d gold" % fee
		fee_label.add_theme_color_override(&"font_color", COLOR_GOLD if can_pay else COLOR_BAD)
	else:
		fee_label.text = ""
	xp_label.text = "+%d %s xp" % [
		roundi(recipe.xp_reward * _xp_multiplier_for(recipe)),
		JobRegistry.display_name(recipe.profession_for(_station)),
	]

	if _looping:
		craft_button.disabled = false
		var target: int = _qty_target()
		craft_button.text = (
			"Stop (%d / %d)" % [_crafted_this_run, target] if target > 0
			else "Stop (%d)" % _crafted_this_run
		)
		_set_progress(_progress_bar.value if _progress_bar != null else 0.0)
		return
	_set_progress(0.0)

	craft_button.disabled = not (meets_level and has_mats and can_pay)
	if not meets_level:
		craft_button.text = "Requires Lv %d" % recipe.required_level
	elif not has_mats:
		craft_button.text = "Missing materials"
	elif not can_pay:
		craft_button.text = "Not enough gold"
	else:
		craft_button.text = _craft_button_label()


## "Craft" / "Craft ×25" / "Craft All" — the batch size belongs on the button
## that commits to it, not only on the selector above it.
func _craft_button_label() -> String:
	match _qty_mode:
		Qty.ONE:
			return _action_verb()
		Qty.X:
			return "%s ×%d" % [_action_verb(), _qty_target()]
		_:
			return "%s All" % _action_verb()


## "Helmet · wearable at level N" for gear, "Material" for mats.
func _slot_line(item: Item) -> String:
	var gear: GearItem = item as GearItem
	if gear == null:
		return "Material"
	var slot_name: String = "Gear"
	if gear.slot != null:
		slot_name = gear.slot.resource_path.get_file().get_basename().capitalize()
	if gear.required_level > 0:
		return "%s · wearable at level %d" % [slot_name, gear.required_level]
	return slot_name


func _owned_line(item: Item) -> String:
	var item_id: int = int(item.get_meta(&"id", 0))
	var count: int = _owned.get(item_id, 0)
	var line: String = "In bag: %d" % count
	if item is GearItem and item_id in _equipped_ids():
		line += " · Equipped"
	return line


func _equipped_ids() -> Array:
	if ClientState.local_player == null:
		return []
	return ClientState.local_player.equipment_component.slots.values.values()


## One "name  have/need" row; gear ingredients read as "Consumes:" (ring
## upgrades) and a smelting catalyst as "Requires:", because it is held for the
## craft rather than spent by it and a plain row would read as a lie.
func _make_material_row(ingredient: CraftIngredient, recipe: CraftingRecipe) -> HBoxContainer:
	var ing_id: int = int(ingredient.item.get_meta(&"id", 0))
	var have: int = _owned.get(ing_id, 0)
	var enough: bool = have >= ingredient.amount

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)

	var icon: TextureRect = TextureRect.new()
	icon.custom_minimum_size = Vector2(20, 20)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = ingredient.item.item_icon
	row.add_child(icon)

	var name_label: Label = Label.new()
	var smelt: SmeltingRecipe = recipe as SmeltingRecipe
	var prefix: String = ""
	if smelt != null and smelt.is_catalyst(ing_id):
		prefix = "Requires: "
	elif ingredient.item is GearItem:
		prefix = "Consumes: "
	name_label.text = prefix + str(ingredient.item.item_name)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override(&"font_size", 13)
	row.add_child(name_label)

	var count_label: Label = Label.new()
	count_label.text = "%d / %d" % [have, ingredient.amount]
	count_label.add_theme_font_size_override(&"font_size", 13)
	count_label.add_theme_color_override(&"font_color", COLOR_OK if enough else COLOR_BAD)
	row.add_child(count_label)
	return row


func _has_ingredients(recipe: CraftingRecipe) -> bool:
	for ingredient: CraftIngredient in recipe.required_inputs():
		if ingredient == null or ingredient.item == null:
			continue
		var ing_id: int = int(ingredient.item.get_meta(&"id", 0))
		if _owned.get(ing_id, 0) < ingredient.amount:
			return false
	return true


# --- Crafting ----------------------------------------------------------------

func _on_craft_pressed() -> void:
	if _selected < 0 or _station == null:
		return
	if ClientState.local_player != null and ClientState.local_player.is_crafting():
		ClientState.local_player.cancel_craft_session()
		_render_detail()
		return
	if _looping:
		_stop_loop()
		_render_detail()
		return
	# Close the fullscreen shell and run the batch on the compact HUD chip so the
	# player can see the world and open Inventory / Skills / Quests while crafting.
	if ClientState.local_player == null:
		_start_craft_loop()
		return
	var recipe: CraftingRecipe = _station.recipes[_selected]
	if _level_for(recipe) < recipe.required_level or not _has_ingredients(recipe):
		return
	if _station.craft_fee > 0 and _golds < _station.craft_fee:
		return
	var qty: int = _qty_target()
	var key: String = _station_key
	var station: CraftingStationResource = _station
	var recipe_index: int = _selected
	hide()
	ClientState.local_player.start_craft_session(key, station, recipe_index, qty)


## Wait CRAFT_INTERVAL, craft one, repeat until the batch size is reached, the
## materials run out, the player hits Stop, or the menu closes. Fallback path when
## no LocalPlayer is available — normal play uses [method LocalPlayer.start_craft_session].
func _start_craft_loop() -> void:
	_looping = true
	_loop_generation += 1
	_crafted_this_run = 0
	var gen: int = _loop_generation
	var target: int = _qty_target()
	_render_detail()
	while _looping and gen == _loop_generation and visible and _selected >= 0:
		var recipe: CraftingRecipe = _station.recipes[_selected]
		if _level_for(recipe) < recipe.required_level or not _has_ingredients(recipe):
			break
		if _station.craft_fee > 0 and _golds < _station.craft_fee:
			break
		# Paced by the same shared multiplier the HUD loop uses, so an Anvil
		# Stabilizer speeds this fallback path up identically.
		var interval: float = CRAFT_INTERVAL / maxf(0.01, CraftController.known_speed)
		var waited: float = 0.0
		while waited < interval and _looping and gen == _loop_generation and visible:
			await get_tree().create_timer(0.05).timeout
			waited += 0.05
			_set_progress(waited / interval)
		if not _looping or gen != _loop_generation or not visible:
			break
		if not _has_ingredients(recipe):
			break
		var ok: bool = await _craft_once()
		if not ok:
			break
		_crafted_this_run += 1
		_set_progress(0.0)
		if target > 0 and _crafted_this_run >= target:
			break
		_render_detail() # refresh the "3 / 25" readout on the Stop button
	_stop_loop()
	if is_inside_tree():
		_render_detail()


## Single craft/cook request. Returns true on success.
func _craft_once() -> bool:
	if _selected < 0 or _station == null:
		return false
	var recipe: CraftingRecipe = _station.recipes[_selected]
	var result: Array = await Client.request_data_await(
		&"craft.item",
		{"station_key": _station_key, "recipe": _selected},
		InstanceClient.current.name
	)
	if result[1] != OK or not result[0].get("ok", false):
		_toast_failure(result[0] if result[1] == OK else {})
		return false

	var data: Dictionary = result[0]
	CraftController.known_speed = maxf(0.01, float(data.get("craft_speed", 1.0)))
	var verb: String = "Brewed" if _is_herblore_station() else ("Cooked" if _is_cooking_station() else "Crafted")
	var title: String = "%s %d %s" % [verb, int(data.get("amount", 1)), str(recipe.output_item.item_name)]
	var xp_gain: int = int(data.get("xp", 0))
	# Which skill was actually paid comes back in the payload rather than being
	# assumed from the station: a recipe can override it (the Ascended Workbench
	# hosts Smithing rows), and the server is the one that decided.
	var paid: StringName = StringName(str(data.get("profession", _station.profession)))
	var lines: PackedStringArray = PackedStringArray()
	if xp_gain > 0:
		lines.append("+%d %s XP" % [xp_gain, JobRegistry.display_name(paid)])
	Toaster.toast_feed("craft:" + str(_station_key), title, lines)
	var craft_level: int = int(data.get("level", 0))
	if craft_level > 0 and _station != null:
		ClientState.set_skill_level(paid, craft_level)
	if data.get("leveled_up", false) and ClientState.local_player != null:
		LevelUpFx.celebrate_skill(
			ClientState.local_player,
			paid,
			craft_level,
		)
	await _refresh()
	return true


func _toast_failure(data: Dictionary) -> void:
	var verb: String = "brew" if _is_herblore_station() else ("cook" if _is_cooking_station() else "craft")
	match String(data.get("reason", "")):
		"level":
			Toaster.toast("Requires level %d to %s this." % [int(data.get("required_level", 0)), verb])
		"ingredients":
			Toaster.toast("You don't have the ingredients.")
		"gold":
			Toaster.toast("Not enough gold for the station fee (%d)." % int(data.get("fee", 0)))
		"too_fast":
			Toaster.toast("Steady on — one at a time.")
		"too_far":
			Toaster.toast("Move closer to the station.")
		"inventory_full":
			Toaster.toast("Your bag is full. Bank some items first.")
		_:
			Toaster.toast("Can't %s that right now." % verb)


