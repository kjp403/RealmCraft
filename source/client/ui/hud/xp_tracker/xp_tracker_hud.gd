class_name XpTrackerHud
extends Control
## Radial XP orb: a notched ring that fills toward the next level in whichever
## skill the player is currently training, with the floating "+N xp" numbers
## rising off it.
##
## Fed by [signal ClientState.skill_xp_gained], the one client-side door every
## XP path funnels through — gathering, crafting, salvage, altar offerings,
## daily-board claims and Slayer kills all arrive here in the same shape, so the
## orb works for a skill nobody has written yet without a line of new code. The
## orb follows the LAST skill to pay out: skilling is a one-thing-at-a-time
## activity, and a player who chops for a minute then mines wants the orb to
## follow them, not to pick one skill and stick to it.
##
## The gauge is drawn at its authored 1x size and never scaled — see
## tools/build_ui_frames.py, which cuts the casing, the fill band and the spark
## from one set of radii. Scaling it by anything but a whole number resamples
## the quarter notches into mush, which is the entire reason they are notches
## and not painted ticks.
##
## Level-ups are flagged by the SERVER on the same event that pays the XP, so
## the orb never has to guess from the level moving — switching skills moves it
## further than any level-up does. They are LOCAL only: the icon flashes,
## particles burst behind the casing, the arc wraps to zero. The fireworks, the
## jingle and the "your Mining level has achieved N" line all belong to
## [LevelUpFx], which already fires off the same server payload — doubling them
## puts two celebrations on one event.

const TOOLTIP_SCENE: String = "res://source/client/ui/hud/xp_tracker/xp_tracker_tooltip.tscn"

## Client setting that switches the orb off, stored the same way the Slayer
## badge stores its own (see [SlayerTracker]). Absent means on.
const SETTING_SECTION: StringName = &"general"
const SETTING_PROPERTY: StringName = &"xp_tracker"

## Ring geometry, mirrored from tools/build_ui_frames.py. Change it there and
## re-run the generator, then change it here — the spark rides a circle these
## numbers describe, and a mismatch floats it off the arc.
const CASING_DIAMETER: float = 48.0
## Radius the spark travels on: the middle of the fill band (XP_R_IN 17,
## XP_R_OUT 23).
const SPARK_RADIUS: float = 20.0

## Where the floating numbers hang from, in orb-local pixels: the LEFT edge,
## low in the casing. Both halves matter and both are about the minimap
## ([NavigationMinimap] ends at y=120, z_index 80, opaque) sitting directly
## above the orb at y=128:
##   x = -6  — just off the casing, with the text growing further left into
##             open play area rather than back under the rail.
##   y = 30  — low enough that the whole 26px rise ([constant
##             XpFloatingTextManager.DRIFT_PX]) tops out at y=132, clear of the
##             minimap. Anchored above the orb instead, every number was drawn
##             behind the minimap panel and no player ever saw one.
const DROPS_ANCHOR: Vector2 = Vector2(-6.0, 30.0)

## How long the orb stays up after the last XP tick.
const AUTO_HIDE_SECONDS: float = 4.0
## Fade used when the orb comes and goes.
const FADE_TIME: float = 0.22
## Micro-pulse on every tick. 1.05 is deliberately small — this fires on EVERY
## skilling tick, several a second, and a bigger pop turns a gathering session
## into a pumping heartbeat.
const PULSE_SCALE: float = 1.05
const PULSE_TIME: float = 0.09
## How long the arc takes to catch up to a new value. Short enough to feel
## connected to the click that earned it.
const FILL_TIME: float = 0.28
## The level-up wrap: run the arc up to full, snap to empty, then fill to the
## real remainder.
const WRAP_UP_TIME: float = 0.22
const WRAP_IN_TIME: float = 0.34

## Per-skill arc tint and floating-number colour. Keyed on the job SLUG, so
## Crafting is `outfitting` and Farming is `harvesting` — see [JobRegistry].
## An unlisted skill falls back to [constant PixelUI.INK_XP] rather than going
## untinted, so a new job looks deliberate on the day it ships.
const SKILL_TINTS: Dictionary[StringName, Color] = {
	&"mining": Color(0.60, 0.72, 0.86),       # cold steel
	&"woodcutting": Color(0.48, 0.76, 0.42),  # green timber
	&"fishing": Color(0.40, 0.80, 0.88),      # sea
	&"cooking": Color(1.00, 0.62, 0.34),      # ember
	&"smithing": Color(1.00, 0.48, 0.18),     # forge fire
	&"fletching": Color(0.78, 0.60, 0.36),    # cut wood
	&"outfitting": Color(0.72, 0.56, 0.92),   # dyed thread (Crafting)
	&"herblore": Color(0.50, 0.90, 0.70),     # crushed herb
	&"harvesting": Color(0.92, 0.82, 0.42),   # wheat (Farming)
	&"prayer": Color(0.82, 0.88, 1.00),       # cold light
	&"slayer": Color(0.88, 0.32, 0.30),       # blood
}

@onready var _gauge: Control = $Gauge
@onready var _burst: CPUParticles2D = $Gauge/Burst
@onready var _arc: TextureProgressBar = $Gauge/Arc
@onready var _icon: TextureRect = $Gauge/Icon
@onready var _spark: Sprite2D = $Gauge/Spark
@onready var _drops: XpFloatingTextManager = $Drops

## The skill the orb is currently showing.
var _job: StringName = &""
var _level: int = 1
var _xp_into_level: int = 0
var _xp_to_next: int = 1

var _hide_timer: Timer
var _fill_tween: Tween
var _pulse_tween: Tween
var _fade_tween: Tween
## True while the pointer is over the orb: the auto-hide is paused so a player
## reading the breakdown doesn't have it vanish mid-sentence.
var _hovered: bool = false
## Hand-placed hover card, built only on web — see [method _build_web_card].
var _web_card: XpTrackerTooltip


## Whether the player has the orb switched on (default true). Static so the
## settings panel can read and write it without reaching into the HUD.
static func is_enabled() -> bool:
	var value: Variant = ClientState.settings.get_value(SETTING_SECTION, SETTING_PROPERTY)
	if value == null:
		value = ClientState.settings.get_default(SETTING_SECTION, SETTING_PROPERTY)
	return true if value == null else bool(value)


static func set_enabled(enabled: bool) -> void:
	ClientState.settings.set_value(SETTING_SECTION, SETTING_PROPERTY, enabled)


## Arc tint for [param job], falling back to the generic XP blue.
static func tint_for(job: StringName) -> Color:
	return SKILL_TINTS.get(job, PixelUI.INK_XP)


func _ready() -> void:
	PixelUI.make_pixel_perfect(self)
	# Nearest is inherited by every child that doesn't override it, but the arc
	# and the spark are the two that would actually show the blur, so they say so
	# for themselves in the scene as well.
	_gauge.pivot_offset = Vector2(CASING_DIAMETER, CASING_DIAMETER) * 0.5
	# Set here rather than trusted from the scene: the number that decides whether
	# a drop is visible at all belongs next to the comment explaining it.
	_drops.position = DROPS_ANCHOR

	_hide_timer = Timer.new()
	_hide_timer.one_shot = true
	_hide_timer.wait_time = AUTO_HIDE_SECONDS
	_hide_timer.timeout.connect(_on_hide_timeout)
	add_child(_hide_timer)

	modulate.a = 0.0
	visible = false
	set_process(false)

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	if UiGlyphs.is_web():
		# Godot's tooltip popups never render in the HTML5 export, so the web
		# build gets a card this node places itself. Same scene, same copy.
		_build_web_card()
		gui_input.connect(_on_web_gui_input)
	else:
		# _make_custom_tooltip is only consulted when there IS tooltip text, so
		# this non-empty placeholder is what switches the card on. It is never
		# displayed: the override replaces it wholesale.
		tooltip_text = " "

	ClientState.skill_xp_gained.connect(_on_skill_xp_gained)
	ClientState.settings.setting_changed.connect(_on_setting_changed)


## Orb-only hit testing. The control's rect is a square and the gauge is a
## circle, so without this the four corners swallow clicks that were aimed past
## the orb — and LMB out there is click-to-move, so the player reads a dropped
## corner click as the game ignoring them.
func _has_point(point: Vector2) -> bool:
	var centre := Vector2(CASING_DIAMETER, CASING_DIAMETER) * 0.5
	return point.distance_to(centre) <= CASING_DIAMETER * 0.5


## Only runs while the orb is on screen: one sin/cos a frame is cheap, but not
## worth paying for a widget that is hidden most of a session.
func _process(_delta: float) -> void:
	_place_spark()


# ---------------------------------------------------------------------------
# XP intake
# ---------------------------------------------------------------------------

func _on_skill_xp_gained(
	job: StringName,
	amount: int,
	xp_into_level: int,
	level: int,
	leveled_up: bool,
) -> void:
	if not is_enabled():
		return
	var tint: Color = tint_for(job)
	# The number floats whatever the orb does, so a skill that pays out while
	# the orb is mid-fade still reads.
	_drops.push(job, amount, tint)

	var switched: bool = job != _job
	_job = job
	_level = level
	_xp_into_level = maxi(xp_into_level, 0)
	# The denominator never travels: it is a static curve both sides share.
	# At the cap there is no next level, so the arc is pinned full rather than
	# dividing by zero.
	_xp_to_next = maxi(SkillXp.xp_to_next(level), 0)

	if switched:
		_dress_for_job(job, tint)
	_show()
	_pulse()
	# Taken from the server, never inferred from the level moving: on the first
	# tick of a session there is nothing to compare against, and a level-up that
	# lands on the same event as a skill switch would read as neither.
	if leveled_up:
		_play_level_up(tint)
	else:
		_fill_to(_target_ratio(), FILL_TIME)


## Fraction of the way to the next level, 0..1. A capped skill reads as full:
## it is not "0% of nothing".
func _target_ratio() -> float:
	if _xp_to_next <= 0:
		return 1.0
	return clampf(float(_xp_into_level) / float(_xp_to_next), 0.0, 1.0)


## Swap the centre icon and the arc colour to the new skill.
func _dress_for_job(job: StringName, tint: Color) -> void:
	_icon.texture = JobRegistry.icon_for(job)
	_arc.tint_progress = tint
	# Lightened, not the flat tint: a bead the same colour as the arc it rides
	# vanishes into it. The leading edge has to read as the hot end of the fill.
	_spark.modulate = tint.lightened(0.6)
	_burst.color = tint
	# A skill change is not progress in the skill being switched TO, so the arc
	# jumps rather than sweeping — sweeping from Mining's 80% to Fletching's 10%
	# animates a loss the player did not suffer.
	_arc.value = _target_ratio() * _arc.max_value
	_place_spark()


# ---------------------------------------------------------------------------
# Animation
# ---------------------------------------------------------------------------

## Put the spark on the leading edge of the fill.
##
## The arc fills clockwise from the top, so the leading edge is at
## `ratio` of a full turn measured that way: x uses sin and y uses -cos, which
## puts 0 at the top and a quarter turn at the right — the same convention
## _ring_geometry uses in the generator to place the 25% notch. Rounded to whole
## pixels, or the bead shimmers as it crawls.
func _place_spark() -> void:
	var ratio: float = 0.0
	if _arc.max_value > 0.0:
		ratio = _arc.value / _arc.max_value
	# Hidden at both ends: at 0 there is no leading edge yet, and at a full bar
	# the bead would sit on the seam looking like a notch that came loose.
	_spark.visible = ratio > 0.001 and ratio < 0.999
	if not _spark.visible:
		return
	var theta: float = ratio * TAU
	var centre := Vector2(CASING_DIAMETER, CASING_DIAMETER) * 0.5
	_spark.position = Vector2(
		roundf(centre.x + sin(theta) * SPARK_RADIUS),
		roundf(centre.y - cos(theta) * SPARK_RADIUS),
	)


func _fill_to(ratio: float, duration: float) -> void:
	if _fill_tween != null and _fill_tween.is_valid():
		_fill_tween.kill()
	_fill_tween = create_tween()
	_fill_tween.tween_property(_arc, ^"value", ratio * _arc.max_value, duration)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _pulse() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(_gauge, ^"scale", Vector2.ONE * PULSE_SCALE, PULSE_TIME)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_property(_gauge, ^"scale", Vector2.ONE, PULSE_TIME)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


## Local level-up: run the arc up to full, flash the icon, burst the particles,
## then wrap to empty and fill to whatever carried over. The world-level
## celebration is [LevelUpFx]'s and is deliberately not repeated here.
func _play_level_up(tint: Color) -> void:
	if _fill_tween != null and _fill_tween.is_valid():
		_fill_tween.kill()
	_fill_tween = create_tween()
	_fill_tween.tween_property(_arc, ^"value", _arc.max_value, WRAP_UP_TIME)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_fill_tween.tween_callback(_on_wrap_peak.bind(tint))
	_fill_tween.tween_property(_arc, ^"value", _target_ratio() * _arc.max_value, WRAP_IN_TIME)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## The instant the ring completes: empty it, flash the icon white and throw the
## burst. Everything lands on the same frame so it reads as one event.
func _on_wrap_peak(tint: Color) -> void:
	_arc.value = 0.0
	_place_spark()
	_burst.color = tint
	_burst.emitting = true
	# Overbright, not plain white: the icon is already light, and a blowout is
	# what sells the flash on a 32px sprite.
	_icon.modulate = Color(3.0, 3.0, 3.0)
	var flash: Tween = create_tween()
	flash.tween_property(_icon, ^"modulate", Color.WHITE, 0.45)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------------------
# Hover card
# ---------------------------------------------------------------------------

## Desktop path. Godot owns the returned node — it positions, shows and frees
## it — so this hands back a FRESH instance every time rather than reusing one.
func _make_custom_tooltip(_for_text: String) -> Object:
	var card: XpTrackerTooltip = _new_card()
	if card == null:
		return null
	# Godot reads the card's size before the tree has laid it out, so the fill
	# has to happen after _ready has run on the instance. Instantiating and
	# filling in one breath (rather than deferring) keeps the first frame right.
	_fill_card(card)
	return card


## Web path: one long-lived card, parented to the orb but top-level so it is
## positioned in screen space rather than inside the 48px orb rect.
func _build_web_card() -> void:
	_web_card = _new_card()
	if _web_card == null:
		return
	_web_card.visible = false
	_web_card.z_index = 80
	add_child(_web_card)
	_web_card.set_as_top_level(true)


func _new_card() -> XpTrackerTooltip:
	var scene: PackedScene = load(TOOLTIP_SCENE) as PackedScene
	if scene == null:
		return null
	return scene.instantiate() as XpTrackerTooltip


## Push the orb's current numbers into a card. The card is given the same pair
## the arc divides, so the two can never disagree.
func _fill_card(card: XpTrackerTooltip) -> void:
	card.fill(_job, _level, _xp_into_level, _xp_to_next, tint_for(_job))


func _show_web_card() -> void:
	if _web_card == null or _job == &"" or not visible:
		return
	_fill_card(_web_card)
	_web_card.visible = true
	_web_card.reset_size()
	# Below the orb, matching where the desktop tooltip lands.
	_web_card.global_position = global_position + Vector2(0.0, size.y + 4.0)


func _hide_web_card() -> void:
	if _web_card != null:
		_web_card.visible = false


## Touch has no hover, so on a phone a tap toggles the card instead. Deliberately
## does NOT consume the event: the orb is not a button, and swallowing the touch
## here would be one more place a tap goes nowhere.
func _on_web_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		if _web_card != null and _web_card.visible:
			_hide_web_card()
		else:
			_show_web_card()


# ---------------------------------------------------------------------------
# Show / hide
# ---------------------------------------------------------------------------

func _show() -> void:
	_hide_timer.start(AUTO_HIDE_SECONDS)
	if visible and modulate.a >= 1.0:
		return
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	visible = true
	set_process(true)
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, ^"modulate:a", 1.0, FADE_TIME)


func _on_hide_timeout() -> void:
	# Held open while the pointer is on it. Re-armed rather than cancelled, so
	# the orb still leaves on its own once the pointer moves off.
	if _hovered:
		_hide_timer.start(AUTO_HIDE_SECONDS)
		return
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, ^"modulate:a", 0.0, FADE_TIME)
	_fade_tween.tween_callback(_finish_hide)


func _finish_hide() -> void:
	visible = false
	set_process(false)
	_hide_web_card()
	# Numbers mid-flight would otherwise reappear at whatever opacity they had
	# when the orb left.
	_drops.clear()


func _on_mouse_entered() -> void:
	_hovered = true
	_show_web_card()


func _on_mouse_exited() -> void:
	_hovered = false
	_hide_web_card()
	# Give the player the full window back from the moment they look away,
	# rather than however little was left when they hovered.
	if visible:
		_hide_timer.start(AUTO_HIDE_SECONDS)


func _on_setting_changed(section: StringName, property: StringName, new_value: Variant) -> void:
	if section != SETTING_SECTION or property != SETTING_PROPERTY:
		return
	if not bool(new_value):
		_hide_timer.stop()
		if _fade_tween != null and _fade_tween.is_valid():
			_fade_tween.kill()
		modulate.a = 0.0
		_finish_hide()
