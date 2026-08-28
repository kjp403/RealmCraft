class_name ElementalTelegraph
extends Node2D
## A ground marker for a big telegraphed boss move, in an ELEMENT's colour with
## real motion in it. The replacement for CastTelegraph on boss casts: that one
## is two flat draw_circle calls in red, which reads the same whether a meteor,
## a laser or an ice age is about to land.
##
## Three things are happening at once, each answering a different question:
##   WHERE  — the filled body + a crisp boundary ring.
##   WHEN   — a converging ring that collapses from the rim onto the centre and
##            arrives exactly at impact, plus a clock wedge. Two independent
##            reads of the same clock, so it stays legible when the body is
##            crowded with players and adds.
##   WHAT   — element tint, a counter-rotating rune ring, and drifting motes
##            (embers rise, frost sinks, sparks jitter). Players learn the
##            colour before they learn the mechanic.
##
## [member mode] flips the meaning: DANGER marks ground to LEAVE, SAFE marks the
## one patch to GET INTO while everything else is hit. SAFE deliberately reads
## cool and calm with the pressure drawn OUTSIDE, so the two never confuse at a
## glance — that inversion is the whole point of the Killing Frost mechanic.
##
## Pure client visual; frees itself. Server-authoritative damage never consults it.

## EARTH is APPENDED, never inserted: the element travels the wire as a raw int
## (see [method HostileNpc.rp_elem_telegraph]) and is stored as one in
## [member EnemyTypeResource.telegraph_element], so renumbering FIRE/FROST/STORM
## would silently recolour every existing boss. Consumers that only know the
## first three clamp into range rather than breaking.
enum Element { FIRE, FROST, STORM, EARTH }
enum Mode { DANGER, SAFE }

## Tints per element: [core fill, rim/detail]. The rim is the brighter read.
const PALETTE: Dictionary = {
	Element.FIRE:  [Color(1.0, 0.35, 0.08), Color(1.0, 0.78, 0.28)],
	Element.FROST: [Color(0.35, 0.72, 1.0), Color(0.78, 0.95, 1.0)],
	Element.STORM: [Color(0.62, 0.36, 1.0), Color(0.85, 0.78, 1.0)],
	# Deep moss core, bright sap rim. Kept clearly YELLOW-green so it cannot be
	# confused with the blue-green SAFE ring below — a danger marker that reads
	# as a safe spot is the worst possible failure for this class.
	Element.EARTH: [Color(0.24, 0.62, 0.16), Color(0.72, 0.95, 0.34)],
}
## SAFE overrides the palette — a safe ring must never be mistaken for a hot one.
const SAFE_FILL: Color = Color(0.45, 0.95, 0.72)
const SAFE_RIM: Color = Color(0.80, 1.0, 0.90)

## Danger radius — match the server's hit test or the marker lies.
var radius: float = 32.0
## Wind-up length; the converging ring lands on the centre at exactly this time.
var duration: float = 1.0
var element: Element = Element.FIRE
var mode: Mode = Mode.DANGER

var _elapsed: float = 0.0
var _spin: float = 0.0


func _ready() -> void:
	z_index = -1 # on the ground, under characters and under the impact VFX
	_spawn_motes()


func _process(delta: float) -> void:
	_elapsed += delta
	# Counter-rotation: the rune ring turns one way, the inner ticks the other.
	# A single spinning ring reads as decoration; opposed motion reads as a
	# mechanism winding down, which is the feeling a wind-up wants.
	_spin += delta * (0.9 if mode == Mode.SAFE else 1.7)
	queue_redraw()
	if _elapsed >= duration:
		queue_free()


func _fill_color() -> Color:
	return SAFE_FILL if mode == Mode.SAFE else PALETTE[element][0]


func _rim_color() -> Color:
	return SAFE_RIM if mode == Mode.SAFE else PALETTE[element][1]


## Drifting motes sell the element before the payload lands. CPUParticles2D (not
## GPU) — the web export has no compute path for GPU particles.
func _spawn_motes() -> void:
	var p: CPUParticles2D = CPUParticles2D.new()
	p.emitting = true
	p.amount = 20
	p.lifetime = maxf(0.45, duration * 0.7)
	p.preprocess = 0.2
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.85
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.2
	match element:
		Element.FIRE:   # embers rise and burn out
			p.gravity = Vector2(0.0, -46.0)
			p.initial_velocity_min = 8.0
			p.initial_velocity_max = 26.0
		Element.FROST:  # flakes settle
			p.gravity = Vector2(0.0, 18.0)
			p.initial_velocity_min = 3.0
			p.initial_velocity_max = 12.0
		Element.STORM:  # sparks scatter fast and erratically
			p.gravity = Vector2.ZERO
			p.initial_velocity_min = 26.0
			p.initial_velocity_max = 70.0
			p.spread = 180.0
			p.lifetime = 0.28
		Element.EARTH:  # grit is THROWN up and falls back — the pillar is
			# tearing the floor open, so the motion has to arc, not drift.
			p.gravity = Vector2(0.0, 92.0)
			p.initial_velocity_min = 34.0
			p.initial_velocity_max = 62.0
			p.spread = 42.0
			p.direction = Vector2.UP
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, Color(_rim_color(), 0.95))
	ramp.set_color(1, Color(_fill_color(), 0.0))
	p.color_ramp = ramp
	add_child(p)


func _draw() -> void:
	var t: float = clampf(_elapsed / duration, 0.0, 1.0)
	var fill: Color = _fill_color()
	var rim: Color = _rim_color()
	# Ease the fill so most of the brightening happens LATE — an early-bright
	# telegraph makes players commit to dodging before the danger is real.
	var heat: float = t * t

	if mode == Mode.SAFE:
		_draw_safe(t, fill)
	else:
		draw_circle(Vector2.ZERO, radius, Color(fill, 0.08 + 0.30 * heat))
	# Boundary: the line players actually stand relative to. Always crisp.
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(rim, 0.55 + 0.45 * heat), 2.0, true)

	_draw_runes(rim, heat)

	# WHEN, read 1: a ring converging on the centre, arriving at impact.
	if t < 1.0:
		var conv: float = radius * (1.0 - t)
		draw_arc(Vector2.ZERO, maxf(conv, 1.0), 0.0, TAU, 48, Color(rim, 0.9), 2.5, true)
	# WHEN, read 2: the clock wedge sweeping to full.
	draw_arc(Vector2.ZERO, radius * 0.82, -PI / 2.0, -PI / 2.0 + TAU * t, 48, Color(rim, 0.75), 3.0)


## SAFE mode draws the PRESSURE outside the ring — a wall closing inward — and
## leaves the interior clean, so "get in" is the obvious read.
func _draw_safe(t: float, fill: Color) -> void:
	draw_circle(Vector2.ZERO, radius, Color(fill, 0.14))
	var wall: float = radius + (radius * 1.5) * (1.0 - t)
	var hazard: Color = PALETTE[element][1]
	for i: int in 3:
		var r: float = wall + float(i) * 7.0
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(hazard, 0.5 - 0.13 * float(i)), 3.0, true)
	# Inward tick marks: short spokes pointing at the safe zone.
	for i: int in 12:
		var a: float = TAU * float(i) / 12.0 + _spin * 0.4
		var dir: Vector2 = Vector2.from_angle(a)
		draw_line(dir * (wall - 2.0), dir * (wall - 12.0), Color(hazard, 0.65), 2.0)


## A dashed rune ring, counter-rotating against the wedge. Drawn as arc segments
## with gaps rather than a solid circle so the rotation is actually visible.
func _draw_runes(rim: Color, heat: float) -> void:
	var rune_r: float = radius * 0.66
	var seg: float = TAU / 16.0
	for i: int in 8:
		var a: float = seg * 2.0 * float(i) - _spin
		draw_arc(Vector2.ZERO, rune_r, a, a + seg, 6, Color(rim, 0.35 + 0.35 * heat), 2.0, true)
