extends CompanionPreset
## PIXIE. A tiny fairy in a leaf dress with a pink ponytail, darting along at the
## wearer's shoulder on glittering wings, trailing sparkle. When they stop she
## hovers beside them, twirls, and taps her wand - and a ring of little flowers
## blooms in the air around her and drifts away.
##
## DETAILED PASS. The fairy is painted on a [PixelCanvas]: skin, a pink ponytail
## with a highlight, a green leaf dress with a darker hem, tiny arms and legs, a
## shiny eye and a blush. Live on top, because they need to move every frame:
## gossamer wings (additive, beating), the wand and its star, glitter, and the
## flower ring.

const FOLLOW: Vector2 = Vector2(0, -38)
const FOLLOW_PX: float = 15.0
const IDLE_AFTER_S: float = 0.8
const SPELL_EVERY_S: float = 3.6
const SPELL_S: float = 1.4

const SKIN: Color = Color(1.0, 0.87, 0.76)
const HAIR: Color = Color(1.0, 0.52, 0.76)
const DRESS: Color = Color(0.44, 0.80, 0.46)
const DRESS_DARK: Color = Color(0.26, 0.58, 0.32)
const WING: Color = Color(0.70, 0.92, 1.0)
const WAND: Color = Color(0.94, 0.86, 0.62)
const STAR: Color = Color(1.0, 0.95, 0.55)
const PETAL: Array[Color] = [Color(1.0, 0.60, 0.80), Color(1.0, 0.92, 0.50), Color(0.72, 0.64, 1.0)]

const W: int = 14
const H: int = 20

var _facing: float = 1.0


func _build() -> void:
	stiffness = 85.0
	damping = 11.0
	add_body_layer(_paint_wings, true, 0)
	add_body_layer(_paint_fairy, false, 1)
	add_body_layer(_paint_magic, true, 2)
	add_motes(Color(1.0, 0.85, 1.0), 14)


func target_local(_delta: float) -> Vector2:
	set_in_front(true)
	if absf(_heading.x) > 0.2:
		_facing = signf(_heading.x)
	if still_for < IDLE_AFTER_S:
		var dart: Vector2 = Vector2(sin(_elapsed * 3.7), cos(_elapsed * 5.3)) * 2.0
		return FOLLOW - _heading * FOLLOW_PX + dart
	return Vector2(-17.0 * _facing, -38.0 + sin(_elapsed * 2.4) * 2.0)


func _spell_t() -> float:
	if still_for < IDLE_AFTER_S + 0.8:
		return -1.0
	var t: float = fposmod(still_for - IDLE_AFTER_S - 0.8, SPELL_EVERY_S)
	return t / SPELL_S if t < SPELL_S else -1.0


static func _frame() -> ImageTexture:
	return PixelCanvas.cached("pixie", W, H, func(c: PixelCanvas) -> void:
		# Ponytail behind the head.
		c.ball(3.5, 6.0, 2.0, 2.6, HAIR)
		# Legs.
		c.rect(6.0, 15.0, 1.0, 4.0, SKIN)
		c.rect(8.0, 15.0, 1.0, 5.0, SKIN)
		# Leaf dress: a bell, flaring to a pointed hem.
		c.tri(Vector2(7.5, 8.0), Vector2(3.0, 16.0), Vector2(12.0, 16.0), DRESS)
		c.tri(Vector2(3.0, 16.0), Vector2(5.0, 16.0), Vector2(4.0, 17.5), DRESS)
		c.tri(Vector2(10.0, 16.0), Vector2(12.0, 16.0), Vector2(11.0, 17.5), DRESS)
		# Arms.
		c.rect(4.0, 9.0, 1.0, 4.0, SKIN)
		c.rect(10.0, 9.0, 1.0, 3.0, SKIN)
		# Head and hair.
		c.ball(7.5, 5.0, 3.2, 3.2, SKIN)
		c.ball(7.0, 3.2, 3.5, 2.3, HAIR)
		c.finish(0.15, 0.2, 0.55)
		# Details: leaf veins on the dress, hair highlight, face.
		c.line(Vector2(7.5, 10.0), Vector2(7.5, 15.0), DRESS_DARK)
		c.px(6.0, 13.0, DRESS_DARK)
		c.px(9.0, 13.0, DRESS_DARK)
		c.rect(5.0, 2.0, 2.0, 1.0, HAIR.lightened(0.35))
		c.eye(8.0, 5.0, 2, 2)
		c.px(6.5, 7.0, Color(1.0, 0.55, 0.68))
		c.px(9.0, 7.0, Color(0.7, 0.35, 0.40))     # smile
	)


func _paint_wings(layer: VfxDrawLayer) -> void:
	# Two pairs, beating fast: width flickers as they sweep.
	var beat: float = absf(sin(_elapsed * 28.0))
	for pair: int in 2:
		var up: bool = pair == 0
		var c: Vector2 = Vector2(-2.0 * _facing, -13.0 if up else -9.0)
		var rx: float = (5.5 if up else 4.0) * (0.35 + 0.65 * beat)
		var ry: float = 3.2 if up else 2.4
		for side: float in [-1.0, 1.0]:
			layer.draw_set_transform(c + Vector2(side * rx * 0.7, 0.0), 0.0, Vector2(1.0, ry / maxf(rx, 0.1)))
			layer.draw_circle(Vector2.ZERO, rx, Color(WING, 0.30))
			layer.draw_circle(Vector2.ZERO, rx * 0.55, Color(WING, 0.35))
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _paint_fairy(layer: VfxDrawLayer) -> void:
	# The twirl: during a spell she spins, which in 2D is facing flipping fast.
	var f: float = _facing
	var s: float = _spell_t()
	if s >= 0.0 and s < 0.35:
		f = 1.0 if int(s * 20.0) % 2 == 0 else -1.0
	PixelCanvas.draw_sprite(layer, _frame(), Vector2.ZERO, f)
	# Wand held out in the front hand.
	var hand: Vector2 = Vector2(3.0 * f, -10.0)
	var tip: Vector2 = hand + Vector2(4.0 * f, -4.0)
	layer.draw_line(hand, tip, WAND, 1.0)


func _paint_magic(layer: VfxDrawLayer) -> void:
	var f: float = _facing
	var tip: Vector2 = Vector2(7.0 * f, -14.0)
	var tw: float = 0.6 + 0.4 * sin(_elapsed * 9.0)
	layer.draw_circle(tip, 2.5, Color(STAR, 0.25 * tw))
	layer.draw_rect(Rect2(tip.round() - Vector2(1, 0), Vector2(3, 1)), Color(STAR, tw))
	layer.draw_rect(Rect2(tip.round() - Vector2(0, 1), Vector2(1, 3)), Color(STAR, tw))
	# The spell: a ring of tiny flowers blooming out from her and fading.
	var s: float = _spell_t()
	if s < 0.3:
		return
	var k: float = (s - 0.3) / 0.7
	for i: int in 8:
		var a: float = float(i) * TAU / 8.0 + k * 0.8
		var at: Vector2 = Vector2(0, -10) + Vector2(cos(a), sin(a) * 0.7) * (5.0 + k * 12.0)
		var col: Color = Color(PETAL[i % PETAL.size()], 1.0 - k)
		var p: Vector2 = at.round()
		layer.draw_rect(Rect2(p + Vector2(-1, 0), Vector2(1, 1)), col)
		layer.draw_rect(Rect2(p + Vector2(1, 0), Vector2(1, 1)), col)
		layer.draw_rect(Rect2(p + Vector2(0, -1), Vector2(1, 1)), col)
		layer.draw_rect(Rect2(p + Vector2(0, 1), Vector2(1, 1)), col)
		layer.draw_rect(Rect2(p, Vector2(1, 1)), Color(1.0, 1.0, 0.8, 1.0 - k))
