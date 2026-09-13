extends GroundCompanionPreset
## SPIRIT FAWN. A pale, faintly glowing fawn with luminous blue spots and tiny
## crystal antler buds. It prances after the wearer, leaving little motes of
## light where its hooves touch. When they stop it lowers its head to graze, and
## small glowing flowers open in the grass around its feet.
##
## DETAILED PASS. Painted on a [PixelCanvas] (prance gathered, prance stretched,
## stand, graze): mint-white coat in three tones, a pale belly, slender legs
## with dark hooves, big ears with pink insides, a white tail tuft and a shiny
## eye. Live on top: the spots and antlers glowing and pulsing (additive), the
## hoof motes, and the flowers.

## A faint blue cast, not pure white: pure white with thick legs read as a goat.
const COAT: Color = Color(0.84, 0.92, 1.0)
const COAT_SHADE: Color = Color(0.62, 0.74, 0.90)
const DAPPLE: Color = Color(0.55, 0.78, 0.98)
const HOOF: Color = Color(0.36, 0.40, 0.46)
const EAR_IN: Color = Color(1.0, 0.76, 0.82)
const GLOW: Color = Color(0.45, 0.90, 1.0)
const FLOWER: Array[Color] = [Color(0.60, 0.95, 1.0), Color(0.90, 0.80, 1.0), Color(1.0, 1.0, 0.75)]
const GRAZE_AFTER_S: float = 0.8

const W: int = 26
const H: int = 24

## Spot positions inside the coat, in canvas pixels, for the standing poses.
const SPOTS: Array[Vector2] = [Vector2(9, 11), Vector2(12, 10), Vector2(15, 11), Vector2(11, 13), Vector2(14, 13)]

var _motes: CPUParticles2D


func _build() -> void:
	hop_peak = 4.0
	hop_rate = 2.8
	add_body_layer(_paint_ground_glow, true, 0)
	add_body_layer(_paint_fawn, false, 1)
	add_body_layer(_paint_glow, true, 2)
	var m: CPUParticles2D = add_motes(GLOW, 10, VfxTextures.dot(4), Vector2(0, -1))
	m.gravity = Vector2(0, -10.0)
	m.emission_sphere_radius = 5.0
	_motes = m


func _tick(delta: float) -> void:
	super(delta)
	_motes.emitting = is_hopping() or still_for >= GRAZE_AFTER_S


static func _frame(pose: String) -> ImageTexture:
	return PixelCanvas.cached("fawn_" + pose, W, H, func(c: PixelCanvas) -> void:
		var hd: Vector2
		var legs: Array[Vector2]
		match pose:
			"gathered":
				legs = [Vector2(8, 15), Vector2(10, 15), Vector2(14, 15), Vector2(16, 15)]
			"stretched":
				legs = [Vector2(5, 15), Vector2(7, 15), Vector2(17, 15), Vector2(19, 15)]
			_:
				legs = [Vector2(7, 15), Vector2(9, 15), Vector2(15, 15), Vector2(17, 15)]
		for i: int in legs.size():
			var lg: Vector2 = legs[i]
			var leg_len: float = 7.0 if pose != "gathered" else 5.0
			# One pixel wide: a deer is all slender legs.
			c.rect(lg.x, lg.y, 1.0, leg_len, COAT_SHADE if i % 2 == 0 else COAT)
			c.rect(lg.x, lg.y + leg_len, 1.0, 1.0, HOOF)
		# White tail tuft.
		c.ball(4.5, 10.5, 1.6, 1.8, COAT)
		# Body and pale belly.
		c.ball(12.0, 12.0, 7.0, 3.8, COAT)
		c.ball(12.5, 14.0, 5.0, 1.6, Color(1.0, 1.0, 0.98), 0.1, 0.0)
		if pose == "graze":
			# Neck down, nose to the grass.
			c.ball(18.0, 14.0, 2.4, 3.0, COAT)
			hd = Vector2(20.5, 18.5)
		else:
			c.ball(18.0, 9.0, 2.2, 3.4, COAT)
			hd = Vector2(20.0, 5.5)
		# Big ears.
		c.ball(hd.x - 3.6, hd.y - 2.2, 2.8, 1.4, COAT)
		c.ball(hd.x - 0.5, hd.y - 3.6, 1.4, 2.8, COAT_SHADE)
		c.ball(hd.x, hd.y, 3.2, 2.8, COAT)
		c.ball(hd.x + 2.8, hd.y + 1.0, 1.6, 1.2, COAT)    # muzzle
		c.finish(0.1, 0.22, 0.58)
		# Dappled fawn spots, baked in so they read even between glow pulses.
		for sp: Vector2 in SPOTS:
			c.px(sp.x, sp.y, DAPPLE)
		c.px(hd.x - 3.5, hd.y - 2.0, EAR_IN)
		c.px(hd.x - 0.5, hd.y - 3.5, EAR_IN)
		c.eye(hd.x + 0.5, hd.y - 1.0, 2, 2)
		c.px(hd.x + 4.0, hd.y + 1.0, HOOF)                 # nose
		c.px(hd.x - 1.0, hd.y + 1.0, Color(1.0, 0.65, 0.75))
	)


## Head position in sprite-local space (canvas - (13, 24)).
func _head(pose: String) -> Vector2:
	return Vector2(20.5 - 13.0, 18.5 - 24.0) if pose == "graze" else Vector2(20.0 - 13.0, 5.5 - 24.0)


func _pose() -> String:
	if still_for >= GRAZE_AFTER_S:
		return "graze" if fposmod(still_for, 5.0) < 3.4 else "stand"
	if not is_hopping():
		return "stand"
	return "gathered" if hop_phase < 0.4 or hop_phase > 0.9 else "stretched"


func _paint_fawn(layer: VfxDrawLayer) -> void:
	apply_hop(layer, 9.0)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	PixelCanvas.draw_sprite(layer, _frame(_pose()), Vector2(0.0, -hop_height), facing)


func _paint_glow(layer: VfxDrawLayer) -> void:
	var feet: Vector2 = Vector2(0.0, -hop_height)
	var pose: String = _pose()
	# Luminous spots, pulsing one after another along the back.
	for i: int in SPOTS.size():
		var pulse: float = 0.55 + 0.45 * sin(_elapsed * 2.5 - float(i) * 0.9)
		var p: Vector2 = feet + Vector2((SPOTS[i].x - 13.0) * facing, SPOTS[i].y - 24.0)
		if facing < 0.0:
			p.x -= 1.0
		layer.draw_rect(Rect2(p.round(), Vector2.ONE), Color(GLOW, pulse))
		layer.draw_circle(p + Vector2(0.5, 0.5), 2.0, Color(GLOW, 0.12 * pulse))
	# Crystal antler buds between the ears.
	var hd: Vector2 = feet + Vector2(_head(pose).x * facing, _head(pose).y)
	var bud: Vector2 = hd + Vector2(-1.5 * facing, -4.0)
	var shine: float = 0.7 + 0.3 * sin(_elapsed * 3.3)
	layer.draw_rect(Rect2(bud.round(), Vector2(1, 2)), Color(GLOW, shine))
	layer.draw_rect(Rect2((bud + Vector2(1.5 * facing, -0.5)).round(), Vector2(1, 2)), Color(GLOW, shine))
	layer.draw_circle(bud + Vector2(0.5, 0.0), 3.0, Color(GLOW, 0.14 * shine))


## Flowers opening in the grass while it grazes, drawn on the floor under it.
func _paint_ground_glow(layer: VfxDrawLayer) -> void:
	if still_for < GRAZE_AFTER_S:
		return
	var grow: float = clampf((still_for - GRAZE_AFTER_S) / 1.5, 0.0, 1.0)
	for i: int in 5:
		var start: float = float(i) * 0.15
		var k: float = clampf((grow - start) / 0.4, 0.0, 1.0)
		if k <= 0.0:
			continue
		var at: Vector2 = Vector2((-9.0 + float(i) * 4.5) * facing, 1.0 + float(i % 2) * 2.0).round()
		var col: Color = Color(FLOWER[i % FLOWER.size()], k)
		layer.draw_rect(Rect2(at + Vector2(-1, 0), Vector2(3, 1)), Color(col, k * 0.7))
		layer.draw_rect(Rect2(at + Vector2(0, -1), Vector2(1, 3)), Color(col, k * 0.7))
		layer.draw_rect(Rect2(at, Vector2.ONE), Color(1.0, 1.0, 0.9, k))
