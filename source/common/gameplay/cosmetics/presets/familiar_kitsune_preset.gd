extends CompanionPreset
## KITSUNE. A little fox spirit floating along behind the wearer with three
## tails of blue fox-fire streaming out behind it. When they stop it settles
## beside them, eyes closed in a contented smile, tails fanning out wide, and
## two orbs of fox-fire circle round it.
##
## PROTOTYPE - not registered, no slot yet.
##
## Front view, so no mirroring. The tails are additive flame polygons (the same
## teardrop the Ember Imp uses, pointed along a direction): polygons rotate
## cleanly, unlike one-pixel rects, so the tails can swing freely.

const FOLLOW: Vector2 = Vector2(0, -34)
const FOLLOW_PX: float = 16.0
const IDLE_AFTER_S: float = 0.8

const FUR: Color = Color(1.0, 0.62, 0.26)
const FUR_DARK: Color = Color(0.80, 0.40, 0.14)
const MUZZLE: Color = Color(1.0, 0.96, 0.90)
const EAR_IN: Color = Color(0.36, 0.20, 0.16)
const FIRE: Color = Color(0.35, 0.65, 1.0)
const FIRE_CORE: Color = Color(0.85, 0.95, 1.0)
const MARK: Color = Color(0.92, 0.22, 0.30)


func _build() -> void:
	stiffness = 60.0
	damping = 10.0
	add_body_layer(_paint_tails, true, 0)
	add_body_layer(_paint_fox, false, 1)
	add_body_layer(_paint_orbs, true, 2)
	add_motes(FIRE, 8, VfxTextures.dot(4))


func target_local(_delta: float) -> Vector2:
	set_in_front(true)
	if still_for < IDLE_AFTER_S:
		return FOLLOW - _heading * FOLLOW_PX + Vector2(0, sin(_elapsed * 3.0) * 1.5)
	var side: float = -signf(_heading.x) if absf(_heading.x) > 0.1 else -1.0
	return Vector2(16.0 * side, -32.0 + sin(_elapsed * 1.5) * 1.5)


## A flame tongue from [param root] pointing along [param dir].
func _flame(root: Vector2, dir: Vector2, width: float, length: float) -> PackedVector2Array:
	var side: Vector2 = dir.orthogonal()
	var pts: PackedVector2Array = PackedVector2Array()
	# Round back half first: +side, round behind the root, to -side...
	for i: int in 7:
		var a: float = PI * float(i) / 6.0
		pts.append(root + (side * cos(a) - dir * sin(a)) * width)
	# ...then out to the tip on the -side and back in on the +side.
	pts.append(root - side * width * 0.6 + dir * length * 0.45)
	pts.append(root + dir * length)
	pts.append(root + side * width * 0.6 + dir * length * 0.45)
	return pts


func _paint_tails(layer: VfxDrawLayer) -> void:
	var idle: bool = still_for >= IDLE_AFTER_S
	var s: float = maxf(0.001, global_scale.x)
	# Moving, the tails stream away from the direction of travel; idle, they fan.
	var drift: float = clampf(-body_velocity().x / s * 0.01, -0.6, 0.6)
	# Tails spring from the base of the body and fan OUT to the sides. Rooted at
	# the chest and pointing up, they sat behind the head and read as a spiky
	# crown of flames rather than as tails.
	# Radians either side of straight up. Past ~0.9 they flatten out into a wedge
	# under the fox and read as wings.
	var fan: float = 0.8 if idle else 0.5
	for i: int in 3:
		var sway: float = sin(_elapsed * 3.0 + float(i) * 1.3) * 0.15
		var spread: float = (float(i) - 1.0) * fan
		if i == 1:
			spread = 0.0
		var dir: Vector2 = Vector2.from_angle(-PI * 0.5 + spread + drift + sway)
		var flick: float = 1.0 + 0.1 * sin(_elapsed * 11.0 + float(i))
		var root: Vector2 = Vector2(0.0, 2.0)
		var length: float = (15.0 if i == 1 else 13.0) * flick
		layer.draw_colored_polygon(_flame(root, dir, 3.0, length), Color(FIRE, 0.7))
		layer.draw_colored_polygon(_flame(root, dir, 1.4, length * 0.6), Color(FIRE_CORE, 0.8))


func _paint_fox(layer: VfxDrawLayer) -> void:
	var idle: bool = still_for >= IDLE_AFTER_S
	# Sitting body.
	layer.draw_circle(Vector2(0.0, 1.0), 3.6, FUR_DARK)
	layer.draw_circle(Vector2(0.0, 0.7), 3.2, FUR)
	layer.draw_circle(Vector2(0.0, 1.6), 1.8, MUZZLE)
	# Head and ears.
	var head: Vector2 = Vector2(0.0, -5.0)
	for side: float in [-1.0, 1.0]:
		layer.draw_colored_polygon(PackedVector2Array([
			head + Vector2(side * 1.5, -2.0), head + Vector2(side * 4.0, -2.0), head + Vector2(side * 3.5, -6.0),
		]), FUR_DARK)
		layer.draw_colored_polygon(PackedVector2Array([
			head + Vector2(side * 2.2, -2.5), head + Vector2(side * 3.4, -2.5), head + Vector2(side * 3.2, -4.8),
		]), EAR_IN)
	layer.draw_circle(head, 4.0, FUR_DARK)
	layer.draw_circle(head + Vector2(0, -0.3), 3.6, FUR)
	layer.draw_circle(head + Vector2(0, 1.5), 2.2, MUZZLE)
	layer.draw_rect(Rect2(head.x - 0.5, head.y + 1.0, 1.0, 1.0), FACE_DARK)   # nose
	# A red spirit mark on the brow.
	layer.draw_rect(Rect2(head.x - 0.5, head.y - 3.0, 1.0, 2.0), MARK)
	if idle:
		# Contented closed eyes: little upturned arcs.
		for side: float in [-1.0, 1.0]:
			var e: Vector2 = (head + Vector2(side * 2.0, -0.8)).round()
			layer.draw_rect(Rect2(e.x - 1.0, e.y, 1.0, 1.0), FACE_DARK)
			layer.draw_rect(Rect2(e.x, e.y - 1.0, 1.0, 1.0), FACE_DARK)
			layer.draw_rect(Rect2(e.x + 1.0, e.y, 1.0, 1.0), FACE_DARK)
	else:
		draw_eyes(layer, head + Vector2(0.0, -0.8), 1.8, Vector2(signf(_heading.x) * 0.5, 0.0), blinking(3.3, 0.8), 2)
	draw_blush(layer, head + Vector2(0.0, 0.8), 3.0)


func _paint_orbs(layer: VfxDrawLayer) -> void:
	if still_for < IDLE_AFTER_S:
		return
	var k: float = clampf((still_for - IDLE_AFTER_S) / 0.6, 0.0, 1.0)
	for i: int in 2:
		var a: float = _elapsed * 2.2 + float(i) * PI
		var at: Vector2 = Vector2(cos(a) * 10.0, -3.0 + sin(a) * 3.0)
		var flick: float = 0.8 + 0.2 * sin(_elapsed * 13.0 + float(i))
		layer.draw_circle(at, 3.0 * k, Color(FIRE, 0.25 * flick))
		layer.draw_circle(at, 1.6 * k, Color(FIRE, 0.6 * flick))
		layer.draw_circle(at, 0.8 * k, Color(FIRE_CORE, flick))
