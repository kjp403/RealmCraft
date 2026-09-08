class_name DungeonHud
extends PanelContainer
## Upper-right dungeon-run HUD: a live MM:SS run clock and — on HARD runs — the shared revive count.
## Driven entirely by &"dungeon.hud" pushes from DungeonService: {active, elapsed_s, has_pool,
## revives}. The clock ticks LOCALLY (the server sends the elapsed baseline on entry and re-syncs it
## on each revive change), so there's no per-second network spam. Hidden whenever no run is active.
##
## Wears the same thin pill as BossHuntHud (RunClockChip) and rides the upper-right
## rail under the minimap — see Hud._place_right_rail.

const CHIP: GDScript = preload("res://source/client/ui/hud/run_clock_chip.gd")

var _has_pool: bool = false
var _revives: int = 0
## Local clock baseline: the run-elapsed (seconds) captured at the last push + the ticks_msec then.
var _base_elapsed_s: float = 0.0
var _base_tick_ms: int = 0
var _last_shown_sec: int = -1

var _timer_label: Label
var _revive_label: Label


func _ready() -> void:
	_build_ui()
	visible = false
	set_process(false)
	Client.subscribe(&"dungeon.hud", _on_dungeon_hud)


## {active:false} ends the display; {active:true, elapsed_s, has_pool, revives} shows / updates it.
func _on_dungeon_hud(payload: Dictionary) -> void:
	if not bool(payload.get("active", false)):
		visible = false
		set_process(false)
		return
	# Re-base the local clock whenever the server sends an elapsed (entry + every revive change).
	if payload.has("elapsed_s"):
		_base_elapsed_s = float(payload["elapsed_s"])
		_base_tick_ms = Time.get_ticks_msec()
	_has_pool = bool(payload.get("has_pool", false))
	_revives = int(payload.get("revives", 0))
	_refresh_revives()
	_last_shown_sec = -1 # force an immediate clock redraw
	_update_clock()
	visible = true
	set_process(true)


func _process(_delta: float) -> void:
	_update_clock()


## Tick the MM:SS clock from the local baseline, throttled to one redraw per whole second.
func _update_clock() -> void:
	var elapsed: float = _base_elapsed_s + float(Time.get_ticks_msec() - _base_tick_ms) / 1000.0
	var total: int = maxi(0, int(elapsed))
	if total == _last_shown_sec:
		return
	_last_shown_sec = total
	# float division + floori for the minutes — avoids the int/int "integer division" warning.
	_timer_label.text = "%02d:%02d" % [floori(total / 60.0), total % 60]


## Show "Revives: N" only on HARD runs; redden it at 0 (one more death wipes the run).
func _refresh_revives() -> void:
	_revive_label.visible = _has_pool
	if not _has_pool:
		return
	_revive_label.text = "1 revive" if _revives == 1 else "%d revives" % _revives
	_revive_label.add_theme_color_override(
		&"font_color", CHIP.URGENT if _revives <= 0 else CHIP.DETAIL)


## One thin pill in the toast language, in the upper-right rail. The vertical
## slot belongs to Hud._place_right_rail. Built in code (mirrors the lazily-built
## SparringCountdown) so hud.tscn's unique_id node table is left untouched.
func _build_ui() -> void:
	var row: HBoxContainer = CHIP.dress(self)

	_timer_label = CHIP.timer_label()
	_timer_label.text = "00:00"
	row.add_child(_timer_label)

	_revive_label = CHIP.detail_label()
	_revive_label.text = "0 revives"
	row.add_child(_revive_label)
