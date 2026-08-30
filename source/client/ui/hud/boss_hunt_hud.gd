class_name BossHuntHud
extends PanelContainer
## Top-center Boss Hunt HUD: a live MM:SS clock counting DOWN to the end of the
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
## contract can never be active at the same time anyway.

## Below this many seconds the clock turns red — time to spend your potions.
const URGENT_S: int = 60

var _boss: String = ""
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
	_boss = str(payload.get("boss", _boss))
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
		&"font_color", Color(1.0, 0.42, 0.38) if total <= URGENT_S else Color(1, 1, 1))


## "Fungal Heart · 3 killed · 2 lives". The lives segment goes red on the last
## one — that death ends the contract, so it should read as a warning, not a
## number. Omitted entirely until a push has actually carried the field.
func _refresh_detail() -> void:
	var parts: PackedStringArray = PackedStringArray()
	if not _boss.is_empty():
		parts.append(_boss)
	parts.append("%d killed" % _kills)
	if _lives >= 0:
		parts.append("%d %s" % [_lives, "life" if _lives == 1 else "lives"])
	_detail_label.text = "  ·  ".join(parts)
	_detail_label.add_theme_color_override(
		&"font_color",
		Color(1.0, 0.42, 0.38) if _lives == 1 else Color(1.0, 0.88, 0.6))


## Compact dark panel, top-center just below the status-effect strip — same slot
## and styling as DungeonHud (the two are mutually exclusive).
func _build_ui() -> void:
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_top = 44.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_END
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel: StyleBoxFlat = StyleBoxFlat.new()
	panel.bg_color = Color(0.06, 0.06, 0.08, 0.55)
	panel.content_margin_top = 5
	panel.content_margin_bottom = 5
	panel.content_margin_left = 20
	panel.content_margin_right = 20
	add_theme_stylebox_override(&"panel", panel)

	var box: VBoxContainer = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	_timer_label = Label.new()
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override(&"font_size", 26)
	_timer_label.text = "30:00"
	_timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_timer_label)

	_detail_label = Label.new()
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_label.add_theme_font_size_override(&"font_size", 14)
	_detail_label.add_theme_color_override(&"font_color", Color(1.0, 0.88, 0.6))
	_detail_label.text = "0 killed"
	_detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_detail_label)
