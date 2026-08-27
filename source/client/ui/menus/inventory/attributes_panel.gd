extends VBoxContainer
## Attribute spending panel for the Character → Stats tab.
##
## Rows are built from AttributeMap (one source of truth with the server), and
## each one spells out three things a player actually cares about: what the
## attribute is FOR in plain English, what their points have granted so far,
## and exactly what the next point will add. Raw stat keys never reach the UI.

var attributes: Dictionary
var available_points: int:
	set = _set_available_points

@onready var available_points_label: Label = $AvailablePointsLabel

## Human-readable stat names for the per-attribute breakdowns. Anything missing
## falls back to Stat.display_name().
## Short forms on purpose: these appear twice per row (total + next point), so
## the full "Ability Power"-style names wrap the row onto three lines.
const STAT_LABELS: Dictionary = {
	&"health_max": "Max HP",
	&"health_regen": "HP Regen",
	&"ad": "Attack",
	&"ap": "Magic",
	&"armor": "Armor",
	&"mr": "Magic Res",
	&"mana_max": "Mana",
	&"mana_regen": "Mana Regen",
	&"move_speed": "Move Speed",
	&"ability_haste": "Haste",
}

## Stats reported per second rather than as a flat number.
const PER_SECOND_STATS: PackedStringArray = ["health_regen", "mana_regen"]

## Attributes whose stats aren't wired into gameplay yet — add a name here to
## disable its row with a "Coming soon" tag. Empty since the magic update.
const LOCKED_ATTRIBUTES: PackedStringArray = []

## attribute name -> {"points": Label, "gain": Label, "button": Button}.
var _rows: Dictionary = {}


func _ready() -> void:
	add_theme_constant_override(&"separation", 6)
	_build_rows()
	# Re-fetch every time the panel becomes visible — without this, the values
	# shown reflect the first open only, and a mid-session level-up leaves the
	# panel reporting stale "available points" until relog.
	visibility_changed.connect(_refetch_if_visible)
	_refetch_if_visible()


func _refetch_if_visible() -> void:
	if not visible:
		return
	Client.request_data(
		&"attribute.get",
		_on_attribute_received,
		{},
		InstanceClient.current.name
	)


func _build_rows() -> void:
	for attribute_name: StringName in AttributeMap.ORDER:
		_build_row(attribute_name)


## One attribute: coloured name + spent points + [+], the plain-English pitch,
## and a "your points give X / next point gives Y" breakdown.
func _build_row(attribute_name: StringName) -> void:
	var locked: bool = String(attribute_name) in LOCKED_ATTRIBUTES

	var row: PanelContainer = PanelContainer.new()
	row.add_theme_stylebox_override(&"panel", _row_stylebox(AttributeMap.color_for(attribute_name)))
	add_child(row)

	var pad: MarginContainer = MarginContainer.new()
	pad.add_theme_constant_override(&"margin_left", 10)
	pad.add_theme_constant_override(&"margin_right", 10)
	pad.add_theme_constant_override(&"margin_top", 6)
	pad.add_theme_constant_override(&"margin_bottom", 6)
	row.add_child(pad)

	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 2)
	pad.add_child(body)

	# --- Header line: name, spent points, + button ---
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 8)
	body.add_child(header)

	var name_label: Label = Label.new()
	name_label.text = AttributeMap.label_for(attribute_name)
	name_label.add_theme_font_size_override(&"font_size", 14)
	name_label.add_theme_color_override(&"font_color", AttributeMap.color_for(attribute_name))
	header.add_child(name_label)

	var points_label: Label = Label.new()
	points_label.text = "0"
	points_label.add_theme_font_size_override(&"font_size", 14)
	points_label.add_theme_color_override(&"font_color", Color(0.95, 0.95, 1.0))
	points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	points_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	points_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(points_label)

	var button: Button = Button.new()
	button.text = "+"
	button.custom_minimum_size = Vector2(30, 30)
	header.add_child(button)

	# --- What it's for, in one line ---
	var blurb: Label = Label.new()
	blurb.text = "Coming soon" if locked else AttributeMap.blurb_for(attribute_name)
	blurb.add_theme_font_size_override(&"font_size", 10)
	blurb.add_theme_color_override(&"font_color", Color(0.6, 0.63, 0.72))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(blurb)

	# --- Current total / next point ---
	var gain: Label = Label.new()
	gain.add_theme_font_size_override(&"font_size", 11)
	gain.add_theme_color_override(&"font_color", Color(0.78, 0.82, 0.9))
	gain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(gain)

	if locked:
		row.modulate.a = 0.5
		button.disabled = true
		button.tooltip_text = "Unlocks with the magic update."
	else:
		button.pressed.connect(_on_attribute_pressed.bind(attribute_name))

	_rows[attribute_name] = {"points": points_label, "gain": gain, "button": button}
	_refresh_row(attribute_name)


func _row_stylebox(accent: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color(1, 1, 1, 0.03)
	box.border_color = Color(accent.r, accent.g, accent.b, 0.35)
	box.set_border_width_all(1)
	box.border_width_left = 3
	box.set_corner_radius_all(4)
	return box


## "Now: +12 Attack   ·   +1 Attack per point"
func _refresh_row(attribute_name: StringName) -> void:
	if not _rows.has(attribute_name):
		return
	var spent: int = int(attributes.get(String(attribute_name), 0))
	var row: Dictionary = _rows[attribute_name]
	(row["points"] as Label).text = str(spent)

	var text: String = "%s per point" % _describe(AttributeMap.stats_for(attribute_name))
	if spent > 0:
		var total: Dictionary = AttributeMap.attr_to_stats({attribute_name: spent})
		text = "Now: %s   •   %s" % [_describe(total), text]
	(row["gain"] as Label).text = text


## "+3 Max Health, +0.03 Health Regen/s" — a stat table in player-facing words.
func _describe(stats: Dictionary) -> String:
	var parts: PackedStringArray = []
	for stat_name: StringName in stats:
		var value: float = float(stats[stat_name])
		var label: String = str(STAT_LABELS.get(stat_name, Stat.display_name(stat_name)))
		var suffix: String = "/s" if String(stat_name) in PER_SECOND_STATS else ""
		# Trim trailing zeros so whole numbers read "+3", not "+3.00".
		var amount: String = ("%.2f" % value).rstrip("0").rstrip(".")
		parts.append("+%s %s%s" % [amount, label, suffix])
	return ", ".join(parts)


func _on_attribute_pressed(attribute_name: StringName) -> void:
	# Checked on the server too.
	if available_points <= 0:
		return
	available_points -= 1

	var key: String = String(attribute_name)
	attributes[key] = int(attributes.get(key, 0)) + 1
	_refresh_row(attribute_name)

	var stats: Dictionary = AttributeMap.stats_for(attribute_name)
	for stat_name: StringName in stats:
		if ClientState.stats.data.has(stat_name):
			ClientState.stats.data[stat_name] += stats[stat_name]
		else:
			ClientState.stats.data[stat_name] = stats[stat_name]
	Client.data_push(&"stats.update", ClientState.stats.data)

	Client.request_data(
		&"attribute.spend",
		Callable(),
		{"attr": key},
		InstanceClient.current.name
	)


func _on_attribute_received(data: Dictionary) -> void:
	# Keys can arrive as String or StringName depending on the transport; key the
	# local copy by String so the spend path can't create a duplicate entry.
	attributes = {}
	var received: Dictionary = data.get("attr", {})
	for key: Variant in received:
		attributes[String(key)] = int(received[key])
	available_points = data.get("points", 0)
	for attribute_name: StringName in _rows:
		_refresh_row(attribute_name)


func _set_available_points(value: int) -> void:
	available_points = value
	if available_points_label:
		available_points_label.text = (
			"Available points: %d" % value if value > 0
			else "No points to spend — earn more by raising your Combat Level"
		)
		available_points_label.add_theme_color_override(
			&"font_color", Color(1, 0.85, 0.4) if value > 0 else Color(0.6, 0.63, 0.72)
		)
	for attribute_name: StringName in _rows:
		var button: Button = _rows[attribute_name]["button"]
		if not button.tooltip_text.begins_with("Unlocks"):
			button.disabled = value <= 0
