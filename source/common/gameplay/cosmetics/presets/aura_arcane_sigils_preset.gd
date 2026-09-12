extends ThemeAuraPreset
## ARCANE SIGILS. The matching aura for the Arcane Magus title: a violet circle
## with gold glyphs turning around the wearer at chest height.
##
## THE SIGILS STAND UPRIGHT AND THE CIRCLE LIES FLAT, and that split is the whole
## illusion. A glyph squashed onto the ground plane reads as painted on the floor;
## the same glyph drawn upright, at a height that rises and falls as it goes
## round, reads as an object hanging in the air and orbiting. The vertical bob is
## doing the work that perspective would do if this were 3D.
##
##   RING    the shared theme circle.
##   SIGILS  six glyphs orbiting at chest height, each a handful of pixels, each
##           fading as it passes BEHIND the wearer so the ring reads as a ring.
##   MOTES   violet dust rising through them.

const SIGIL_COUNT: int = 6
## Seconds per orbit. Slower than the floor ring, so the two are never in step and
## the eye keeps finding new arrangements.
const ORBIT_PERIOD_S: float = 11.0
## How far the glyphs rise and fall over one orbit, in px. This is the depth cue,
## and it has to be a real fraction of the orbit's width or the six marks land in
## a straight horizontal row and read as floating TEXT rather than as a ring.
const BOB_PX: float = 9.0
## Orbit radius. Inside the floor ring rather than outside it: a mark orbiting
## wider than the circle it belongs to looks like it came off something else.
const ORBIT_RADIUS: float = BASE_RADIUS * 0.92
## Height of the orbit, in local space (origin is the feet).
##
## NOT [constant CosmeticPreset.CHEST_Y]: those landmarks are for a 64px cell and
## the figure inside one fills its lower two thirds, so CHEST_Y sits level with the
## top of the head and the sigils orbited ABOVE the wearer like a crown. Measured
## against the real stand-in body in the proof capture.
const ORBIT_Y: float = -17.0


func theme() -> StringName:
	return CosmeticThemes.ARCANE


func _build() -> void:
	var p: CPUParticles2D = _add_emitter(12, 2.2, VfxTextures.dot(6))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	p.emission_points = _ring_points(12, BASE_RADIUS * 0.85)
	p.direction = Vector2(0, -1)
	p.spread = 30.0
	p.gravity = Vector2(0, -12.0)
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 16.0
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.9
	p.color_ramp = _swell_ramp(core(), Color(pale(), 0.8), 0.3)
	p.material = _additive()


func _draw() -> void:
	_use_ground_plane()
	draw_theme_ring()
	_draw_sigils()


## The orbiting glyphs. Each is built from its own index, so the ring carries a
## repeating but non-uniform inscription - readable as writing rather than as six
## identical stamps.
func _draw_sigils() -> void:
	_use_upright_plane()
	var turn: float = _elapsed * TAU / ORBIT_PERIOD_S
	for i: int in SIGIL_COUNT:
		var angle: float = turn + float(i) * TAU / float(SIGIL_COUNT)
		# sin(angle) is +1 at the near side and -1 at the far side: the same term
		# lifts the glyph, brightens it and widens it, which is every depth cue
		# available in a flat draw pass.
		var near: float = 0.5 + 0.5 * sin(angle)
		var at: Vector2 = Vector2(
			cos(angle) * ORBIT_RADIUS,
			ORBIT_Y - BOB_PX * sin(angle)
		)
		var alpha: float = 0.35 + 0.6 * near
		var tint: Color = accent().lerp(pale(), near * 0.5)
		_draw_glyph(at, i, Color(tint, alpha))
		# A dim violet backing behind each glyph, so a gold mark never sits on a
		# bright tile with nothing to read it against.
		draw_circle(at, 2.6, Color(core(), 0.12 * alpha))


## One glyph: a stem plus two or three strokes chosen by index. Pixel rectangles
## rather than lines, because a 3px rune drawn with draw_line lands on half pixels
## and turns to mush against 64px art.
##
## EVERY STROKE IS OFF-CENTRE, and that is not decoration. The obvious version -
## a centred stem with a bar across the top - is the letter T, and a ring of them
## reads as floating text in a way that is impossible to un-see once noticed.
## Asymmetric marks read as an alphabet nobody knows, which is the whole idea.
##
## Kept to three pixels across as well: these orbit a 64px body, and a five-pixel
## mark next to it is signage rather than a sigil.
func _draw_glyph(at: Vector2, index: int, tint: Color) -> void:
	var shape: int = index % 4
	draw_rect(Rect2(at - Vector2(0.5, 1.5), Vector2(1.0, 3.0)), tint)
	if shape == 0:
		draw_rect(Rect2(at + Vector2(-1.5, -1.5), Vector2(2.0, 1.0)), tint)
		draw_rect(Rect2(at + Vector2(0.5, 1.5), Vector2(1.0, 1.0)), tint)
	elif shape == 1:
		draw_rect(Rect2(at + Vector2(0.5, -0.5), Vector2(2.0, 1.0)), tint)
		draw_rect(Rect2(at + Vector2(-1.5, 1.5), Vector2(1.0, 1.0)), tint)
	elif shape == 2:
		draw_rect(Rect2(at + Vector2(-2.0, -1.5), Vector2(1.0, 2.0)), tint)
		draw_rect(Rect2(at + Vector2(-1.5, 0.5), Vector2(2.0, 1.0)), tint)
	else:
		draw_rect(Rect2(at + Vector2(0.5, -1.5), Vector2(1.0, 2.0)), tint)
		draw_rect(Rect2(at + Vector2(-1.5, -1.5), Vector2(1.0, 1.0)), tint)
