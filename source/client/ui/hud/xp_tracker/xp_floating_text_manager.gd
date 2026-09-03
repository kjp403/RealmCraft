class_name XpFloatingTextManager
extends Control
## Floating "+N xp" numbers beside the radial XP tracker, with a per-skill
## accumulator so rapid skilling ticks read as one growing number instead of a
## wall of overlapping labels.
##
## Skilling ticks are FAST — fletching runs several arrows a second, and a
## multi-job node credits two skills off one swing. Spawning a label per tick
## stacks four or five semi-transparent numbers on top of each other and none of
## them are readable. So while a skill's drop is still on screen, a new tick is
## swallowed into it: the total grows, the text is rewritten, and the fade and
## the scale pop both restart. One label per skill, however hard the player
## clicks.
##
## Accumulation is keyed on the JOB SLUG, not global. A herb node paying both
## Herblore and Medicine has to show two numbers — merging them would print one
## skill's XP under the other's name. Concurrent drops stack upward in rows and
## are tinted by their skill (see [method push]), which is what tells them apart:
## the text itself stays "+N xp" so it never gets long enough to overlap.
##
## STRICTLY VISUAL, and deliberately transparent to the mouse: this floats over
## the play area, where LMB is click-to-move. Every node here is
## MOUSE_FILTER_IGNORE — a label that ate a movement click would feel like the
## game dropped input.

## How far one drop rises across its life, in whole pixels.
const DRIFT_PX: int = 26
## Lifetime of a drop that is never fed again. Long enough to read a 4-digit
## number, short enough that the next tick usually lands inside it.
const LIFETIME: float = 1.05
## Fraction of the lifetime the drop stays fully opaque before the fade starts.
## Fading from the first frame makes a number that is still being added to look
## like it is already leaving.
const FADE_HOLD: float = 0.55
## Scale a drop pops to on every tick that feeds it. Small: this fires on EVERY
## skilling tick, and anything punchier turns a normal gathering session into a
## throbbing screen.
const POP_SCALE: float = 1.18
## How long the pop takes to settle back to 1.0.
const POP_TIME: float = 0.17
## Longest one label may keep absorbing ticks. Without this, sustained skilling
## feeds the same drop forever and the number climbs into a session total that
## means nothing — the player wants to read "this burst", not "this hour".
const BURST_MAX_MS: int = 4000
## Vertical gap between concurrent drops for different skills.
const ROW_GAP: int = 15
## Pixel font size. Integer, per [method PixelUI.label] — a fractional size
## reintroduces the subpixel placement this whole widget exists to avoid.
const FONT_SIZE: int = 14


## One live number. Plain inner class rather than a Dictionary so the fields are
## typed and a typo is a parse error instead of a silently missing key.
class Drop extends RefCounted:
	var label: Label
	## Running XP total the label is currently displaying.
	var total: int = 0
	## When this drop first appeared — the clock [constant BURST_MAX_MS] runs on.
	var born_ms: int = 0
	## Y the drop drifts up FROM, so concurrent skills don't share a line.
	var base_y: float = 0.0
	var tween: Tween


## job slug -> live Drop. Entries are removed as their labels free themselves.
var _drops: Dictionary = {}


func _ready() -> void:
	# Zero-sized anchor point: drops are positioned relative to this node's
	# origin and centred on it, so the HUD only has to place a single point.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2.ZERO
	PixelUI.make_pixel_perfect(self)


## Show [param amount] XP gained in [param job].
##
## Feeds the skill's existing drop when it has one, otherwise starts a new one.
## [param tint] should be the same colour the tracker's arc is using for this
## skill, so a player watching two skills tick at once can match each number to
## its gauge without reading a word.
func push(job: StringName, amount: int, tint: Color = PixelUI.INK_XP) -> void:
	if amount <= 0 or job == &"":
		return
	var now_ms: int = Time.get_ticks_msec()
	var existing: Drop = _live_drop(job)
	if existing != null and now_ms - existing.born_ms < BURST_MAX_MS:
		existing.total += amount
		_apply_text(existing, tint)
		_animate(existing)
		return
	# Either nothing on screen for this skill, or the burst ran its full window.
	# Retire the stale one rather than letting it finish alongside its
	# replacement — two labels for one skill on one line is the exact overlap
	# this class exists to prevent.
	if existing != null:
		_retire(job, existing)
	_spawn(job, amount, tint, now_ms)


## Clear every live number immediately. Called when the tracker hides or the
## player changes map — a drop left mid-tween would pop back into view at
## whatever opacity it had when the HUD went away.
func clear() -> void:
	for key: Variant in _drops.keys():
		var drop: Drop = _drops[key] as Drop
		if drop != null and is_instance_valid(drop.label):
			drop.label.queue_free()
	_drops.clear()


func _spawn(job: StringName, amount: int, tint: Color, now_ms: int) -> void:
	var drop := Drop.new()
	drop.total = amount
	drop.born_ms = now_ms
	# Stack above whatever is already on screen. Rows are assigned at spawn and
	# never reflowed: shuffling live numbers downward as an older one expires
	# reads as a glitch, and the drops are gone in about a second anyway.
	drop.base_y = -float(_live_count() * ROW_GAP)

	var label: Label = PixelUI.text("", FONT_SIZE, tint)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drop.label = label
	add_child(label)

	_drops[job] = drop
	_apply_text(drop, tint)
	_animate(drop)


## Rewrite the label and re-centre it on this node's origin.
##
## Re-measuring on every tick matters: "+90 xp" and "+1,250 xp" are different
## widths, and a label that keeps its old width drifts off-centre as the number
## grows. Positions are rounded to whole pixels — a label on a half pixel is
## exactly the blur the pixel font is chosen to avoid.
func _apply_text(drop: Drop, tint: Color) -> void:
	if not is_instance_valid(drop.label):
		return
	drop.label.text = "+%s xp" % SkillXp.format_xp(drop.total)
	drop.label.add_theme_color_override(&"font_color", tint)
	var wanted: Vector2 = drop.label.get_combined_minimum_size()
	drop.label.size = wanted
	# Pivot at the centre so the pop scales about the number, not its top-left.
	drop.label.pivot_offset = wanted * 0.5
	drop.label.position = Vector2(roundf(-wanted.x * 0.5), roundf(drop.base_y))


## (Re)start the drop's animation from the top: pop the scale, restart the rise,
## restart the fade. Killing the previous tween is what makes a fed drop look
## refreshed rather than fading on its original schedule.
func _animate(drop: Drop) -> void:
	if not is_instance_valid(drop.label):
		return
	if drop.tween != null and drop.tween.is_valid():
		drop.tween.kill()

	var label: Label = drop.label
	label.modulate.a = 1.0
	label.scale = Vector2.ONE * POP_SCALE

	# Bound to the LABEL, not to self: when the label frees itself the tween dies
	# with it, so a drop that outlives its parent can never tick on a freed node.
	var tween: Tween = label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, ^"scale", Vector2.ONE, POP_TIME)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Drift runs through a method rather than a property so every frame lands on
	# a whole pixel. Tweening position:y directly puts the text on fractional
	# coordinates for most of its life, which shimmers under the project's
	# stretched base resolution.
	tween.tween_method(
		_apply_drift.bind(drop), 0.0, float(DRIFT_PX), LIFETIME
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, ^"modulate:a", 0.0, LIFETIME * (1.0 - FADE_HOLD))\
		.set_delay(LIFETIME * FADE_HOLD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)
	drop.tween = tween


func _apply_drift(risen: float, drop: Drop) -> void:
	if not is_instance_valid(drop.label):
		return
	drop.label.position.y = roundf(drop.base_y - risen)


## The skill's drop if it is still on screen, else null. Also reaps the map
## entry for a label that has already freed itself, so [method _live_count]
## doesn't keep counting numbers that are gone.
func _live_drop(job: StringName) -> Drop:
	var drop: Drop = _drops.get(job, null) as Drop
	if drop == null:
		return null
	if not is_instance_valid(drop.label):
		_drops.erase(job)
		return null
	return drop


func _live_count() -> int:
	var count: int = 0
	for key: Variant in _drops.keys():
		var drop: Drop = _drops[key] as Drop
		if drop != null and is_instance_valid(drop.label):
			count += 1
		else:
			_drops.erase(key)
	return count


func _retire(job: StringName, drop: Drop) -> void:
	if drop.tween != null and drop.tween.is_valid():
		drop.tween.kill()
	if is_instance_valid(drop.label):
		drop.label.queue_free()
	_drops.erase(job)
