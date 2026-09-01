extends CosmeticPreset
## RUNEBOUND TITAN (ancient magic). Three concentric stone rings geared into each
## other, turning in alternating directions under the wearer, while carved runes
## rise out of them and snap into alignment before burning out.
##
## MECHANICAL HOOK: a real gear train. The rings do not merely spin opposite ways
## - each ring's angular speed is derived from its RADIUS, so every ring's teeth
## travel at the same linear speed at the point where they mesh. That is the
## actual constraint on interlocking gears, and it is the whole reason the three
## rings read as one mechanism instead of three stacked spinning hoops. Get it
## wrong and the teeth visibly slide through each other.
##
## SECOND HOOK: the runes SNAP. Every other particle layer in the set moves
## continuously, because that is all a particle system can do. These are drawn, so
## they can rise at a random offset and then jump - instantly, no easing - onto a
## quantised slot, hold there, and fade. That discontinuity is the read: something
## is aligning them, which is what "runebound" has to look like.
##
##   RINGS  three toothed stone bands, mix-blended, carved and lit.
##   RUNES  drawn on an additive layer above the stone (see _add_draw_layer for
##          why they cannot share the stone's node).

const STONE_DARK: Color = Color(0.16, 0.14, 0.13)
const STONE_MID: Color = Color(0.34, 0.30, 0.27)
const STONE_LIT: Color = Color(0.52, 0.47, 0.42)
const RUNE_GLOW: Color = Color(1.0, 0.72, 0.28)
const RUNE_HOT: Color = Color(1.0, 0.93, 0.72)

## Ring radii, outermost first. Each ring meshes with the next one in.
const RING_RADII: Array[float] = [31.0, 21.5, 12.0]
## Teeth per ring. Kept proportional to radius so tooth SIZE is roughly constant
## around the mechanism - teeth that grow with the ring look moulded, not cut.
const RING_TEETH: Array[int] = [14, 10, 6]
## Radians/sec of the OUTER ring. The rest are derived from it in _ring_spin.
const BASE_SPIN: float = 0.30

const RUNE_COUNT: int = 7
## Seconds for one rune to rise, snap, hold and fade.
const RUNE_CYCLE_S: float = 3.1
## Point in that cycle where the rune stops drifting and jumps onto its slot.
const SNAP_AT: float = 0.46
## Angular slots a rune can snap to. A power of two reads as deliberate.
const RUNE_SLOTS: int = 8

## Per-rune roll: drift offset, target slot, glyph seed. Rolled once so a rune
## keeps its identity for its whole life.
var _runes: Array[Dictionary] = []


func _build() -> void:
	_roll_runes()
	# Runes go on their own additive layer above the stone, at the SAME z as this
	# preset rather than one above it. A child at equal z already draws after its
	# parent's own _draw(), which is all the ordering the runes need - and raising
	# it by one would put them at effective z 0, tying with the player sprite and
	# (on tree order) painting over the body, which is the one thing every layer
	# in this set is supposed to stay under.
	_add_draw_layer(_paint_runes, true, 0)


func _roll_runes() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	for i: int in RUNE_COUNT:
		_runes.append({
			# Where it drifts before the snap, and which slot it snaps ONTO. The
			# two are unrelated on purpose - the jump has to be visible.
			"drift": rng.randf_range(-13.0, 13.0),
			"slot": rng.randi_range(0, RUNE_SLOTS - 1),
			"glyph": rng.randi(),
			"phase": float(i) / float(RUNE_COUNT) + rng.randf() * 0.06,
			"radius": rng.randf_range(0.45, 0.95),
		})


## Angular speed of ring [param index], signed.
##
## Gear law: meshing teeth share a linear speed, so w scales as 1/r, and every
## mesh reverses direction. Both fall out of this one expression, which is why
## there is no hand-tuned per-ring speed table to drift out of sync.
func _ring_spin(index: int) -> float:
	var direction: float = 1.0 if index % 2 == 0 else -1.0
	return direction * BASE_SPIN * (RING_RADII[0] / RING_RADII[index])


func _draw() -> void:
	_use_ground_plane()
	# Innermost first so the outer rings overlap it at the mesh points, which is
	# what puts the outer ring visibly in FRONT and gives the stack depth.
	for i: int in range(RING_RADII.size() - 1, -1, -1):
		_draw_ring(i)


## One toothed stone ring: a dark band, a lit upper edge, and teeth alternating
## in and out so it can mesh with the ring on either side of it.
func _draw_ring(index: int) -> void:
	var radius: float = RING_RADII[index]
	var teeth: int = RING_TEETH[index]
	var spin: float = _elapsed * _ring_spin(index)
	var band: float = 4.0

	# Dark outline first, then the stone face inside it. Two passes rather than
	# one: a single mid-grey arc on a dark floor has no edge and reads as a
	# painted circle, and the outline is what gives the band a carved lip.
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 56, Color(STONE_DARK, 0.95), band, false)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 56, Color(STONE_MID, 0.95), band - 1.6, false)
	# A thin lit arc riding just inside the face. Offsetting the highlight inward
	# rather than centring it is what makes the band read as a raised ridge with a
	# top face, instead of as a flat stripe.
	draw_arc(Vector2.ZERO, radius - 1.1, 0.0, TAU, 56, Color(STONE_LIT, 0.55), 1.0, false)

	for t: int in teeth:
		var angle: float = spin + float(t) * TAU / float(teeth)
		# Teeth alternate pointing out and in around each ring, so whichever
		# neighbour a ring meshes with finds teeth waiting for it.
		var outward: bool = t % 2 == 0
		var reach: float = radius + (band * 1.35 if outward else -band * 1.35)
		var tip: Vector2 = _ground_point(angle, reach)
		var root: Vector2 = _ground_point(angle, radius)
		draw_line(root, tip, Color(STONE_DARK, 1.0), 3.6)
		draw_line(root, tip, Color(STONE_MID, 0.95), 2.2)
		draw_line(root, tip.lerp(root, 0.4), Color(STONE_LIT, 0.6), 1.0)

	# Carved runes cut into the band itself, lighting as they come round the near
	# side. These are STONE, not the floating runes - they never leave the ring.
	for c: int in teeth / 3:
		var angle: float = spin * 0.98 + float(c) * TAU / float(maxi(1, teeth / 3))
		var at: Vector2 = _ground_point(angle, radius)
		var lit: float = 0.35 + 0.65 * (0.5 + 0.5 * sin(angle))
		var pulse: float = 0.6 + 0.4 * sin(_elapsed * 1.7 + float(index) * 2.1)
		draw_rect(
			Rect2(at - Vector2(0.9, 0.9), Vector2(1.8, 1.8)),
			Color(RUNE_GLOW, 0.55 * lit * pulse)
		)


## Runes lifting off the mechanism, drawn on the additive layer.
##
## The cycle is: RISE with a random sideways drift, SNAP onto a slot, HOLD, FADE.
## The snap is a hard branch rather than a lerp - easing into the slot would just
## look like the drift slowing down, and the point is that something grabbed it.
func _paint_runes(layer: Node2D) -> void:
	if not _viewer_in_range():
		return
	for rune: Dictionary in _runes:
		var phase: float = fposmod(_elapsed / RUNE_CYCLE_S + float(rune["phase"]), 1.0)
		var rise: float = smoothstep(0.0, 0.85, phase)
		var height: float = lerpf(-2.0, CHEST_Y - 2.0, rise)

		var slot_angle: float = float(int(rune["slot"])) * TAU / float(RUNE_SLOTS)
		var aligned: Vector2 = _ground_point(slot_angle, BASE_RADIUS * float(rune["radius"]))

		var at: Vector2
		var spin: float
		var flash: float = 0.0
		if phase < SNAP_AT:
			# Drifting: off its slot, and tumbling.
			at = Vector2(aligned.x + float(rune["drift"]), aligned.y * 0.5 + height)
			spin = phase * 6.0
		else:
			# Snapped: exactly on the slot, exactly upright, for the rest of its
			# life. Nothing interpolates across this boundary.
			at = Vector2(aligned.x, aligned.y * 0.5 + height)
			spin = 0.0
			# A bright pop on the frame it lands, decaying fast - the impact of
			# the alignment, and what draws the eye to the discontinuity.
			flash = pow(1.0 - clampf((phase - SNAP_AT) / 0.12, 0.0, 1.0), 2.0)

		# Fade out over the back third; fade in as it clears the stone.
		var alpha: float = smoothstep(0.0, 0.12, phase) * (1.0 - smoothstep(0.62, 1.0, phase))
		if alpha <= 0.01:
			continue
		_paint_glyph(layer, at, spin, int(rune["glyph"]), alpha, flash)


## One glyph: a stack of small bars whose arrangement comes from its seed, so the
## seven runes on screen are visibly different characters rather than one symbol
## repeated. Bars, not curves - a curve at this size is a smudge.
func _paint_glyph(
	layer: Node2D, at: Vector2, spin: float, seed_value: int, alpha: float, flash: float
) -> void:
	var glow: Color = RUNE_GLOW.lerp(RUNE_HOT, flash)
	layer.draw_circle(at, 4.0 + flash * 5.0, Color(glow, 0.14 * alpha + 0.30 * flash))
	# Rotation is applied to the whole glyph, so the bars stay square to each
	# other while it tumbles - a rune is a rigid carving, not a swarm.
	layer.draw_set_transform(at, spin, Vector2.ONE)
	var bits: int = seed_value
	# Vertical stem, always present: it is what makes the shapes read as one
	# alphabet rather than as random confetti.
	layer.draw_rect(Rect2(-0.5, -3.5, 1.0, 7.0), Color(glow, 0.95 * alpha))
	for row: int in 3:
		if bits & (1 << row) == 0:
			continue
		var y: float = -2.6 + float(row) * 2.4
		var wide: bool = bits & (1 << (row + 3)) != 0
		var left: float = -2.6 if wide else -0.5
		var width: float = 5.2 if wide else 3.1
		layer.draw_rect(Rect2(left, y, width, 1.0), Color(glow, 0.9 * alpha))
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
