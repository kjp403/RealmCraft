class_name BossHuntHud
extends PanelContainer
## Upper-right Boss Hunt HUD: a live MM:SS clock counting DOWN to the end of the
## contract, plus the boss's name, the running kill tally, and the lives the
## party has left (BossHuntService.CONTRACT_LIVES, shared however many hunters
## are in the arena — losing the last one fails the contract).
##
## Driven entirely by &"boss_hunt.hud" pushes from BossHuntService:
## {active, remaining_s, boss, kills, lives}. Like DungeonHud, the clock ticks LOCALLY
## from the baseline the server sends (on entry and on every kill), so there is
## no per-second network spam. Hidden whenever no contract is running.
##
## A separate node from DungeonHud rather than a mode flag on it: that one counts
## UP with no end, this one counts DOWN and goes red at the wire, and a run and a
## contract can never be active at the same time anyway. Both wear the same thin
## pill (RunClockChip) and ride the upper-right rail — see Hud._place_right_rail.

## Below this many seconds the clock turns red — time to spend your potions.
const URGENT_S: int = 60

const CHIP: GDScript = preload("res://source/client/ui/hud/run_clock_chip.gd")

var _kills: int = 0
## Shared lives left. -1 until the first push carries one, so an older server
## that does not send the field shows the clock alone rather than "0 lives".
var _lives: int = -1
## Local clock baseline: remaining seconds at the last push + the ticks_msec then.
var _base_remaining_s: float = 0.0
var _base_tick_ms: int = 0
var _last_shown_sec: int = -1

var _timer_label: Label
var _detail_label: Label


func _ready() -> void:
	_build_ui()
	visible = false
	set_process(false)
	Client.subscribe(&"boss_hunt.hud", _on_hud)


## {active:false} ends the display; {active:true, remaining_s, boss, kills} shows
## or updates it.
func _on_hud(payload: Dictionary) -> void:
	if not bool(payload.get("active", false)):
		visible = false
		set_process(false)
		return
	if payload.has("remaining_s"):
		_base_remaining_s = float(payload["remaining_s"])
		_base_tick_ms = Time.get_ticks_msec()
	_kills = int(payload.get("kills", _kills))
	_lives = int(payload.get("lives", _lives))
	_refresh_detail()
	_last_shown_sec = -1 # force an immediate clock redraw
	_update_clock()
	visible = true
	set_process(true)


func _process(_delta: float) -> void:
	_update_clock()


## Tick the countdown from the local baseline, throttled to one redraw per whole
## second. Floors at 00:00 — the server owns the actual expiry.
func _update_clock() -> void:
	var remaining: float = _base_remaining_s - float(Time.get_ticks_msec() - _base_tick_ms) / 1000.0
	var total: int = maxi(0, int(remaining))
	if total == _last_shown_sec:
		return
	_last_shown_sec = total
	# float division + floori for the minutes — avoids the int/int "integer division" warning.
	_timer_label.text = "%02d:%02d" % [floori(total / 60.0), total % 60]
	_timer_label.add_theme_color_override(
		&"font_color", CHIP.URGENT if total <= URGENT_S else CHIP.INK)


## "3 killed · 2 lives". The lives segment goes red on the last one — that death
## ends the contract, so it should read as a warning, not a number. Omitted
## entirely until a push has actually carried the field.
##
## The boss is NOT named here: the entry banner named it, the boss bar names it
## through the whole fight, and the name was the single widest thing on a chip
## that has to fit the right rail's 224px lane.
func _refresh_detail() -> void:
	var parts: PackedStringArray = PackedStringArray()
	parts.append("%d killed" % _kills)
	if _lives >= 0:
		parts.append("%d %s" % [_lives, "life" if _lives == 1 else "lives"])
	_detail_label.text = "  ·  ".join(parts)
	_detail_label.add_theme_color_override(
		&"font_color", CHIP.URGENT if _lives == 1 else CHIP.DETAIL)


## One thin pill in the toast language, in the upper-right rail. The vertical
## slot belongs to Hud._place_right_rail. Built in code (mirrors DungeonHud) so
## hud.tscn's unique_id node table is left untouched.
func _build_ui() -> void:
	var row: HBoxContainer = CHIP.dress(self)

	_timer_label = CHIP.timer_label()
	_timer_label.text = "30:00"
	row.add_child(_timer_label)

	_detail_label = CHIP.detail_label()
	_detail_label.text = "0 killed"
	row.add_child(_detail_label)
