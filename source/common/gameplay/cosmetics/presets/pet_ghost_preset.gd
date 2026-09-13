extends CompanionPreset
## GHOST. A round little ghost with a curling wisp of a tail, rosy cheeks and
## shiny eyes, glowing softly and shedding sparkles. It floats along behind the
## wearer, and when they stop it hides behind them and plays peek-a-boo - popping
## out one side with a wave and a "boo", then ducking back to try the other.
##
## PET slot - sold in the Vault's Pets tab, priced in PremiumCatalog.COSMETIC_COSTS.
##
## v2 (TLC pass): the first ghost was a flat sheet with two dots and read as a
## placeholder next to the Wisp. The fixes are the ones that make the Wisp work:
## a soft additive glow, sparkles, a lit/shaded body instead of one flat colour,
## eyes with a shine, and something always moving (tail curl, arms, bob).
##
## PEEK-A-BOO STAYS BEHIND THE WEARER THE WHOLE TIME. The first two versions
## swapped the ghost in FRONT once it was most of the way out, which put it
## squarely over the player's face - it read as covering them, not peeking.
## Now the body always occludes it while idle: tucked in, it vanishes behind the
## torso; peeking, the head still hides its inner half, so what shows is half a
## ghost leaning out from behind someone. That half-hidden edge IS the peek.

const FOLLOW: Vector2 = Vector2(0, -32)
const FOLLOW_PX: float = 16.0
const HIDE_AT: Vector2 = Vector2(0, -18)
## Far enough that the eyes clear the edge of the head (about 8 px either side
## of centre on the starter body), close enough that the inner half stays hidden.
const PEEK_X: float = 13.0
const PEEK_PERIOD_S: float = 3.6
const IDLE_AFTER_S: float = 0.8

const LIT: Color = Color(0.97, 0.98, 1.0, 0.95)
const SHADE: Color = Color(0.76, 0.80, 0.97, 0.92)
const EDGE: Color = Color(0.52, 0.56, 0.84)
const GLOW: Color = Color(0.70, 0.80, 1.0)
const HEAD_R: float = 6.0

var _peek: float = 0.0
var _peek_side: float = 1.0
var _surprised: bool = false


func _build() -> void:
	stiffness = 60.0
	damping = 11.0
	add_body_layer(_paint_glow, true, 0)
	add_body_layer(_paint_ghost, false, 1)
	add_motes(Color(0.80, 0.85, 1.0), 8, null, Vector2(0, -2))


func target_local(_delta: float) -> Vector2:
	var bob: float = sin(_elapsed * 2.2) * 1.5
	if still_for < IDLE_AFTER_S:
		_peek = 0.0
		_surprised = false
		set_in_front(true)
		return FOLLOW - _heading * FOLLOW_PX + Vector2(0, bob)
	var t: float = still_for - IDLE_AFTER_S
	var cycle: float = fposmod(t / PEEK_PERIOD_S, 1.0)
	_peek_side = 1.0 if int(t / PEEK_PERIOD_S) % 2 == 0 else -1.0
	if cycle < 0.35:
		_peek = 0.0
	elif cycle < 0.5:
		_peek = smoothstep(0.35, 0.5, cycle)
	elif cycle < 0.82:
		_peek = 1.0
	else:
		_peek = 1.0 - smoothstep(0.82, 1.0, cycle)
	_surprised = _peek > 0.9
	set_in_front(false)
	return HIDE_AT + Vector2(_peek_side * PEEK_X * _peek, -2.0 * _peek + bob)


func _paint_glow(layer: VfxDrawLayer) -> void:
	var pulse: float = 0.85 + 0.15 * sin(_elapsed * 3.0)
	layer.draw_circle(Vector2(0, -2), 13.0, Color(GLOW, 0.07 * pulse))
	layer.draw_circle(Vector2(0, -2), 9.0, Color(GLOW, 0.14 * pulse))


## The body outline: a round head flowing into a tapering tail that curls toward
## [param tip]. Built so no two neighbouring points coincide (polygon
## triangulation fails on near-duplicates).
func _outline(r: float, tip: Vector2) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 13:
		var a: float = PI * 0.8 + (PI * 1.4) * float(i) / 12.0   # over the top, side to side
		pts.append(Vector2(cos(a) * r, -4.0 + sin(a) * r))
	# Down the right side, out to the tip, back in under the body. Kept to four
	# points with the tip always right of centre and below y 3: the first
	# version interpolated extra points toward the tip, and a short tail folded
	# them across each other and failed to triangulate.
	pts.append(Vector2(r * 0.72, 3.0))
	pts.append(tip)
	pts.append(Vector2(1.0, 5.5))
	pts.append(Vector2(-r * 0.82, 2.0))
	return pts


func _paint_ghost(layer: VfxDrawLayer) -> void:
	# Lean into the direction of travel, and round the corner when peeking.
	var lean: float = clampf(body_velocity().x / maxf(0.001, global_scale.x) * 0.003, -0.12, 0.12)
	layer.draw_set_transform(Vector2.ZERO, _peek_side * 0.12 * _peek - lean, Vector2.ONE)

	# The tail CURLS off to one side and swishes - a tip straight down the
	# middle read as a map pin, not a ghost. It also trails opposite the motion.
	var trail: float = clampf(-body_velocity().x / maxf(0.001, global_scale.x) * 0.05, -3.0, 3.0)
	var curl: float = 5.0 + sin(_elapsed * 3.3) * 2.0
	var tip: Vector2 = Vector2(maxf(2.5, curl + trail), 6.5 - sin(_elapsed * 3.3) * 1.2)

	var outline: PackedVector2Array = _outline(HEAD_R, tip)
	layer.draw_colored_polygon(outline, SHADE)
	# The lit body: the same shape, smaller and nudged up-left, so a crescent of
	# shade is left along the lower right - the cheapest believable shading.
	var lit: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in outline:
		lit.append((p - Vector2(-1.0, -4.0)) * 0.84 + Vector2(-1.3, -4.4))
	layer.draw_colored_polygon(lit, LIT)
	# A round wisp at the tail's end, so it finishes in a soft curl, not a point.
	layer.draw_circle(tip + Vector2(0.5, 0.0), 1.8, EDGE)
	layer.draw_circle(tip + Vector2(0.3, -0.3), 1.2, LIT)
	var closed: PackedVector2Array = outline.duplicate()
	closed.append(outline[0])
	layer.draw_polyline(closed, EDGE, 1.0)

	# Arms: little nubs; the peeking side waves.
	var wave: float = sin(_elapsed * 12.0) * 1.5 if _peek > 0.8 else sin(_elapsed * 2.2) * 0.5
	for side: float in [-1.0, 1.0]:
		var up: float = wave - 2.5 if side == _peek_side and _peek > 0.8 else wave * 0.3
		layer.draw_circle(Vector2(side * (HEAD_R + 0.5), -1.0 + up), 1.5, SHADE)
		layer.draw_circle(Vector2(side * (HEAD_R + 0.2), -1.4 + up), 1.0, LIT)

	# The face is drawn UNROTATED. Rotating one-pixel rects smears them into
	# slanted blobs, and the eyes looked angry; the head can lean without them.
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var look: Vector2 = Vector2(_peek_side * _peek, 0.0) if _peek > 0.0 else Vector2(signf(_heading.x) * 0.8, 0.0)
	draw_eyes(layer, Vector2(0.0, -5.0), 2.5, look, blinking(3.0), 3)
	draw_blush(layer, Vector2(look.x, -2.0), 4.0)
	# Mouth: a tiny smile travelling, an "o" when it pops out to say boo.
	var m: Vector2 = Vector2(look.x, -1.0).round()
	if _surprised:
		layer.draw_rect(Rect2(m.x - 1.0, m.y, 2.0, 2.0), FACE_DARK)
	else:
		layer.draw_rect(Rect2(m.x - 1.0, m.y + 1.0, 1.0, 1.0), FACE_DARK)
		layer.draw_rect(Rect2(m.x, m.y + 1.0, 1.0, 1.0), FACE_DARK)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
