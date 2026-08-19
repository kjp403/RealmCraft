extends Control
## HUD prayer bar — sibling of HealthBar and ManaBar (same stat-sync pattern).
## Smoothly tweens its fill on PRAYER / PRAYER_MAX change. No damage chip:
## spending prayer points isn't "damage", so a lagging red chunk would read wrong.
## Shows drain rate when prayers are active.

const FILL_TIME: float = 0.18

@onready var label: Label = $ProgressBar/Label
@onready var progress_bar: ProgressBar = $ProgressBar
@onready var drain_label: Label = $DrainLabel

var _tween: Tween
var _current_drain: float = 0.0


func _ready() -> void:
	ClientState.local_player_ready.connect(
		func(local_player: LocalPlayer) -> void:
			local_player.stats_component.stats.stat_changed.connect(_on_stat_changed)
			_on_stat_changed(Stat.PRAYER_MAX, local_player.stats_component.get_stat(Stat.PRAYER_MAX))
			_on_stat_changed(Stat.PRAYER, local_player.stats_component.get_stat(Stat.PRAYER))
	)
	# Subscribe to prayer state updates for drain rate
	Client.subscribe(&"prayer.state", _on_prayer_state)


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


func _update_label(value: float) -> void:
	label.text = "%d / %d" % [value, progress_bar.max_value]


func _update_drain_label() -> void:
	if _current_drain > 0.0:
		drain_label.text = "-%.1f/min" % _current_drain
		drain_label.visible = true
	else:
		drain_label.visible = false
