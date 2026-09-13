extends CompanionPreset
## PHOENIX CHICK. A fluffy baby phoenix flapping along at the wearer's shoulder,
## a crest of live flame on its head and fire streaming off its tail feathers,
## shedding embers. When they stop it hovers beside them - and every few seconds
## it bursts into flame, curls into a blazing egg of fire, and hatches back out
## with a ring of sparks: a tiny rebirth.
##
## PET slot - sold in the Vault's Pets tab, priced in PremiumCatalog.COSMETIC_COSTS.
##
## DETAILED PASS. The bird is painted on a [PixelCanvas] (two wing frames) with
## three-tone plumage, a golden beak, a shiny eye and a coloured outline. The
## FIRE is live on top: additive flame tongues for the crest and tail that
## flicker every frame, a heat glow, and ember particles - the part a baked
## sprite could never animate.
##
## REACTS: it does not hide - in a fight it BLAZES, crest and tail flames doubling
## and the heat glow flaring. While its owner mines, sparks fly off the rock with
## every strike. A level-up is a rebirth: it bursts into its egg of fire and
## hatches out in a ring of sparks.

## Has reactions of its own beyond the shared hide / cheer / level-up. The Vault
## reads this to shelve the pet under "Reactive Pets" (see cosmetics_menu.gd).
const THEMED_REACTIONS: bool = true

const FOLLOW: Vector2 = Vector2(0, -36)
const FOLLOW_PX: float = 16.0
const IDLE_AFTER_S: float = 0.8
const REBIRTH_EVERY_S: float = 5.5
const REBIRTH_S: float = 1.5

const PLUME: Color = Color(0.95, 0.36, 0.14)
const PLUME_DEEP: Color = Color(0.78, 0.16, 0.10)
const BELLY: Color = Color(1.0, 0.80, 0.34)
const HEAD: Color = Color(1.0, 0.54, 0.18)
const BEAK: Color = Color(1.0, 0.86, 0.36)
const FIRE: Color = Color(1.0, 0.50, 0.12)
const FIRE_HOT: Color = Color(1.0, 0.86, 0.40)
const FIRE_CORE: Color = Color(1.0, 0.98, 0.80)

const W: int = 22
const H: int = 20

var _facing: float = 1.0
var _embers: CPUParticles2D


func _build() -> void:
	hides_in_combat = false
	custom_level_up = true
	stiffness = 70.0
	damping = 10.0
	add_body_layer(_paint_glow, true, 0)
	add_body_layer(_paint_tail_fire, true, 1)
	add_body_layer(_paint_bird, false, 2)
	add_body_layer(_paint_crest, true, 3)
	var e: CPUParticles2D = add_motes(FIRE_HOT, 14, VfxTextures.dot(3), Vector2(0, -8))
	e.gravity = Vector2(0, -22.0)
	e.lifetime = 0.9
	_embers = e


func target_local(_delta: float) -> Vector2:
	set_in_front(true)
	if absf(_heading.x) > 0.2:
		_facing = signf(_heading.x)
	if still_for < IDLE_AFTER_S:
		return FOLLOW - _heading * FOLLOW_PX + Vector2(0, sin(_elapsed * 8.0) * 1.5)
	return Vector2(-17.0 * _facing, -36.0 + sin(_elapsed * 2.5) * 2.0)


## 0 normal; during a rebirth, 0 -> 1 -> 0 as it curls into fire and back out.
func _rebirth() -> float:
	if celebrating():
		return sin(celebration_t() * PI)
	# No idle rebirth mid-fight: curled in an egg is the opposite of blazing.
	if activity() == &"combat":
		return 0.0
	if still_for < IDLE_AFTER_S + 1.0:
		return 0.0
	var t: float = fposmod(still_for - IDLE_AFTER_S - 1.0, REBIRTH_EVERY_S)
	if t > REBIRTH_S:
		return 0.0
	return sin(t / REBIRTH_S * PI)


static func _frame(wings_up: bool) -> ImageTexture:
	return PixelCanvas.cached("phoenix_" + ("up" if wings_up else "down"), W, H, func(c: PixelCanvas) -> void:
		# Tail feathers: three long plumes sweeping back and down.
		c.tri(Vector2(6.0, 12.0), Vector2(0.0, 16.0), Vector2(4.0, 18.0), PLUME_DEEP)
		c.tri(Vector2(7.0, 13.0), Vector2(1.0, 19.0), Vector2(6.0, 18.5), PLUME)
		c.tri(Vector2(8.0, 13.5), Vector2(4.0, 20.0), Vector2(8.5, 18.0), PLUME_DEEP)
		# Far wing.
		if wings_up:
			c.tri(Vector2(8.0, 9.0), Vector2(3.0, 2.0), Vector2(1.0, 8.0), PLUME_DEEP)
		else:
			c.tri(Vector2(8.0, 11.0), Vector2(1.0, 15.0), Vector2(2.0, 10.0), PLUME_DEEP)
		# Round fluffy body and belly.
		c.ball(10.5, 12.0, 5.6, 5.0, PLUME)
		c.ball(12.0, 13.5, 3.4, 3.0, BELLY, 0.18, 0.12)
		# Fluff tufts on the chest.
		c.px(10.0, 16.5, BELLY)
		c.px(13.0, 16.5, BELLY)
		# Big head.
		c.ball(14.5, 6.5, 4.4, 4.2, HEAD)
		# Beak.
		c.tri(Vector2(17.5, 5.5), Vector2(21.5, 7.0), Vector2(17.5, 8.5), BEAK)
		# Little feet tucked under.
		c.rect(9.0, 17.0, 1.0, 2.0, BEAK.darkened(0.3))
		c.rect(12.0, 17.0, 1.0, 2.0, BEAK.darkened(0.3))
		# Near wing, over the body: the flap.
		if wings_up:
			c.tri(Vector2(9.0, 10.0), Vector2(6.0, 1.0), Vector2(3.0, 7.0), PLUME)
			c.tri(Vector2(9.0, 10.0), Vector2(5.0, 4.0), Vector2(4.0, 8.0), PLUME.lightened(0.15))
		else:
			c.tri(Vector2(10.0, 11.0), Vector2(3.0, 17.0), Vector2(4.0, 11.0), PLUME)
			c.tri(Vector2(9.5, 11.5), Vector2(5.0, 15.0), Vector2(5.0, 12.0), PLUME.lightened(0.15))
		c.finish(0.18, 0.26, 0.6)
		# Details.
		c.eye(15.0, 5.0, 2, 3)
		c.px(13.0, 8.0, Color(1.0, 0.55, 0.65))
		c.px(18.0, 7.0, BEAK.darkened(0.35))
		# Feather tips on the wing edge.
		c.px(4.0, 7.0 if wings_up else 11.0, FIRE_HOT)
		c.px(6.0, 4.0 if wings_up else 14.0, FIRE_HOT)
	)


## 1 normally; bigger in a fight.
func _blaze() -> float:
	return 1.7 if activity() == &"combat" else 1.0


func _paint_glow(layer: VfxDrawLayer) -> void:
	var flick: float = (0.85 + 0.15 * sin(_elapsed * 13.0) * sin(_elapsed * 5.0)) * _blaze()
	var r: float = _rebirth()
	layer.draw_circle(Vector2(0, -9), 15.0 + r * 6.0, Color(FIRE, (0.07 + r * 0.12) * flick))
	layer.draw_circle(Vector2(0, -9), 9.0 + r * 4.0, Color(FIRE, (0.12 + r * 0.18) * flick))


## Sparks thrown off the rock face in front of the owner on every strike.
func _paint_mining_sparks(layer: VfxDrawLayer) -> void:
	var strike: float = fposmod(_elapsed * 1.8, 1.0)
	if strike > 0.35:
		return
	var k: float = strike / 0.35
	var hit: Vector2 = owner_local() + Vector2(12.0 * owner_front(), -8.0)
	for i: int in 6:
		var a: float = -PI * 0.5 + (float(i) - 2.5) * 0.45
		var d: Vector2 = Vector2(cos(a) * owner_front() * -1.0, sin(a))
		var at: Vector2 = hit + d * (2.0 + k * 9.0) + Vector2(0.0, k * k * 6.0)
		layer.draw_rect(Rect2(at.round(), Vector2.ONE), Color(FIRE_HOT, 1.0 - k))


## A flame tongue from [param root] along [param dir].
func _tongue(layer: VfxDrawLayer, root: Vector2, dir: Vector2, width: float, length: float, col: Color) -> void:
	var side: Vector2 = dir.orthogonal()
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 7:
		var a: float = PI * float(i) / 6.0
		pts.append(root + (side * cos(a) - dir * sin(a)) * width)
	pts.append(root - side * width * 0.6 + dir * length * 0.5)
	pts.append(root + dir * length)
	pts.append(root + side * width * 0.6 + dir * length * 0.5)
	layer.draw_colored_polygon(pts, col)


func _paint_tail_fire(layer: VfxDrawLayer) -> void:
	var r: float = _rebirth()
	var f: float = _facing
	for i: int in 3:
		var sway: float = sin(_elapsed * 9.0 + float(i) * 1.7) * 0.25
		var dir: Vector2 = Vector2.from_angle(PI * 0.82 + float(i) * 0.18 + sway)
		dir.x *= f
		var root: Vector2 = Vector2((-5.0 + float(i)) * f, -4.0 + float(i) * 0.5)
		var flick: float = 1.0 + 0.2 * sin(_elapsed * 17.0 + float(i))
		_tongue(layer, root, dir, 2.2 * _blaze(), (7.0 + r * 5.0) * flick * _blaze(), Color(FIRE, 0.7))
		_tongue(layer, root, dir, 1.1 * _blaze(), (4.5 + r * 3.0) * flick * _blaze(), Color(FIRE_HOT, 0.8))


func _paint_bird(layer: VfxDrawLayer) -> void:
	var r: float = _rebirth()
	var flap_rate: float = 12.0 if still_for < IDLE_AFTER_S else 7.0
	var up: bool = fposmod(_elapsed * flap_rate / TAU, 1.0) < 0.5
	if r > 0.55:
		# Curled up inside the egg of fire: the bird is hidden by the blaze.
		_paint_egg(layer, r)
		return
	PixelCanvas.draw_sprite(layer, _frame(up), Vector2(0.0, 0.0), _facing, Color(1, 1, 1, 1.0 - r))
	if r > 0.0:
		_paint_egg(layer, r)


## The rebirth: an egg of flame that swells round the bird, then a spark ring as
## it hatches back out.
func _paint_egg(layer: VfxDrawLayer, r: float) -> void:
	var c: Vector2 = Vector2(0, -10)
	layer.draw_set_transform(c, 0.0, Vector2(0.85, 1.0))
	layer.draw_circle(Vector2.ZERO, 9.0 * r, Color(FIRE, 0.9 * r))
	layer.draw_circle(Vector2(-1, -1), 6.0 * r, Color(FIRE_HOT, 0.95 * r))
	layer.draw_circle(Vector2(-2, -2), 3.0 * r, Color(FIRE_CORE, r))
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _paint_crest(layer: VfxDrawLayer) -> void:
	var r: float = _rebirth()
	var f: float = _facing
	# Crest: three little flames licking up off the back of the head.
	if r < 0.55:
		for i: int in 3:
			var sway: float = sin(_elapsed * 11.0 + float(i) * 2.1) * 0.3
			var dir: Vector2 = Vector2.from_angle(-PI * 0.5 - 0.35 * f + (float(i) - 1.0) * 0.35 * f + sway)
			var root: Vector2 = Vector2((3.0 + float(i) * 1.2) * f, -16.0 + absf(float(i) - 1.0))
			var flick: float = 1.0 + 0.25 * sin(_elapsed * 19.0 + float(i) * 3.0)
			_tongue(layer, root, dir, 1.6 * _blaze(), 6.0 * flick * _blaze(), Color(FIRE, 0.85))
			_tongue(layer, root, dir, 0.8 * _blaze(), 3.5 * flick * _blaze(), Color(FIRE_CORE, 0.9))
	if activity() == &"pickaxe":
		_paint_mining_sparks(layer)
	# The level-up hatch.
	if celebrating():
		var burst_l: float = (celebration_t() - 0.55) / 0.45
		if burst_l > 0.0 and burst_l < 1.0:
			for i: int in 14:
				var a: float = float(i) * TAU / 14.0
				var at: Vector2 = Vector2(0, -10) + Vector2(cos(a), sin(a)) * (6.0 + burst_l * 18.0)
				layer.draw_rect(Rect2(at.round(), Vector2(1, 1)), Color(FIRE_CORE, 1.0 - burst_l))
		return
	# The hatch: a ring of sparks thrown out as the egg bursts.
	if still_for >= IDLE_AFTER_S + 1.0:
		var t: float = fposmod(still_for - IDLE_AFTER_S - 1.0, REBIRTH_EVERY_S)
		var burst: float = (t - REBIRTH_S * 0.6) / 0.6
		if burst > 0.0 and burst < 1.0:
			for i: int in 10:
				var a: float = float(i) * TAU / 10.0
				var at: Vector2 = Vector2(0, -10) + Vector2(cos(a), sin(a)) * (6.0 + burst * 14.0)
				layer.draw_rect(Rect2(at.round(), Vector2(1, 1)), Color(FIRE_CORE, 1.0 - burst))
