extends Control
## HUD prayer bar — sibling of HealthBar and ManaBar (same stat-sync pattern).
## Smoothly tweens its fill on PRAYER / PRAYER_MAX change. No damage chip:
## spending prayer points isn't "damage", so a lagging red chunk would read wrong.
## Shows drain rate when prayers are active.

const FILL_TIME: float = 0.18
const QUICK_ON: Color = Color(0.93, 0.80, 0.35)
const QUICK_OFF: Color = Color(0.72, 0.76, 0.84)

@onready var label: Label = $ProgressBar/Label
@onready var progress_bar: ProgressBar = $ProgressBar
@onready var drain_label: Label = $DrainLabel
@onready var quick_button: Button = $QuickButton

var _tween: Tween
var _current_drain: float = 0.0
var _active: Array = []
var _busy: bool = false


func _ready() -> void:
	ClientState.local_player_ready.connect(
		func(local_player: LocalPlayer) -> void:
			local_player.stats_component.stats.stat_changed.connect(_on_stat_changed)
			_on_stat_changed(Stat.PRAYER_MAX, local_player.stats_component.get_stat(Stat.PRAYER_MAX))
			_on_stat_changed(Stat.PRAYER, local_player.stats_component.get_stat(Stat.PRAYER))
	)
	# Subscribe to prayer state updates for drain rate
	Client.subscribe(&"prayer.state", _on_prayer_state)
	quick_button.pressed.connect(_on_quick_pressed)
	ClientState.quick_prayers_changed.connect(_update_quick_button)
	_update_quick_button()


func _on_stat_changed(stat_name: StringName, value: float) -> void:
	if stat_name == Stat.PRAYER:
		if _tween != null and _tween.is_valid():
			_tween.kill()
		_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tween.tween_property(progress_bar, ^"value", value, FILL_TIME)
		_update_label(value)
	elif stat_name == Stat.PRAYER_MAX:
		progress_bar.max_value = value
		_update_label(progress_bar.value)


func _on_prayer_state(payload: Dictionary) -> void:
	var drain: float = float(payload.get("drain", 0.0))
	_current_drain = drain
	_update_drain_label()
	if payload.has("active"):
		_active = payload.get("active", [])
	_update_quick_button()


## One click flips the WHOLE starred set (see quick_prayers.gd for how that set
## is built). No local optimism: the button repaints from the server's own
## snapshot, same rule as the panel's individual toggles -- a partially-refused
## batch (ran out of points partway through) must show what actually happened,
## not what the click hoped for.
func _on_quick_pressed() -> void:
	if _busy:
		return
	var quick_set: Array[StringName] = QuickPrayers.load_set()
	if quick_set.is_empty():
		Toaster.toast("No quick prayers set. Star some in the Prayer book.")
		return
	if InstanceClient.current == null:
		return
	_busy = true
	var slugs: PackedStringArray = PackedStringArray()
	for slug: StringName in quick_set:
		slugs.append(String(slug))
	var result: Array = await Client.request_data_await(
		&"prayer.quick_toggle", {"slugs": slugs}, String(InstanceClient.current.name)
	)
	_busy = false
	var payload: Dictionary = result[0] if result.size() > 0 and result[0] is Dictionary else {}
	if not bool(payload.get("ok", false)):
		Toaster.toast("Could not toggle quick prayers.")
		return
	_active = payload.get("active", [])
	var skipped: Array = payload.get("skipped", [])
	if not skipped.is_empty():
		Toaster.toast("Not enough prayer points for %d of your quick prayers." % skipped.size())
	_update_quick_button()


## Amber + pressed when every starred prayer is currently active, muted
## otherwise -- so the button itself answers "is my set fully on" at a glance,
## the same at-rest readability the panel's star colour gives per-row.
func _update_quick_button() -> void:
	if quick_button == null:
		return
	var quick_set: Array[StringName] = QuickPrayers.load_set()
	quick_button.disabled = quick_set.is_empty()
	if quick_set.is_empty():
		quick_button.tooltip_text = "Star prayers in the Prayer book to set these up."
		quick_button.add_theme_color_override(&"font_color", QUICK_OFF)
		return
	var all_on: bool = true
	for slug: StringName in quick_set:
		if not _active.has(String(slug)):
			all_on = false
			break
	quick_button.tooltip_text = (
		"Turn off your quick prayers" if all_on else "Turn on your quick prayers"
	)
	quick_button.add_theme_color_override(&"font_color", QUICK_ON if all_on else QUICK_OFF)


func _update_label(value: float) -> void:
	label.text = "%d / %d" % [value, progress_bar.max_value]


func _update_drain_label() -> void:
	if _current_drain > 0.0:
		drain_label.text = "-%.1f/min" % _current_drain
		drain_label.visible = true
	else:
		drain_label.visible = false
