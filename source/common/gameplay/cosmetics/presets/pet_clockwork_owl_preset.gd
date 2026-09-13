extends CompanionPreset
## CLOCKWORK OWL. A brass-and-copper automaton owl. It flies after the wearer on
## riveted wings trailing little puffs of steam, and when they stop it lands on
## top of their head, folds its wings, and sits there ticking - chest gear
## turning, glass lens-eyes glowing, head clicking round in steps to look about.
##
## PET slot - sold in the Vault's Pets tab, priced in PremiumCatalog.COSMETIC_COSTS.
##
## DETAILED PASS. The body is painted on a [PixelCanvas] (wings folded and two
## flap frames): brass plating in three tones, a copper chest plate ringed with
## rivets, iron eye sockets and a coloured outline. Live on top: the chest gear
## drawn turning, lens glow pulsing additively, the head's stepped click-turn,
## and steam. The perch uses the measured head height, so it sits on every skin.
##
## REACTS: it does not hide - it is a machine. While its owner mines it sweeps a
## scanning beam across the ground from its lenses, gear whirring. In a fight its
## lenses switch to red and its gear spins up.

## Has reactions of its own beyond the shared hide / cheer / level-up. The Vault
## reads this to shelve the pet under "Reactive Pets" (see cosmetics_menu.gd).
const THEMED_REACTIONS: bool = true

const FOLLOW: Vector2 = Vector2(-2, -38)
const FOLLOW_PX: float = 15.0
const PERCH_AFTER_S: float = 1.0

const BRASS: Color = Color(0.82, 0.62, 0.28)
const BRASS_DEEP: Color = Color(0.58, 0.40, 0.16)
const COPPER: Color = Color(0.74, 0.40, 0.22)
const IRON: Color = Color(0.30, 0.28, 0.32)
const RIVET: Color = Color(1.0, 0.90, 0.60)
const LENS: Color = Color(0.40, 0.95, 1.0)
const STEAM: Color = Color(0.92, 0.94, 1.0)

const W: int = 20
const H: int = 24

var _perched: bool = false
var _steam: CPUParticles2D


const LENS_ALERT: Color = Color(1.0, 0.30, 0.25)


func _build() -> void:
	hides_in_combat = false
	stiffness = 70.0
	damping = 11.0
	add_body_layer(_paint_scan_beam, true, 0)
	add_body_layer(_paint_owl, false, 0)
	add_body_layer(_paint_gear_and_face, false, 1)
	add_body_layer(_paint_lens_glow, true, 2)
	var s: CPUParticles2D = CPUParticles2D.new()
	s.amount = 6
	s.lifetime = 0.9
	s.local_coords = false
	s.texture = VfxTextures.puff(10)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.position = Vector2(-5, -12)
	s.direction = Vector2(-1, -1)
	s.spread = 25.0
	s.gravity = Vector2(0, -12.0)
	s.initial_velocity_min = 6.0
	s.initial_velocity_max = 12.0
	s.scale_amount_min = 0.4
	s.scale_amount_max = 0.8
	s.color_ramp = _fade_ramp(STEAM, 0.45)
	body.add_child(s)
	_steam = s


func target_local(_delta: float) -> Vector2:
	_perched = still_for >= PERCH_AFTER_S
	_steam.emitting = not _perched
	set_in_front(true)
	if _perched:
		stiffness = 160.0
		damping = 22.0
		return Vector2(0.0, wearer_head_top() - 0.5)
	stiffness = 70.0
	damping = 11.0
	return FOLLOW - _heading * FOLLOW_PX + Vector2(0, sin(_elapsed * 7.0) * 2.0)


static func _frame(pose: String) -> ImageTexture:
	return PixelCanvas.cached("clockowl_" + pose, W, H, func(c: PixelCanvas) -> void:
		var cx: float = 10.0
		# Wings: folded plates at the sides, or spread up / down.
		match pose:
			"up":
				for s: float in [-1.0, 1.0]:
					c.tri(Vector2(cx + s * 3.0, 12.0), Vector2(cx + s * 10.0, 3.0), Vector2(cx + s * 9.0, 12.0), BRASS_DEEP)
					c.tri(Vector2(cx + s * 3.0, 13.0), Vector2(cx + s * 8.0, 6.0), Vector2(cx + s * 7.0, 13.0), BRASS)
			"down":
				for s: float in [-1.0, 1.0]:
					c.tri(Vector2(cx + s * 3.0, 11.0), Vector2(cx + s * 10.0, 19.0), Vector2(cx + s * 8.0, 11.0), BRASS_DEEP)
					c.tri(Vector2(cx + s * 3.0, 12.0), Vector2(cx + s * 8.0, 17.0), Vector2(cx + s * 7.0, 12.0), BRASS)
			_:
				for s: float in [-1.0, 1.0]:
					c.ball(cx + s * 5.5, 15.0, 2.0, 5.5, BRASS_DEEP)
		# Body: a brass egg.
		c.ball(cx, 15.5, 5.6, 6.5, BRASS)
		# Copper chest plate.
		c.ball(cx, 16.5, 3.6, 4.2, COPPER, 0.22, 0.18)
		# Iron talons.
		c.rect(cx - 3.0, 22.0, 2.0, 2.0, IRON)
		c.rect(cx + 1.0, 22.0, 2.0, 2.0, IRON)
		# Head: a wide brass dome with ear tufts.
		c.tri(Vector2(cx - 6.0, 6.0), Vector2(cx - 3.0, 4.0), Vector2(cx - 6.5, 0.0), BRASS_DEEP)
		c.tri(Vector2(cx + 3.0, 4.0), Vector2(cx + 6.0, 6.0), Vector2(cx + 6.5, 0.0), BRASS_DEEP)
		c.ball(cx, 7.0, 6.0, 4.6, BRASS)
		c.finish(0.2, 0.3, 0.62)
		# Details: rivets round the chest plate, seam line across the head.
		for a: int in 8:
			var ang: float = float(a) * TAU / 8.0
			c.px(cx + cos(ang) * 3.4, 16.5 + sin(ang) * 4.0, RIVET)
		c.line(Vector2(cx - 5.0, 9.0), Vector2(cx + 5.0, 9.0), BRASS_DEEP)
		# Iron eye sockets (lenses are drawn live on top).
		for s: float in [-1.0, 1.0]:
			c.ellipse(cx + s * 2.6, 6.5, 2.2, 2.2, IRON)
		# Beak.
		c.tri(Vector2(cx - 1.0, 8.5), Vector2(cx + 1.0, 8.5), Vector2(cx, 11.0), RIVET.darkened(0.2))
	)


func _head_turn() -> float:
	# Clicks round in discrete steps, like a mechanism, rather than gliding.
	if not _perched:
		return 0.0
	var step: int = int(floor(still_for * 0.9)) % 4
	return [0.0, 1.0, 0.0, -1.0][step]


func _paint_owl(layer: VfxDrawLayer) -> void:
	var pose: String = "folded"
	if not _perched:
		pose = "up" if fposmod(_elapsed * 1.8, 1.0) < 0.5 else "down"
	PixelCanvas.draw_sprite(layer, _frame(pose), Vector2.ZERO)


func _paint_gear_and_face(layer: VfxDrawLayer) -> void:
	# Origin at the feet; the sprite is 24 tall with its margin.
	var top: float = -float(H) - 1.0
	var chest: Vector2 = Vector2(0.0, top + 17.5)
	# The gear: a hub, a rim and six teeth, turning.
	var busy: bool = activity() == &"combat" or activity() == &"pickaxe"
	var spin: float = _elapsed * (14.0 if busy else (2.0 if _perched else 6.0))
	layer.draw_arc(chest, 2.0, 0.0, TAU, 12, BRASS_DEEP.darkened(0.3), 1.0)
	for i: int in 6:
		var a: float = spin + float(i) * TAU / 6.0
		var tip: Vector2 = chest + Vector2(cos(a), sin(a)) * 2.8
		layer.draw_rect(Rect2(tip.round() - Vector2(0.5, 0.5), Vector2(1, 1)), RIVET)
	layer.draw_rect(Rect2(chest.round() - Vector2(0.5, 0.5), Vector2(1, 1)), IRON)
	# Lenses: offset by the head turn so the eyes look about.
	var turn: float = _head_turn()
	var lens: Color = LENS_ALERT if activity() == &"combat" else LENS
	for s: float in [-1.0, 1.0]:
		var e: Vector2 = (Vector2(s * 2.6 + turn, top + 7.5)).round()
		layer.draw_rect(Rect2(e.x - 1.0, e.y - 1.0, 2.0, 2.0), lens)
		layer.draw_rect(Rect2(e.x - 1.0, e.y - 1.0, 1.0, 1.0), Color.WHITE)


func _paint_lens_glow(layer: VfxDrawLayer) -> void:
	var top: float = -float(H) - 1.0
	var pulse: float = 0.7 + 0.3 * sin(_elapsed * 3.0)
	var turn: float = _head_turn()
	for s: float in [-1.0, 1.0]:
		var e: Vector2 = Vector2(s * 2.6 + turn, top + 7.5)
		var glow: Color = LENS_ALERT if activity() == &"combat" else LENS
		layer.draw_circle(e, 3.5, Color(glow, 0.18 * pulse))
		layer.draw_circle(e, 2.0, Color(glow, 0.25 * pulse))


## Mining: a cone of light from the lenses sweeping back and forth over the
## ground in front of its owner, like a prospector's detector.
func _paint_scan_beam(layer: VfxDrawLayer) -> void:
	if activity() != &"pickaxe":
		return
	var top: float = -float(H) - 1.0
	var eyes: Vector2 = Vector2(0.0, top + 7.5)
	# The ground is the owner's feet: the owl's own origin sits on their head.
	var s: float = maxf(0.001, global_scale.x)
	var ground_y: float = (global_position.y - body.global_position.y) / s
	var sweep: float = sin(_elapsed * 2.2) * 16.0
	var hit: Vector2 = Vector2(sweep, ground_y)
	var near: Color = Color(LENS, 0.22)
	var far: Color = Color(LENS, 0.0)
	layer.draw_polygon(
		PackedVector2Array([eyes + Vector2(-1.5, 0.0), eyes + Vector2(1.5, 0.0), hit + Vector2(5.0, 0.0), hit + Vector2(-5.0, 0.0)]),
		PackedColorArray([near, near, far, far])
	)
	layer.draw_set_transform(hit, 0.0, Vector2(1.0, 0.4))
	layer.draw_arc(Vector2.ZERO, 5.0, 0.0, TAU, 16, Color(LENS, 0.5), 1.0)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
