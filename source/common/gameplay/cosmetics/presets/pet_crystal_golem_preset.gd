extends CompanionPreset
## CRYSTAL GOLEM. A little living geode: a faceted amethyst body with glowing
## eyes, floating along with three smaller crystal shards orbiting it, passing
## behind and in front. When the wearer stops the shards swing out into a wide
## slow ring, light sweeps across its facets, and it hums with an inner glow.
##
## PET slot - sold in the Vault's Pets tab, priced in PremiumCatalog.COSMETIC_COSTS.
##
## DETAILED PASS. Every crystal is painted on a [PixelCanvas]: flat facet planes
## in light / mid / deep tones with a bright edge line, which is how gems are
## drawn in pixel art. The shards are separate sprites so they can orbit in 3D
## (far ones drawn behind the body, near ones in front). A glint sweep runs
## across the facets and additive glow breathes underneath.

const FOLLOW: Vector2 = Vector2(0, -38)
const FOLLOW_PX: float = 15.0
const IDLE_AFTER_S: float = 0.8

const AMETHYST: Color = Color(0.64, 0.42, 0.95)
const AMETHYST_LIGHT: Color = Color(0.86, 0.72, 1.0)
const AMETHYST_DEEP: Color = Color(0.40, 0.22, 0.72)
const SHARD_COLORS: Array[Color] = [Color(0.45, 0.90, 1.0), Color(1.0, 0.55, 0.85), Color(0.60, 1.0, 0.70)]
const EYE: Color = Color(0.90, 1.0, 1.0)
const GLOW: Color = Color(0.70, 0.50, 1.0)

const W: int = 16
const H: int = 22


func _build() -> void:
	stiffness = 55.0
	damping = 9.0
	add_body_layer(_paint_glow, true, 0)
	add_body_layer(_paint_shards_far, false, 1)
	add_body_layer(_paint_core, false, 2)
	add_body_layer(_paint_glint, true, 3)
	add_body_layer(_paint_shards_near, false, 4)
	add_motes(AMETHYST_LIGHT, 10)


func target_local(_delta: float) -> Vector2:
	set_in_front(true)
	var bob: float = sin(_elapsed * 1.8) * 2.0
	if still_for < IDLE_AFTER_S:
		return FOLLOW - _heading * FOLLOW_PX + Vector2(0, bob)
	var side: float = -signf(_heading.x) if absf(_heading.x) > 0.1 else -1.0
	return Vector2(18.0 * side, -38.0 + bob)


static func _core() -> ImageTexture:
	return PixelCanvas.cached("crystal_core", W, H, func(c: PixelCanvas) -> void:
		var cx: float = 8.0
		# A hexagonal crystal: pointed top and bottom, three vertical facets.
		c.tri(Vector2(cx - 6.0, 6.0), Vector2(cx + 6.0, 6.0), Vector2(cx, 0.0), AMETHYST)
		c.rect(cx - 6.0, 6.0, 12.0, 10.0, AMETHYST)
		c.tri(Vector2(cx - 6.0, 16.0), Vector2(cx + 6.0, 16.0), Vector2(cx, 22.0), AMETHYST)
		c.finish(0.1, 0.1, 0.55)
		# Facet planes: light left, deep right, over the silhouette.
		c.tri(Vector2(cx - 5.0, 6.0), Vector2(cx - 1.0, 6.0), Vector2(cx - 0.5, 1.5), AMETHYST_LIGHT)
		c.rect(cx - 5.0, 6.0, 3.0, 10.0, AMETHYST_LIGHT)
		c.tri(Vector2(cx + 1.0, 6.0), Vector2(cx + 5.0, 6.0), Vector2(cx + 0.5, 1.5), AMETHYST_DEEP)
		c.rect(cx + 2.0, 6.0, 3.0, 10.0, AMETHYST_DEEP)
		c.tri(Vector2(cx - 5.0, 16.0), Vector2(cx - 1.0, 16.0), Vector2(cx - 0.5, 20.5), AMETHYST_LIGHT.darkened(0.12))
		c.tri(Vector2(cx + 1.0, 16.0), Vector2(cx + 5.0, 16.0), Vector2(cx + 0.5, 20.5), AMETHYST_DEEP.darkened(0.15))
		# A bright edge where the lit facet meets the middle one, and a star glint.
		# Kept one column left of the face: on the face column it crossed the eye
		# and read as a stray letter carved into the crystal.
		c.line(Vector2(cx - 3.0, 7.0), Vector2(cx - 3.0, 15.0), Color(1, 1, 1, 0.75))
		c.px(cx - 4.0, 3.0, Color.WHITE)
		# Face, carved into the middle facet.
		c.rect(cx - 2.0, 10.0, 1.0, 2.0, AMETHYST_DEEP.darkened(0.55))
		c.rect(cx + 1.0, 10.0, 1.0, 2.0, AMETHYST_DEEP.darkened(0.55))
		c.px(cx - 1.0, 13.0, AMETHYST_DEEP.darkened(0.5))
		c.px(cx, 13.0, AMETHYST_DEEP.darkened(0.5))
	)


static func _shard(i: int) -> ImageTexture:
	var col: Color = SHARD_COLORS[i % SHARD_COLORS.size()]
	return PixelCanvas.cached("crystal_shard_%d" % i, 6, 9, func(c: PixelCanvas) -> void:
		c.tri(Vector2(0.0, 3.0), Vector2(6.0, 3.0), Vector2(3.0, 0.0), col)
		c.rect(0.0, 3.0, 6.0, 3.0, col)
		c.tri(Vector2(0.0, 6.0), Vector2(6.0, 6.0), Vector2(3.0, 9.0), col)
		c.finish(0.1, 0.1, 0.55)
		c.rect(0.0, 3.0, 2.0, 3.0, col.lightened(0.35))
		c.rect(4.0, 3.0, 2.0, 3.0, col.darkened(0.3))
		c.px(1.0, 2.0, Color.WHITE)
	)


## Orbit position and depth (sin > 0 is near) of shard [param i].
func _shard_at(i: int) -> Array:
	var idle: bool = still_for >= IDLE_AFTER_S
	var a: float = _elapsed * (0.9 if idle else 2.2) + float(i) * TAU / 3.0
	var r: float = 15.0 if idle else 11.0
	var at: Vector2 = Vector2(cos(a) * r, -11.0 + sin(a) * r * 0.32 + sin(_elapsed * 2.0 + float(i)) * 1.5)
	return [at, sin(a)]


func _paint_shards_far(layer: VfxDrawLayer) -> void:
	_paint_shards(layer, false)


func _paint_shards_near(layer: VfxDrawLayer) -> void:
	_paint_shards(layer, true)


func _paint_shards(layer: VfxDrawLayer, near: bool) -> void:
	for i: int in 3:
		var s: Array = _shard_at(i)
		if (float(s[1]) > 0.0) != near:
			continue
		# Far shards are dimmer, as if further into the dark.
		var shade: float = lerpf(0.65, 1.0, 0.5 + 0.5 * float(s[1]))
		PixelCanvas.draw_sprite(layer, _shard(i), (s[0] as Vector2).round() + Vector2(0, 5), 1.0, Color(shade, shade, shade))


func _paint_core(layer: VfxDrawLayer) -> void:
	PixelCanvas.draw_sprite(layer, _core(), Vector2.ZERO)
	# Glowing eyes, live so they can blink.
	var top: float = -float(H) - 1.0
	if not blinking(3.8, 0.9):
		# Over the carved sockets at canvas x 6 and 9; sprite-local x is canvas x - 8.
		for ex: float in [-2.0, 1.0]:
			layer.draw_rect(Rect2(ex, top + 11.0, 1.0, 2.0), EYE)


func _paint_glow(layer: VfxDrawLayer) -> void:
	var breathe: float = 0.75 + 0.25 * sin(_elapsed * (1.6 if still_for >= IDLE_AFTER_S else 3.0))
	layer.draw_circle(Vector2(0, -12), 16.0, Color(GLOW, 0.07 * breathe))
	layer.draw_circle(Vector2(0, -12), 10.0, Color(GLOW, 0.14 * breathe))


## A band of light sweeping down across the facets every couple of seconds,
## kept inside the body's middle section so it never spills past the crystal.
func _paint_glint(layer: VfxDrawLayer) -> void:
	var t: float = fposmod(_elapsed, 2.4)
	if t > 0.6:
		return
	var k: float = t / 0.6
	var top: float = -float(H) - 1.0
	var y: float = roundf(top + 7.0 + k * 9.0)
	layer.draw_rect(Rect2(-5.0, y, 11.0, 1.0), Color(1.0, 1.0, 1.0, 0.55 * sin(k * PI)))
