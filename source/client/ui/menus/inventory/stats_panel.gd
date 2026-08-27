extends PanelContainer
## Read-only stat readout for the Character → Stats tab.
##
## Every row is "what the number is" PLUS "what it does for you" in plain
## English — a fresh player should be able to read this sheet and understand
## their character without knowing a single formula. Rows are grouped
## (Vitals / Offense / Defense / Utility) and hidden when a stat is inert (no
## mana pool → no mana rows), so the sheet never shows a meaningless 0.

## Section header → rows. Row = [label, color, stat key, kind].
## kind drives both the value format and the explainer line under it.
const _SECTIONS: Array = [
	["Vitals", [
		["Health", Color("#3de600"), Stat.HEALTH_MAX, &"health"],
		["Health Regen", Color("#3de600"), Stat.HEALTH_REGEN, &"hp_regen"],
		["Mana", Color("#33b5e5"), Stat.MANA_MAX, &"mana"],
		["Mana Regen", Color("#33b5e5"), Stat.MANA_REGEN, &"mana_regen"],
	]],
	["Offense", [
		["Attack Damage", Color("#fc7f03"), Stat.AD, &"ad"],
		["Ability Power", Color("#a67ffb"), Stat.AP, &"ap"],
		["Lifesteal", Color("#e0557b"), Stat.LIFESTEAL, &"percent_stat"],
	]],
	["Defense", [
		["Armor", Color("#d8a657"), Stat.ARMOR, &"resist_physical"],
		["Magic Resist", Color("#a67ffb"), Stat.MR, &"resist_magic"],
	]],
	["Utility", [
		["Move Speed", Color("#dbd802"), Stat.MOVE_SPEED, &"move_speed"],
		["Ability Haste", Color("#7dc94f"), Stat.ABILITY_HASTE, &"haste"],
	]],
]

## Base move speed, used to report your speed as a % of a fresh character's.
const _BASE_MOVE_SPEED: float = 112.5

var observed_stats: StatsComponent.Stats

var _rows_box: VBoxContainer


func _ready() -> void:
	_build_layout()
	_try_watch()
	ClientState.local_player_ready.connect(func(_lp: LocalPlayer): _try_watch())


func _build_layout() -> void:
	var pad: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 14)
	add_child(pad)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 8)
	pad.add_child(vbox)

	var title: Label = Label.new()
	title.text = "Combat Stats"
	title.add_theme_color_override(&"font_color", Color(1, 0.9, 0.55))
	title.add_theme_font_size_override(&"font_size", 17)
	vbox.add_child(title)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	# Inset so the scrollbar never sits on top of a value.
	var scroll_pad: MarginContainer = MarginContainer.new()
	scroll_pad.add_theme_constant_override(&"margin_right", 12)
	scroll_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(scroll_pad)

	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override(&"separation", 4)
	scroll_pad.add_child(_rows_box)


func _try_watch() -> void:
	if ClientState.local_player:
		watch_stats(ClientState.local_player.stats_component.stats)


func watch_stats(stats: StatsComponent.Stats) -> void:
	if observed_stats and observed_stats.stat_changed.is_connected(_on_stats_changed):
		observed_stats.stat_changed.disconnect(_on_stats_changed)

	observed_stats = stats
	if observed_stats:
		observed_stats.stat_changed.connect(_on_stats_changed)

	redraw()


func _on_stats_changed(_stat_name: StringName, _value: float) -> void:
	redraw()


func redraw() -> void:
	if _rows_box == null or not observed_stats:
		return

	for child in _rows_box.get_children():
		child.queue_free()

	for section: Array in _SECTIONS:
		var rows: Array = section[1]
		var shown: Array = rows.filter(func(row: Array) -> bool: return _row_shown(row))
		if shown.is_empty():
			continue
		_add_section_header(str(section[0]))
		for row: Array in shown:
			_add_row(row)


## Inert stats (a melee build with no mana, 0 lifesteal) are hidden rather than
## shown as a confusing 0 — the sheet should only list what actually affects you.
func _row_shown(row: Array) -> bool:
	match row[3]:
		&"mana", &"mana_regen":
			return _stat(Stat.MANA_MAX) > 0.0
		&"ap", &"percent_stat":
			return _stat(row[2]) > 0.0
	return true


func _add_section_header(text: String) -> void:
	var header: Label = Label.new()
	header.text = text.to_upper()
	header.add_theme_font_size_override(&"font_size", 11)
	header.add_theme_color_override(&"font_color", Color(0.55, 0.58, 0.68))
	_rows_box.add_child(header)

	var rule: HSeparator = HSeparator.new()
	rule.modulate = Color(1, 1, 1, 0.15)
	_rows_box.add_child(rule)


func _add_row(row: Array) -> void:
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override(&"separation", 12)
	_rows_box.add_child(hbox)

	var text_box: VBoxContainer = VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override(&"separation", 0)
	hbox.add_child(text_box)

	var name_label: Label = Label.new()
	name_label.text = str(row[0])
	name_label.add_theme_font_size_override(&"font_size", 14)
	name_label.add_theme_color_override(&"font_color", Color(0.82, 0.86, 0.92))
	text_box.add_child(name_label)

	var explain: String = _explain(row)
	if not explain.is_empty():
		var explain_label: Label = Label.new()
		explain_label.text = explain
		explain_label.add_theme_font_size_override(&"font_size", 10)
		explain_label.add_theme_color_override(&"font_color", Color(0.58, 0.61, 0.7))
		explain_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		explain_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_box.add_child(explain_label)

	var value_label: Label = Label.new()
	value_label.text = _value_text(row)
	value_label.add_theme_font_size_override(&"font_size", 15)
	value_label.add_theme_color_override(&"font_color", row[1])
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.custom_minimum_size.x = 72
	hbox.add_child(value_label)


func _value_text(row: Array) -> String:
	var value: float = _stat(row[2])
	match row[3]:
		&"health":
			return "%d / %d" % [_stat(Stat.HEALTH), value]
		&"hp_regen", &"mana_regen":
			return "%.1f/s" % value
		&"percent_stat":
			return "%d%%" % roundi(value)
	return "%d" % roundi(value)


## The "what does this do for me" line under each stat. Percentages are computed
## from the same formulas the server uses, so the sheet can't drift from combat.
func _explain(row: Array) -> String:
	var value: float = _stat(row[2])
	match row[3]:
		&"health":
			return "How much damage you can take before going down."
		&"hp_regen":
			return "Health recovered every second while out of combat."
		&"mana":
			return "Fuel for your special abilities. Basic attacks are free."
		&"mana_regen":
			return "Mana recovered every second while out of combat."
		&"ad":
			return "Damage your weapon attacks deal, before the target's armor."
		&"ap":
			return "Damage your spells deal, and how much your heals restore."
		&"percent_stat":
			return "Heals you for this share of the damage you deal."
		&"resist_physical":
			return "Reduces weapon damage taken by %d%%." % roundi(_reduction(value) * 100.0)
		&"resist_magic":
			return "Reduces spell damage taken by %d%%." % roundi(_reduction(value) * 100.0)
		&"move_speed":
			var pct: int = roundi((value / _BASE_MOVE_SPEED - 1.0) * 100.0)
			if pct == 0:
				return "How fast you run. Base speed for your character."
			return "How fast you run — %d%% %s than base." % [
				absi(pct), "faster" if pct > 0 else "slower"
			]
		&"haste":
			if value <= 0.0:
				return "Shortens every attack and ability cooldown."
			return "Attacks and abilities come off cooldown %d%% sooner." % roundi(
				(1.0 - 1.0 / (1.0 + value / 100.0)) * 100.0
			)
	return ""


## The damage-taken reduction for a resistance value — mirrors Character.take_damage.
func _reduction(resist: float) -> float:
	return 1.0 - 100.0 / (100.0 + maxf(0.0, resist))


func _stat(key: Variant) -> float:
	return float(observed_stats.values.get(key, 0.0))
