extends CosmeticTrailPreset
## STATIC WAKE. The Storm set's trail: every stride pins a charged bead to the
## floor, and lightning chains from bead to bead back along the path, ending at
## the wearer's feet. When a bead runs out of charge it pops in a small ring.
##
## WHY IT IS NOT [TrailStormPreset]. That trail is one bolt laid along the path -
## a line. This one is a CHAIN: discrete anchors on the tiles, with short arcs
## hopping between them. The anchors are what make it read as a different
## product at a glance, and they are also what give it a shape when the wearer
## stops - the chain stays on the floor and discharges link by link, oldest
## first, instead of vanishing the instant movement ends.
##
## Colour comes from [CosmeticThemes] like the rest of the Storm set, so this,
## the Aether Arcs aura, the Aether Storm title and the Sapphire dye match.
##
##   BEADS   floor glow + hot pip at each stride, fading with charge.
##   CHAIN   jagged arcs bead to bead, re-rolled on a fixed cadence.
##   POP     an expanding ring in the accent as each bead dies.
##   SPARKS  a thin world-space spray while moving.

const THEME: StringName = CosmeticThemes.STORM

## Seconds a bead holds its charge. Long enough that a sprint shows four or five
## links at once, short enough that a standing player's chain is gone in a beat.
const BEAD_LIFE_S: float = 1.4
## The last slice of a bead's life, spent popping.
const POP_S: float = 0.18
## Re-roll cadence for the arcs. Same argument as [TrailStormPreset.RECALC_S]:
## a fixed timer looks the same at every frame rate, per-frame jitter does not.
const RECALC_S: float = 0.06
## Points per link, and how far a link bows sideways.
const LINK_SEGMENTS: int = 5
const LINK_JITTER_PX: float = 5.0
## Links longer than this are not drawn - a teleport or a hard corner cut must
## not throw one bolt across the screen.
const MAX_LINK_PX: float = 48.0
## Shorter than this and there is nothing to arc across (the frame a bead lands
## under the feet, or two beads at a turn).
const MIN_LINK_PX: float = 4.0

## {"p": Vector2 world, "t": float born}. Oldest first.
var _beads: Array[Dictionary] = []
## Bumped every RECALC_S; seeds the jag so a link holds its shape between rolls.
var _roll: int = 0
var _since_roll: float = 0.0
var _sparks: CPUParticles2D
var _layer: VfxDrawLayer


func _build() -> void:
	# One top_level additive layer in world space: beads are left behind on the
	# tiles, so their coordinates must not ride along with the wearer.
	_layer = _add_draw_layer(_paint, true)
	_layer.top_level = true

	var p: CPUParticles2D = _add_world_emitter(8, 0.45, VfxTextures.pip(3))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 5.0
	p.direction = Vector2(0, -1)
	p.spread = 70.0
	p.gravity = Vector2(0, 140.0)
	p.initial_velocity_min = 25.0
	p.initial_velocity_max = 60.0
	p.color_ramp = _fade_ramp(CosmeticThemes.pale(THEME), 1.0)
	p.material = _additive()
	_sparks = p


func _tick(delta: float) -> void:
	super(delta)
	if _sparks != null:
		_sparks.emitting = is_moving()
	var cutoff: float = _elapsed - BEAD_LIFE_S
	while not _beads.is_empty() and float(_beads[0]["t"]) < cutoff:
		_beads.pop_front()
	_since_roll += delta
	if _since_roll >= RECALC_S:
		_since_roll = 0.0
		_roll += 1


func _on_step(world_pos: Vector2, _heading_dir: Vector2) -> void:
	if not _viewer_in_range():
		return
	_beads.append({"p": world_pos, "t": _elapsed})


## Charge left in a bead, 1 at birth to 0 at death.
func _charge(bead: Dictionary) -> float:
	return clampf(1.0 - (_elapsed - float(bead["t"])) / BEAD_LIFE_S, 0.0, 1.0)


func _paint(layer: VfxDrawLayer) -> void:
	var core: Color = CosmeticThemes.core(THEME)
	var pale: Color = CosmeticThemes.pale(THEME)
	var accent: Color = CosmeticThemes.accent(THEME)

	# Links first, so the beads sit on top of the arcs that end in them.
	for i: int in range(1, _beads.size()):
		var a: Dictionary = _beads[i - 1]
		var b: Dictionary = _beads[i]
		# A link is only as live as its weaker end.
		var live: float = minf(_charge(a), _charge(b))
		_link(layer, a["p"], b["p"], live, i, core, pale)
	# The newest link runs from the last bead to the feet, so the chain is
	# visibly attached to whoever is making it.
	if not _beads.is_empty() and is_moving():
		var last: Dictionary = _beads[-1]
		_link(layer, last["p"], global_position, _charge(last), _beads.size(), core, pale)

	for bead: Dictionary in _beads:
		var charge: float = _charge(bead)
		var at: Vector2 = bead["p"]
		var life_left: float = charge * BEAD_LIFE_S
		if life_left < POP_S:
			# Discharge: a ring thrown outward on the floor as the bead dies.
			var k: float = 1.0 - life_left / POP_S
			layer.draw_set_transform(at, 0.0, Vector2(1.0, GROUND_SQUASH))
			layer.draw_arc(Vector2.ZERO, 3.0 + k * 9.0, 0.0, TAU, 20, Color(accent, 0.8 * (1.0 - k)), 1.0)
			layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			continue
		# A flicker per bead, offset by where it sits so neighbours do not pulse
		# in unison.
		var flicker: float = 0.75 + 0.25 * sin(_elapsed * 31.0 + at.x * 0.7)
		layer.draw_set_transform(at, 0.0, Vector2(1.0, GROUND_SQUASH))
		layer.draw_circle(Vector2.ZERO, 7.0, Color(core, 0.35 * charge * flicker))
		layer.draw_circle(Vector2.ZERO, 3.5, Color(accent, 0.7 * charge * flicker))
		layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		layer.draw_circle(at, 1.5, Color(pale, charge))


## One jagged arc between two world points: a wide dim corona and a one-pixel
## hot core down the same spine.
func _link(layer: VfxDrawLayer, from: Vector2, to: Vector2, live: float, index: int, core: Color, pale: Color) -> void:
	var length: float = from.distance_to(to)
	if live <= 0.0 or length > MAX_LINK_PX or length < MIN_LINK_PX:
		return
	# Bow scales with the link: full jitter on a short link throws spikes out
	# sideways far longer than the link itself, which read as a star burst.
	var jitter: float = LINK_JITTER_PX * clampf(length / 20.0, 0.0, 1.0)
	var side: Vector2 = (to - from).orthogonal().normalized()
	var points: PackedVector2Array = PackedVector2Array()
	for s: int in LINK_SEGMENTS + 1:
		var k: float = float(s) / float(LINK_SEGMENTS)
		var bow: float = 0.0
		if s != 0 and s != LINK_SEGMENTS:
			# Deterministic in (link, segment, roll): no RNG, so a render tool
			# captures exactly what plays.
			bow = sin(float(s) * 12.9898 + float(index) * 4.1 + float(_roll) * 78.233) * jitter
		points.append(from.lerp(to, k) + side * bow)
	layer.draw_polyline(points, Color(core, 0.6 * live), 4.0)
	layer.draw_polyline(points, Color(pale, live), 1.5)
