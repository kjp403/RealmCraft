extends PanelContainer
## Read-only stat readout for the Character → Stats tab.
##
## Every row is "what the number is" PLUS "what it does for you" in plain
## English, and — the point of the panel — WHERE the number came from: base,
## the gear you have on, and the attribute points you spent. The split is live,
## so swapping one piece of armor visibly moves the Gear share and flashes the
## change, which is how a player judges two pieces against each other (and how
## hybrid armor reads at all, since it moves several rows at once).
##
## Rows are grouped (Vitals / Offense / Defense / Utility) and hidden when a
## stat is inert (no mana pool → no mana rows), so the sheet never shows a
## meaningless 0.

## Section header → rows. Row = [label, color, stat key, kind].
## kind drives the value format, the explainer line, and the breakdown.
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

## Armor values sampled in the Attack Damage row. Roughly "unarmored / light /
## average / heavy" for the armor players actually meet, so the row answers
## "what do I hit a target with N armor for?" without a calculator.
const _ARMOR_SAMPLES: Array[int] = [0, 25, 50, 100]

## How long a gear-swap change keeps flashing next to its value.
const _DELTA_HOLD_S: float = 6.0

var observed_stats: StatsComponent.Stats

var _rows_box: VBoxContainer
## Spent attribute points, fetched from the server — one half of the breakdown.
var _attributes: Dictionary = {}
## Live values as of the last redraw, so the next one can show what moved.
var _previous: Dictionary = {}
## stat key -> delta still being shown.
var _deltas: Dictionary = {}
var _delta_timer: SceneTreeTimer
var _redraw_queued: bool = false


func _ready() -> void:
	_build_layout()
	_try_watch()
	ClientState.local_player_ready.connect(func(_lp: LocalPlayer): _try_watch())
	visibility_changed.connect(_refetch_if_visible)
	_refetch_if_visible()


## The attribute split has to come from the server (the client never holds the
## authoritative spread), and it changes while the panel is open — a point spent
## in the panel beside this one has to move this one's Points column too.
func _refetch_if_visible() -> void:
	if not visible or InstanceClient.current == null:
		return
	Client.request_data(
		&"attribute.get",
		func(data: Dictionary) -> void:
			_attributes = data.get("attr", {})
			_queue_redraw(),
		{},
		InstanceClient.current.name
	)


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
	scroll.name = "StatsScroll"
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

	_previous.clear()
	_deltas.clear()
	redraw()


## An equip touches several stats in the same frame (and hybrid armor touches
## most of them), so record what moved, then rebuild ONCE.
func _on_stats_changed(stat_name: StringName, value: float) -> void:
	if _previous.has(stat_name):
		var delta: float = value - float(_previous[stat_name])
		if not is_zero_approx(delta):
			_deltas[stat_name] = float(_deltas.get(stat_name, 0.0)) + delta
			_start_delta_timer()
	_queue_redraw()


func _queue_redraw() -> void:
	if _redraw_queued:
		return
	_redraw_queued = true
	redraw.call_deferred()


## Deltas are a "look what your new gloves did" cue, not permanent state — drop
## them after a beat so the sheet settles back to plain values.
func _start_delta_timer() -> void:
	if _delta_timer != null and _delta_timer.time_left > 0.0:
		return
	_delta_timer = get_tree().create_timer(_DELTA_HOLD_S)
	_delta_timer.timeout.connect(func() -> void:
		_deltas.clear()
		_queue_redraw())


func redraw() -> void:
	_redraw_queued = false
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

	for section: Array in _SECTIONS:
		for row: Array in section[1]:
			_previous[row[2]] = _stat(row[2])


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

	_add_note(text_box, _explain(row), Color(0.58, 0.61, 0.7))
	_add_note(text_box, _breakdown(row), Color(0.52, 0.56, 0.66))
	_add_note(text_box, _extra(row), Color(0.72, 0.63, 0.45))

	var value_box: VBoxContainer = VBoxContainer.new()
	value_box.add_theme_constant_override(&"separation", 0)
	value_box.custom_minimum_size.x = 78
	hbox.add_child(value_box)

	var value_label: Label = Label.new()
	value_label.text = _value_text(row)
	value_label.add_theme_font_size_override(&"font_size", 15)
	value_label.add_theme_color_override(&"font_color", row[1])
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_box.add_child(value_label)

	# The gear-swap flash: what this stat just gained or lost.
	var delta: float = float(_deltas.get(row[2], 0.0))
	if not is_zero_approx(delta):
		var delta_label: Label = Label.new()
		delta_label.text = "%s%s" % ["+" if delta > 0.0 else "−", _number(absf(delta))]
		delta_label.add_theme_font_size_override(&"font_size", 11)
		delta_label.add_theme_color_override(
			&"font_color", Color("#5fd35f") if delta > 0.0 else Color("#e06c6c")
		)
		delta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_box.add_child(delta_label)


func _add_note(parent: Control, text: String, color: Color) -> void:
	if text.is_empty():
		return
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 10)
	label.add_theme_color_override(&"font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)


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
			return "Damage a basic weapon attack deals before the target's armor."
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


## "Base 3   ·   Gear +42   ·   Points +14" — where the number on the right came
## from. Gear is what's left after base and attributes, so a buff or a mastery
## passive lands in it too; that is the honest reading of "everything you have
## on and running right now".
func _breakdown(row: Array) -> String:
	var stat_name: StringName = row[2]
	if row[3] == &"percent_stat":
		return ""
	var base: float = _base_of(stat_name)
	var from_points: float = float(_attribute_stats().get(stat_name, 0.0))
	var gear: float = _stat(stat_name) - base - from_points

	var parts: PackedStringArray = ["Base %s" % _number(base)]
	if not is_zero_approx(gear):
		parts.append("Gear %s%s" % ["+" if gear > 0.0 else "−", _number(absf(gear))])
	if not is_zero_approx(from_points):
		parts.append("Points +%s" % _number(from_points))
	return "   ·   ".join(parts)


## Attack Damage's follow-up question, answered inline: what a basic hit lands
## for once the target's armor eats its share. Same curve the server applies in
## Character.take_damage, on the same AD a basic swing/shot uses.
func _extra(row: Array) -> String:
	if row[3] != &"ad":
		return ""
	var ad: float = _stat(Stat.AD)
	if ad <= 0.0:
		return ""
	var parts: PackedStringArray = []
	for armor: int in _ARMOR_SAMPLES:
		parts.append("%d vs %d" % [roundi(ad * 100.0 / (100.0 + float(armor))), armor])
	return "Per hit:   %s armor" % "   ·   ".join(parts)


## What this stat is worth before gear and attribute points: BASE_STATS, plus
## the free max HP every level grants (the same composition the server spawns
## with, so the three columns always add up to the value on the right).
func _base_of(stat_name: StringName) -> float:
	var base: float = float(PlayerResource.BASE_STATS.get(stat_name, 0.0))
	if stat_name == Stat.HEALTH_MAX:
		base += PlayerResource.HEALTH_PER_LEVEL * float(maxi(ClientState.player_level, 1) - 1)
	return base


func _attribute_stats() -> Dictionary:
	return AttributeMap.attr_to_stats(_attributes)


## The damage-taken reduction for a resistance value — mirrors Character.take_damage.
func _reduction(resist: float) -> float:
	return 1.0 - 100.0 / (100.0 + maxf(0.0, resist))


## Whole numbers read as "42", fractions keep just enough to be meaningful.
func _number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return "%d" % roundi(value)
	return ("%.1f" % value).rstrip("0").rstrip(".")


func _stat(key: Variant) -> float:
	return float(observed_stats.values.get(key, 0.0))
