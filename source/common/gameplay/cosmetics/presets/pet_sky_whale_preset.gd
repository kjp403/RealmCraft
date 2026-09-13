extends CompanionPreset
## SKY WHALE. A little blue whale that swims through the air beside the wearer,
## tail flukes beating slowly, fins sculling. When they stop it drifts lazily
## beside them and every few seconds blows a spout of water from its blowhole
## that sprays up and rains back down.
##
## DETAILED PASS. Painted on a [PixelCanvas] (flukes up, flukes down): a blue
## back with pale spots, a pale grooved belly, a pectoral fin, tail flukes, a
## shiny eye and a smile. Live on top: the swim bob, the spout column and its
## falling droplets.
##
## REACTS: while its owner fishes it gets excited - swims lower and spouts again
## and again. A level-up gets its biggest spout, with a rainbow arcing through it.

## Has reactions of its own beyond the shared hide / cheer / level-up. The Vault
## reads this to shelve the pet under "Reactive Pets" (see cosmetics_menu.gd).
const THEMED_REACTIONS: bool = true

const FOLLOW: Vector2 = Vector2(0, -40)
const FOLLOW_PX: float = 18.0
const IDLE_AFTER_S: float = 0.8
const SPOUT_EVERY_S: float = 3.4
const SPOUT_S: float = 1.3

const BACK: Color = Color(0.36, 0.56, 0.88)
const BELLY: Color = Color(0.84, 0.92, 0.99)
const GROOVE: Color = Color(0.62, 0.74, 0.90)
const SPOT: Color = Color(0.62, 0.80, 1.0)
const WATER: Color = Color(0.70, 0.90, 1.0)

const W: int = 30
const H: int = 17

var _facing: float = 1.0


func _build() -> void:
	custom_level_up = true
	stiffness = 35.0
	damping = 7.0
	add_body_layer(_paint_whale, false, 0)
	add_body_layer(_paint_spout, false, 1)
	add_body_layer(_paint_rainbow, true, 2)


func _spout_every() -> float:
	return 1.1 if activity() == &"fishing_rod" else SPOUT_EVERY_S


func target_local(_delta: float) -> Vector2:
	set_in_front(true)
	if absf(_heading.x) > 0.2:
		_facing = signf(_heading.x)
	var bob: float = sin(_elapsed * 1.6) * 2.0
	if still_for < IDLE_AFTER_S:
		return FOLLOW - _heading * FOLLOW_PX + Vector2(0, bob)
	if activity() == &"fishing_rod":
		return Vector2(-20.0 * _facing, -30.0 + bob * 1.5)
	return Vector2(-20.0 * _facing, -42.0 + bob)


static func _frame(pose: String) -> ImageTexture:
	return PixelCanvas.cached("skywhale_" + pose, W, H, func(c: PixelCanvas) -> void:
		var up: bool = pose == "up"
		# Tail stalk and flukes.
		c.ball(5.5, 9.0, 3.2, 2.2, BACK)
		var fy: float = -2.0 if up else 2.0
		c.tri(Vector2(4.0, 8.5), Vector2(0.0, 4.0 + fy), Vector2(2.5, 9.0), BACK)
		c.tri(Vector2(4.0, 9.5), Vector2(0.0, 13.5 + fy), Vector2(2.5, 9.0), BACK)
		# Body: a long rounded torpedo with a pale belly.
		c.ball(15.5, 8.5, 11.5, 6.0, BACK)
		c.ball(17.0, 11.5, 8.5, 3.2, BELLY, 0.12, 0.06)
		# Pectoral fin, sculling.
		if up:
			c.tri(Vector2(15.0, 11.5), Vector2(11.0, 16.0), Vector2(18.0, 13.0), BACK.darkened(0.12))
		else:
			c.tri(Vector2(15.0, 11.5), Vector2(13.0, 17.0), Vector2(19.0, 13.0), BACK.darkened(0.12))
		c.finish(0.18, 0.22, 0.58)
		# Throat grooves along the belly.
		for gy: float in [11.0, 13.0]:
			c.line(Vector2(12.0, gy), Vector2(24.0, gy), GROOVE)
		# Pale spots scattered on the back.
		for sp: Vector2 in [Vector2(10, 5), Vector2(14, 4), Vector2(19, 4), Vector2(12, 7), Vector2(22, 6)]:
			c.px(sp.x, sp.y, SPOT)
		# Blowhole, eye, smile, blush.
		c.px(20.0, 3.0, BACK.darkened(0.45))
		c.eye(23.0, 7.0, 2, 2)
		c.line(Vector2(24.0, 10.0), Vector2(27.0, 9.0), BACK.darkened(0.5))
		c.px(21.0, 9.5, Color(1.0, 0.62, 0.72))
	)


func _paint_whale(layer: VfxDrawLayer) -> void:
	var rate: float = 3.0 if still_for < IDLE_AFTER_S else 1.4
	var up: bool = fposmod(_elapsed * rate / TAU, 1.0) < 0.5
	PixelCanvas.draw_sprite(layer, _frame("up" if up else "down"), Vector2.ZERO, _facing)


## Level-up: a rainbow arcing up through the spout.
func _paint_rainbow(layer: VfxDrawLayer) -> void:
	if not celebrating():
		return
	var k: float = celebration_t()
	var sweep: float = PI * clampf(k * 2.0, 0.0, 1.0)
	var fade: float = 1.0 - maxf(0.0, k - 0.7) / 0.3
	var colors: Array[Color] = [Color(1.0, 0.4, 0.4), Color(1.0, 0.75, 0.3), Color(1.0, 0.95, 0.4), Color(0.5, 0.9, 0.5), Color(0.45, 0.7, 1.0), Color(0.75, 0.55, 1.0)]
	var hole: Vector2 = Vector2(5.0 * _facing, -14.0)
	for i: int in colors.size():
		layer.draw_arc(hole + Vector2(0, 2), 16.0 - float(i), PI, PI + sweep, 20, Color(colors[i], 0.5 * fade), 1.0)


func _paint_spout(layer: VfxDrawLayer) -> void:
	var t: float
	if celebrating():
		t = celebration_t() * SPOUT_S
	else:
		if still_for < IDLE_AFTER_S + 0.8:
			return
		t = fposmod(still_for - IDLE_AFTER_S - 0.8, _spout_every())
	if t > SPOUT_S:
		return
	var k: float = t / SPOUT_S
	# Blowhole at canvas (20, 3) -> local (5, -14), mirrored with the whale.
	var hole: Vector2 = Vector2(5.0 * _facing, -14.0)
	# The column rises fast, then collapses.
	var height: float = sin(minf(k * 2.0, 1.0) * PI * 0.5) * 11.0 * (1.0 - maxf(0.0, k - 0.6) / 0.4)
	for i: int in int(height):
		var sway: float = roundf(sin(float(i) * 0.9 + _elapsed * 9.0) * 0.6)
		layer.draw_rect(Rect2(hole.x + sway, hole.y - float(i), 1.0, 1.0), Color(WATER, 0.9))
	# Droplets flung out at the top and raining back down.
	if k > 0.2:
		var d: float = (k - 0.2) / 0.8
		for j: int in 6:
			var side: float = -1.0 if j % 2 == 0 else 1.0
			var spread: float = (1.5 + float(j)) * side
			var at: Vector2 = hole + Vector2(spread * d * 2.0, -11.0 + d * d * 18.0 - float(j % 3))
			layer.draw_rect(Rect2(at.round(), Vector2.ONE), Color(WATER, 1.0 - d))
