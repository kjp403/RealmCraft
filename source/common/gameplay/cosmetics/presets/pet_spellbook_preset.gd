extends CompanionPreset
## SPELLBOOK. An old tome that flies after the wearer by flapping its covers like
## wings, and when they stop it hovers open beside them, turning its own pages
## while glyphs float up off the paper.
##
## PET slot - sold in the Vault's Pets tab, priced in PremiumCatalog.COSMETIC_COSTS.
##
## Seen from the front, a book is its spine and two covers; how open it is sets
## how wide the covers project. Flying, the covers beat between half-shut and
## open. Idle, it lies fully open showing the pages, and a page sweeps across
## the spine every few seconds - its width runs through zero as it passes, which
## is what a turning page looks like head-on.

const FOLLOW: Vector2 = Vector2(0, -32)
const FOLLOW_PX: float = 15.0
const IDLE_AFTER_S: float = 0.6
const TURN_EVERY_S: float = 2.6
const TURN_S: float = 0.5

const COVER: Color = Color(0.40, 0.16, 0.42)
const COVER_EDGE: Color = Color(0.24, 0.08, 0.26)
const GILT: Color = Color(0.96, 0.78, 0.32)
const PAGE: Color = Color(0.96, 0.92, 0.80)
const PAGE_SHADE: Color = Color(0.82, 0.76, 0.62)
const INK: Color = Color(0.45, 0.38, 0.50)
const RUNE: Color = Color(0.80, 0.60, 1.0)

const W: float = 7.0
const H: float = 5.0

var _open: float = 0.5
var _glyphs: CPUParticles2D


func _build() -> void:
	stiffness = 75.0
	damping = 10.0
	add_body_layer(_paint_book, false, 0)
	var p: CPUParticles2D = CPUParticles2D.new()
	p.amount = 8
	p.lifetime = 1.1
	p.local_coords = false
	p.texture = VfxTextures.sparkle(7)
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.position = Vector2(0, -2)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(W, 1.0)
	p.direction = Vector2(0, -1)
	p.spread = 20.0
	p.gravity = Vector2(0, -8.0)
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 10.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 0.8
	p.color_ramp = _fade_ramp(RUNE, 0.9)
	p.material = _additive()
	body.add_child(p)
	_glyphs = p


func target_local(delta: float) -> Vector2:
	set_in_front(true)
	var idle: bool = still_for >= IDLE_AFTER_S
	_glyphs.emitting = idle
	if idle:
		_open = move_toward(_open, 1.0, delta * 3.0)
		return Vector2(-16.0 * signf(_heading.x if absf(_heading.x) > 0.1 else 1.0), -30.0 + sin(_elapsed * 1.6) * 1.5)
	# Flapping: covers beat between nearly shut and most of the way open.
	_open = 0.25 + 0.55 * absf(sin(_elapsed * 9.0))
	return FOLLOW - _heading * FOLLOW_PX + Vector2(0, sin(_elapsed * 9.0) * 1.5)


func _paint_book(layer: VfxDrawLayer) -> void:
	var span: float = W * _open
	# Covers splay a little toward the viewer at the outer edge as they open.
	var tilt: float = (1.0 - _open) * 2.0
	for side: float in [-1.0, 1.0]:
		var cover: PackedVector2Array = PackedVector2Array([
			Vector2(0, -H), Vector2(side * (span + 1.0), -H + tilt),
			Vector2(side * (span + 1.0), H + tilt), Vector2(0, H),
		])
		layer.draw_colored_polygon(cover, COVER)
		layer.draw_polyline(PackedVector2Array([cover[0], cover[1], cover[2], cover[3]]), COVER_EDGE, 1.0)
		layer.draw_rect(Rect2(side * (span + 1.0) - (1.0 if side > 0 else 0.0), -H + tilt, 1.0, 1.0), GILT)
	if _open > 0.6:
		for side: float in [-1.0, 1.0]:
			var page: PackedVector2Array = PackedVector2Array([
				Vector2(0, -H + 1.0), Vector2(side * span, -H + 1.0 + tilt),
				Vector2(side * span, H - 1.0 + tilt), Vector2(0, H - 1.0),
			])
			layer.draw_colored_polygon(page, PAGE)
			# Lines of text.
			for row: int in 3:
				var y: float = -H + 2.5 + float(row) * 2.0
				layer.draw_line(Vector2(side * 1.5, y), Vector2(side * (span - 1.5), y), INK, 1.0)
		# A page turning over, right to left.
		var t: float = fposmod(_elapsed, TURN_EVERY_S)
		if t < TURN_S:
			var k: float = t / TURN_S
			var edge: float = cos(k * PI) * span
			layer.draw_colored_polygon(PackedVector2Array([
				Vector2(0, -H + 1.0), Vector2(edge, -H + 0.0),
				Vector2(edge, H - 2.0), Vector2(0, H - 1.0),
			]), PAGE_SHADE if absf(edge) < span * 0.5 else PAGE)
	layer.draw_line(Vector2(0, -H), Vector2(0, H), GILT, 1.0)
