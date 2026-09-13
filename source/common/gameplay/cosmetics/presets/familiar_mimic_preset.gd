extends GroundCompanionPreset
## MIMIC. A little treasure chest on stubby feet that toddles after the wearer.
## When they stop, the lid lifts a crack, warm gold light spills out, and a pair
## of glowing eyes peers out from inside - blinking, looking around - while the
## odd coin hops out and drops back in.
##
## ON THE MOVE IT LEAKS GOLD: every landing jolts the lid up and a coin flies
## out behind it, bounces once on the floor and lies there glinting before it
## fades. The coins are world-space, so they stay where they fell while the chest
## toddles on - a trail of dropped loot.
##
## PROTOTYPE - not registered, no slot yet.
##
## v2 (TLC pass): the first mimic was a flat box with rows of teeth and a tongue,
## and it read as gross rather than cute. This one is a proper chest - planks,
## iron bands with rivets, a domed lid and a gold lock - and the reveal is LIGHT
## and EYES, not a mouth. One tiny fang each side keeps the "mimic" joke.

const WOOD: Color = Color(0.66, 0.40, 0.21)
const WOOD_LIGHT: Color = Color(0.80, 0.53, 0.29)
const WOOD_DARK: Color = Color(0.40, 0.22, 0.11)
const IRON: Color = Color(0.46, 0.48, 0.56)
const IRON_LIGHT: Color = Color(0.74, 0.76, 0.84)
const GOLD: Color = Color(1.0, 0.80, 0.30)
const GOLD_DARK: Color = Color(0.72, 0.50, 0.12)
const INSIDE: Color = Color(0.14, 0.07, 0.10)
const EYE_GLOW: Color = Color(1.0, 0.93, 0.50)
const LIGHT: Color = Color(1.0, 0.82, 0.40)
const FANG: Color = Color(0.98, 0.96, 0.90)

const W: float = 14.0
const BOX_H: float = 7.0
const LID_H: float = 5.0
const OPEN_AFTER_S: float = 1.0
const OPEN_S: float = 0.5
## How far the lid lifts when open, px.
const LIFT_PX: float = 6.0
const COIN_EVERY_S: float = 1.8
const COIN_S: float = 0.7

var _open: float = 0.0
## Seconds left on the jolt the lid gets from a landing.
var _jolt: float = 0.0
var _last_phase: float = 0.0
var _landings: int = 0
## World-space coins: {"p" floor point, "h" height, "vh", "vx", "t" age}.
var _coins: Array[Dictionary] = []

const COIN_GRAVITY: float = 260.0
const COIN_LIFE_S: float = 1.6
const MAX_COINS: int = 12


func _build() -> void:
	hop_peak = 4.0
	add_body_layer(_paint_chest, false, 0)
	add_body_layer(_paint_light, true, 1)
	add_body_layer(_paint_lid, false, 2)
	# Dropped coins live in world space on the floor, not on the chest.
	var floor_layer: VfxDrawLayer = _add_draw_layer(_paint_coins, false, -2)
	floor_layer.top_level = true
	# top_level draws ON TOP of everything at its own z, so a layer meant to be
	# under the wearer needs a z strictly below theirs (see
	# CompanionPreset.set_in_front).


func _tick(delta: float) -> void:
	super(delta)
	_open = move_toward(_open, 1.0 if (still_for >= OPEN_AFTER_S) else 0.0, delta / OPEN_S)
	# A landing is the hop phase wrapping back round to 0.
	if is_hopping() and hop_phase < _last_phase:
		_on_landing()
	_last_phase = hop_phase
	_jolt = maxf(0.0, _jolt - delta)
	_step_coins(delta)


func _on_landing() -> void:
	_jolt = 0.16
	_landings += 1
	# Most landings, not all - a coin every single hop reads as a fountain.
	if _landings % 3 == 2 or _coins.size() >= MAX_COINS or not _viewer_in_range():
		return
	var s: float = global_scale.x
	var back: float = -facing
	_coins.append({
		"p": body.global_position + Vector2(back * 2.0, 1.0) * s,
		"h": (BOX_H + 2.0) * s,
		"vh": (70.0 + 25.0 * float(_landings % 2)) * s,
		"vx": back * (22.0 + 10.0 * float(_landings % 3)) * s,
		"t": 0.0,
	})


func _step_coins(delta: float) -> void:
	var s: float = global_scale.x
	var i: int = 0
	while i < _coins.size():
		var c: Dictionary = _coins[i]
		c["t"] += delta
		if c["t"] >= COIN_LIFE_S:
			_coins.remove_at(i)
			continue
		if c["h"] > 0.0 or c["vh"] > 0.0:
			c["vh"] -= COIN_GRAVITY * s * delta
			c["h"] += c["vh"] * delta
			c["p"] += Vector2(c["vx"] * delta, 0.0)
			if c["h"] <= 0.0:
				c["h"] = 0.0
				# One small bounce, then it lies still.
				c["vh"] = -c["vh"] * 0.35 if absf(c["vh"]) > 30.0 * s else 0.0
				c["vx"] *= 0.4
		i += 1


func _paint_coins(layer: VfxDrawLayer) -> void:
	var s: float = global_scale.x
	for c: Dictionary in _coins:
		var fade: float = clampf((COIN_LIFE_S - float(c["t"])) / 0.4, 0.0, 1.0)
		var at: Vector2 = (c["p"] as Vector2) - Vector2(0.0, c["h"])
		var gold: Color = Color(GOLD, fade)
		if c["h"] > 0.0:
			# Spinning in the air: its width flickers between edge-on and face-on.
			var w: float = (1.0 + roundf(absf(cos(float(c["t"]) * 18.0)) * 2.0)) * s
			layer.draw_rect(Rect2(at.x - w * 0.5, at.y - 1.5 * s, w, 3.0 * s), gold)
		else:
			# Lying flat, with a glint that comes and goes.
			layer.draw_rect(Rect2(at.x - 1.5 * s, at.y - 1.0 * s, 3.0 * s, 2.0 * s), gold)
			layer.draw_rect(Rect2(at.x - 1.5 * s, at.y, 3.0 * s, 1.0 * s), Color(GOLD_DARK, fade))
			if fposmod(float(c["t"]) * 2.0 + at.x, 1.0) < 0.2:
				layer.draw_rect(Rect2(at.x - 0.5 * s, at.y - 1.0 * s, 1.0 * s, 1.0 * s), Color(1, 1, 1, fade))


func _lift() -> float:
	return maxf(ease(_open, 0.5) * LIFT_PX, 2.0 if _jolt > 0.0 else 0.0)


func _paint_chest(layer: VfxDrawLayer) -> void:
	apply_hop(layer, W * 0.55)
	var half: float = W * 0.5
	# Stubby feet, stepping in turn while it hops.
	var step: float = sin(hop_phase * TAU) if is_hopping() else 0.0
	layer.draw_rect(Rect2(-half + 2.0, -1.0 - maxf(0.0, step), 3.0, 2.0), WOOD_DARK)
	layer.draw_rect(Rect2(half - 5.0, -1.0 - maxf(0.0, -step), 3.0, 2.0), WOOD_DARK)

	# The dark mouth, only visible in the gap under a lifted lid.
	var lift: float = _lift()
	if lift > 0.3:
		layer.draw_rect(Rect2(-half + 1.0, -BOX_H - 1.0 - lift, W - 2.0, lift + 1.0), INSIDE)
		# Glowing eyes peering out, looking side to side, blinking.
		var look: float = roundf(sin(_elapsed * 0.9) * 1.5)
		if _open > 0.6 and not blinking(2.8, 0.7):
			for side: float in [-1.0, 1.0]:
				layer.draw_rect(Rect2(side * 2.5 - 1.0 + look, roundf(-BOX_H - lift * 0.65), 2.0, 2.0), EYE_GLOW)
		# One little fang each side of the lip.
		if _open > 0.6:
			layer.draw_rect(Rect2(-half + 2.0, -BOX_H - 1.0, 1.0, 1.0), FANG)
			layer.draw_rect(Rect2(half - 3.0, -BOX_H - 1.0, 1.0, 1.0), FANG)

	# Box body: planks with a light top edge and shaded right side.
	layer.draw_rect(Rect2(-half, -BOX_H, W, BOX_H), WOOD)
	layer.draw_rect(Rect2(-half, -BOX_H, W, 1.0), WOOD_LIGHT)
	layer.draw_rect(Rect2(-half + 1.0, -BOX_H + 3.0, W - 2.0, 1.0), WOOD_DARK)
	layer.draw_rect(Rect2(half - 2.0, -BOX_H, 2.0, BOX_H), WOOD_DARK)
	layer.draw_rect(Rect2(-half, -1.0, W, 1.0), WOOD_DARK)
	# Iron bands with a rivet each.
	for x: float in [-half + 2.0, half - 4.0]:
		layer.draw_rect(Rect2(x, -BOX_H, 2.0, BOX_H), IRON)
		layer.draw_rect(Rect2(x, -BOX_H + 2.0, 1.0, 1.0), IRON_LIGHT)
	# Gold lock on the BOX front, not the lid: on the lid it rose with it and sat
	# right over the eyes peering out of the gap.
	layer.draw_rect(Rect2(-1.5, -BOX_H + 1.0, 3.0, 3.0), GOLD)
	layer.draw_rect(Rect2(-1.5, -BOX_H + 3.0, 3.0, 1.0), GOLD_DARK)
	layer.draw_rect(Rect2(-0.5, -BOX_H + 2.0, 1.0, 1.0), WOOD_DARK)


## Gold light spilling up out of the open lid - additive, so it lights the lid's
## underside and anything behind it rather than painting over it.
func _paint_light(layer: VfxDrawLayer) -> void:
	apply_hop(layer, 0.0)
	var k: float = ease(_open, 0.5)
	if k <= 0.02:
		return
	var flicker: float = 0.9 + 0.1 * sin(_elapsed * 7.0)
	var top: float = -BOX_H - _lift()
	var fan: PackedVector2Array = PackedVector2Array([
		Vector2(-5.0, top), Vector2(5.0, top), Vector2(10.0, top - 12.0 * k), Vector2(-10.0, top - 12.0 * k),
	])
	var bright: Color = Color(LIGHT, 0.30 * k * flicker)
	var clear: Color = Color(LIGHT, 0.0)
	layer.draw_polygon(fan, PackedColorArray([bright, bright, clear, clear]))
	layer.draw_circle(Vector2(0, top), 5.0, Color(LIGHT, 0.18 * k * flicker))
	# A coin hopping out and dropping back in.
	var t: float = fposmod(still_for, COIN_EVERY_S)
	if _open > 0.9 and t < COIN_S:
		var u: float = t / COIN_S
		var n: float = floor(still_for / COIN_EVERY_S)
		var at: Vector2 = Vector2(sin(n * 3.7) * 3.0, top - sin(u * PI) * 9.0).round()
		var spin: float = absf(cos(u * TAU * 1.5))
		layer.draw_rect(Rect2(at.x - roundf(spin), at.y - 1.0, maxf(1.0, roundf(spin * 2.0)), 2.0), GOLD)


func _paint_lid(layer: VfxDrawLayer) -> void:
	apply_hop(layer, 0.0)
	var half: float = W * 0.5
	var y: float = -BOX_H - LID_H - _lift()
	# Domed lid: a full-width band with a slightly narrower band on top.
	layer.draw_rect(Rect2(-half, y + 2.0, W, LID_H - 2.0), WOOD)
	layer.draw_rect(Rect2(-half + 1.0, y, W - 2.0, 2.0), WOOD)
	layer.draw_rect(Rect2(-half + 1.0, y, W - 2.0, 1.0), WOOD_LIGHT)
	layer.draw_rect(Rect2(half - 2.0, y + 1.0, 1.0, LID_H - 1.0), WOOD_DARK)
	layer.draw_rect(Rect2(-half, y + LID_H - 1.0, W, 1.0), WOOD_DARK)
	for x: float in [-half + 2.0, half - 4.0]:
		layer.draw_rect(Rect2(x, y, 2.0, LID_H), IRON)
		layer.draw_rect(Rect2(x, y + 1.0, 1.0, 1.0), IRON_LIGHT)
