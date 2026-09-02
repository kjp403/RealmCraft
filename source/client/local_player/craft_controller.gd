class_name CraftController
extends Node
## Runs a crafting / cooking / brewing batch outside the fullscreen station UI so
## the big menu can close while the player keeps working. Owns a compact HUD chip
## (progress + Stop) and talks to [code]craft.item[/code] the same way the menu did.

## Seconds between crafts at normal speed. An Anvil Stabilizer divides this —
## see [member known_speed].
const CRAFT_INTERVAL: float = 2.0
const COLOR_GOLD: Color = Color(1.0, 0.85, 0.45)
const COLOR_MUTED: Color = Color(0.55, 0.58, 0.66)

## Craft-speed multiplier last reported by the server (1.0 = normal, 2.0 =
## stabilised). Static and shared with [CraftingMenu] so a batch started right
## after another one is already paced correctly — the server sends this back
## with every craft, so the only stale reading is the first craft after login.
## The server floor is the real authority; this just keeps the local loop and
## its progress bar honest.
static var known_speed: float = 1.0

var _player: LocalPlayer
var _active: bool = false
var _generation: int = 0

var _station_key: String = ""
var _station: CraftingStationResource
var _recipe_index: int = -1
var _qty_target: int = -1
var _crafted_this_run: int = 0

var _owned: Dictionary[int, int] = {}
var _golds: int = 0
var _gold_id: int = 0
var _profession_level: int = 1
## Level per profession the station's recipes gate on, for benches that host a
## second trade (the Ascended Workbench holds Smithing rows). The station's own
## profession stays in [member _profession_level]; this covers the overrides.
var _skill_levels: Dictionary[StringName, int] = {}

var _panel: PanelContainer
var _title_label: Label
var _status_label: Label
var _progress_bar: ProgressBar
var _stop_button: Button
var _icon: TextureRect


func setup(player: LocalPlayer) -> void:
	_player = player
	_gold_id = Economy.gold_id()


func is_active() -> bool:
	return _active


func cancel() -> void:
	_active = false
	_generation += 1
	_hide_panel()


## Begin a craft batch. [param qty_target] is -1 for "until materials run out".
func start(
	station_key: String,
	station: CraftingStationResource,
	recipe_index: int,
	qty_target: int
) -> void:
	if _player == null or station == null:
		return
	if recipe_index < 0 or recipe_index >= station.recipes.size():
		return
	var recipe: CraftingRecipe = station.recipes[recipe_index]
	if recipe == null or recipe.output_item == null:
		return

	cancel()
	_station_key = station_key
	_station = station
	_recipe_index = recipe_index
	_qty_target = qty_target
	_crafted_this_run = 0
	_active = true
	_generation += 1
	var gen: int = _generation
	_ensure_panel()
	_update_panel_static()
	_show_panel()
	_run_loop(gen)


func _run_loop(gen: int) -> void:
	await _refresh_state()
	while _active and gen == _generation and _recipe_index >= 0:
		var recipe: CraftingRecipe = _station.recipes[_recipe_index]
		if recipe == null:
			break
		if _level_for(recipe) < recipe.required_level or not _has_ingredients(recipe):
			break
		if _station.craft_fee > 0 and _golds < _station.craft_fee:
			break

		var interval: float = CRAFT_INTERVAL / maxf(0.01, known_speed)
		var waited: float = 0.0
		while waited < interval and _active and gen == _generation:
			await get_tree().create_timer(0.05).timeout
			waited += 0.05
			_set_progress(waited / interval)
		if not _active or gen != _generation:
			break
		if not _has_ingredients(recipe):
			break

		var ok: bool = await _craft_once()
		if not ok:
			break
		_crafted_this_run += 1
		_set_progress(0.0)
		_update_status()
		if _qty_target > 0 and _crafted_this_run >= _qty_target:
			break

	if gen == _generation:
		cancel()


func _craft_once() -> bool:
	if _station == null or _recipe_index < 0 or InstanceClient.current == null:
		return false
	var recipe: CraftingRecipe = _station.recipes[_recipe_index]
	var result: Array = await Client.request_data_await(
		&"craft.item",
		{"station_key": _station_key, "recipe": _recipe_index},
		InstanceClient.current.name
	)
	if result[1] != OK or not result[0].get("ok", false):
		_toast_failure(result[0] if result[1] == OK else {})
		return false

	var data: Dictionary = result[0]
	known_speed = maxf(0.01, float(data.get("craft_speed", 1.0)))
	var verb: String = _done_verb()
	Toaster.toast("%s %d %s" % [verb, int(data.get("amount", 1)), str(recipe.output_item.item_name)])
	var craft_level: int = int(data.get("level", 0))
	# The paid skill comes from the payload, not the station: a recipe may
	# override it (Ascended Workbench hosts Smithing rows), and the server owns
	# that decision.
	var paid: StringName = StringName(str(
		data.get("profession", _station.profession if _station != null else &"")
	))
	if craft_level > 0 and _station != null:
		ClientState.set_skill_level(paid, craft_level)
	if data.get("leveled_up", false) and _player != null:
		LevelUpFx.celebrate_skill(_player, paid, craft_level)
	# Keep compact inventory / gold pouch in sync while the fullscreen menu is closed.
	ClientState.inventory_changed.emit({"quiet": true})
	await _refresh_state()
	return true


func _refresh_state() -> void:
	if InstanceClient.current == null:
		return
	var inv_result: Array = await Client.request_data_await(
		&"inventory.get", {}, InstanceClient.current.name
	)
	if inv_result[1] == OK:
		_recompute_owned(inv_result[0])

	if _station == null:
		return
	var skills_result: Array = await Client.request_data_await(
		&"skills.get", {}, InstanceClient.current.name
	)
	if skills_result[1] == OK:
		var skills: Dictionary = skills_result[0].get("skills", {})
		var entry: Dictionary = skills.get(String(_station.profession), {})
		_profession_level = int(entry.get("level", 1))
		_skill_levels.clear()
		for r: CraftingRecipe in _station.recipes:
			if r == null:
				continue
			var prof: StringName = r.profession_for(_station)
			if not _skill_levels.has(prof):
				_skill_levels[prof] = int(skills.get(String(prof), {}).get("level", 1))


## The player's level in the skill THIS recipe gates on, which is the station's
## profession for everything except an override row.
func _level_for(recipe: CraftingRecipe) -> int:
	if recipe == null or _station == null:
		return _profession_level
	var prof: StringName = recipe.profession_for(_station)
	if prof == _station.profession:
		return _profession_level
	return int(_skill_levels.get(prof, 1))


func _recompute_owned(inventory: Dictionary) -> void:
	_owned.clear()
	for slot_uid in inventory:
		var data: Dictionary = inventory[slot_uid]
		var item_id: int = int(data.get("id", 0))
		if item_id > 0:
			_owned[item_id] = _owned.get(item_id, 0) + int(data.get("a", 0))
	_golds = _owned.get(_gold_id, 0)


func _has_ingredients(recipe: CraftingRecipe) -> bool:
	for ingredient: CraftIngredient in recipe.required_inputs():
		if ingredient == null or ingredient.item == null:
			continue
		var ing_id: int = int(ingredient.item.get_meta(&"id", 0))
		if _owned.get(ing_id, 0) < ingredient.amount:
			return false
	return true


func _done_verb() -> String:
	if _station == null:
		return "Crafted"
	if _station.profession == &"cooking":
		return "Cooked"
	if _station.profession == &"herblore":
		return "Brewed"
	return "Crafted"


func _action_verb() -> String:
	if _station == null:
		return "Crafting"
	if _station.profession == &"cooking":
		return "Cooking"
	if _station.profession == &"herblore":
		return "Brewing"
	return "Crafting"


func _toast_failure(data: Dictionary) -> void:
	var verb: String = "brew" if _station != null and _station.profession == &"herblore" \
		else ("cook" if _station != null and _station.profession == &"cooking" else "craft")
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


# --- Compact HUD chip --------------------------------------------------------

func _ensure_panel() -> void:
	if _panel != null and is_instance_valid(_panel):
		return
	var hud: Node = _find_hud()
	if hud == null:
		return

	_panel = PanelContainer.new()
	_panel.name = "CraftProgressPanel"
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.z_index = 3
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_left = -150.0
	_panel.offset_right = 150.0
	_panel.offset_top = -96.0
	_panel.offset_bottom = -28.0

	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 10)
	margin.add_theme_constant_override(&"margin_right", 10)
	margin.add_theme_constant_override(&"margin_top", 8)
	margin.add_theme_constant_override(&"margin_bottom", 8)
	_panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	margin.add_child(col)

	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 8)
	col.add_child(header)

	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(28, 28)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(_icon)

	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override(&"separation", 0)
	header.add_child(titles)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override(&"font_size", 13)
	_title_label.add_theme_color_override(&"font_color", COLOR_GOLD)
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	titles.add_child(_title_label)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override(&"font_size", 12)
	_status_label.add_theme_color_override(&"font_color", COLOR_MUTED)
	titles.add_child(_status_label)

	_stop_button = Button.new()
	_stop_button.text = "Stop"
	_stop_button.custom_minimum_size = Vector2(56, 28)
	_stop_button.pressed.connect(cancel)
	header.add_child(_stop_button)

	_progress_bar = ProgressBar.new()
	_progress_bar.theme_type_variation = &"XPBar"
	_progress_bar.custom_minimum_size = Vector2(0, 10)
	_progress_bar.show_percentage = false
	_progress_bar.max_value = 1.0
	_progress_bar.value = 0.0
	col.add_child(_progress_bar)

	hud.add_child(_panel)


func _find_hud() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	var hud: Node = tree.root.find_child("HUD", true, false)
	if hud != null:
		return hud
	var nodes: Array[Node] = tree.get_nodes_in_group(&"hud")
	return nodes[0] if not nodes.is_empty() else null


func _show_panel() -> void:
	if _panel != null:
		_panel.visible = true
		_panel.move_to_front()


func _hide_panel() -> void:
	if _panel != null and is_instance_valid(_panel):
		_panel.visible = false
		_set_progress(0.0)


func _update_panel_static() -> void:
	if _station == null or _recipe_index < 0:
		return
	var recipe: CraftingRecipe = _station.recipes[_recipe_index]
	if recipe == null or recipe.output_item == null:
		return
	if _icon != null:
		_icon.texture = recipe.output_item.item_icon
	if _title_label != null:
		var name_text: String = str(recipe.output_item.item_name)
		if recipe.output_amount > 1:
			name_text = "%s ×%d" % [name_text, recipe.output_amount]
		_title_label.text = "%s %s" % [_action_verb(), name_text]
	_update_status()


func _update_status() -> void:
	if _status_label == null:
		return
	if _qty_target > 0:
		_status_label.text = "%d / %d" % [_crafted_this_run, _qty_target]
	else:
		_status_label.text = "%d crafted" % _crafted_this_run


func _set_progress(ratio: float) -> void:
	if _progress_bar == null:
		return
	_progress_bar.value = clampf(ratio, 0.0, 1.0)


