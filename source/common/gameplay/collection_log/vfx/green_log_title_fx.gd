class_name GreenLogTitleFx
extends Node2D
## Nameplate particle layer for a green-log title, parented to the title Label
## and sized to it. One scene per boss; the palette and emitter shape come from
## the exports below, so a new boss's VFX is a .tscn with different values rather
## than a new script.
##
## BUDGET IS THE DESIGN CONSTRAINT, and these obey the same three rules as
## [TitleParticles] because they render in the same place, over the same crowds:
##
##   * CPUParticles2D only. GPU particles are not safe on the web export.
##   * amount within [MIN_AMOUNT, MAX_AMOUNT].
##   * lifetime within [MIN_LIFETIME, MAX_LIFETIME].
##
## Both are clamped in [method _emitter] rather than trusted, so a future boss
## cannot quietly cost ten times what the others do. The failure mode is
## invisible when you test one title alone and only shows up as frame time in a
## full boss lobby.
##
## Z_INDEX 5, absolute. Nameplate art has to clear the player sprite, foliage and
## anything else drawn at world depth, and z_as_relative is off so the depth does
## not change with whatever the label happens to be parented under.

## Emitter budget. Matched to TitleParticles deliberately — these sit alongside
## mastery titles over the same heads, so they answer to the same ceiling.
const MIN_AMOUNT: int = 10
const MAX_AMOUNT: int = 25
const MIN_LIFETIME: float = 0.3
const MAX_LIFETIME: float = 1.2

## Above the player sprite and world props.
const NAMEPLATE_Z: int = 5

## Label sizes are known only after layout, so emitters are built against this
## and rescaled by [method fit_to]. Half-width, half-height.
const REF_EXTENT: Vector2 = Vector2(46.0, 9.0)

## Emitter silhouette. Each is a different read at nameplate size, which matters
## more than colour: three orange titles with the same shape look like one title.
enum Shape {
	EMBER, ## motes rising off the top edge, cooling as they climb
	MOTE, ## heavy specks sinking off the bottom edge
	GLINT, ## still sparkles at the two ends of the label
}

## Which silhouette this title uses.
@export var shape: Shape = Shape.EMBER
## Core colour of the drifting layer.
@export var primary_tint: Color = Color(1.0, 0.55, 0.2)
## Colour of the accent glint layer. Read against a dark chat backdrop, not only
## against the label.
@export var accent_tint: Color = Color(1.0, 0.9, 0.6)
## Drifting-layer particle count, before the budget clamp.
@export var primary_amount: int = 14
## Accent-layer particle count, before the budget clamp.
@export var accent_amount: int = 10

## Half-size of the label this decorates, in label space.
var _extent: Vector2 = REF_EXTENT
var _built: bool = false


func _ready() -> void:
	build()


## Construct the emitter set. Idempotent, and callable WITHOUT the node being in
## a tree — a node added during a tool's _initialize() does not get _ready until
## the tree ticks, so a verifier would otherwise be measuring empty nodes and
## reporting them as fine.
func build() -> void:
	if _built:
		return
	_built = true
	z_as_relative = false
	z_index = NAMEPLATE_Z
	match shape:
		Shape.MOTE:
			_build_mote()
		Shape.GLINT:
			_build_glint()
		_:
			_build_ember()
	# Pure emitters: nothing here draws per frame, so none of these should cost a
	# _process call over every head in a busy town.
	set_process(false)


## Resize to the label this hangs off. Called after the label has laid out, and
## again whenever the text changes — a title is only a few words, but "Sovereign
## of the Standing Water" is twice the width of "Unbanked Coal", and an emitter
## sized for one looks wrong on the other.
func fit_to(label_size: Vector2) -> void:
	if label_size.x <= 1.0:
		return
	_extent = label_size * 0.5
	for child: Node in get_children():
		var p: CPUParticles2D = child as CPUParticles2D
		if p == null:
			continue
		_apply_span(p, int(p.get_meta(&"span_mode", 0)))


# --- Shapes ------------------------------------------------------------------

## Motes lifting off the TOP edge and cooling as they climb. For fire/forge
## titles, where the label should look like it is still giving off heat.
func _build_ember() -> void:
	var embers: CPUParticles2D = _emitter(primary_amount, 1.0, VfxTextures.dot(6), 1)
	embers.direction = Vector2(0, -1)
	embers.spread = 24.0
	embers.gravity = Vector2(0, -46.0) # rises: hot air, not falling sparks
	embers.initial_velocity_min = 8.0
	embers.initial_velocity_max = 26.0
	embers.scale_amount_min = 0.35
	embers.scale_amount_max = 0.85
	# The scale curve and the alpha ramp are deliberately in step. A layer whose
	# size curve peaks where its ramp is transparent is smallest exactly when it
	# is most visible, and reads on screen as a missing effect rather than a
	# subtle one — both peak around 0.25 here.
	embers.scale_amount_curve = _rise_and_shrink()
	embers.color_ramp = _fade(primary_tint, 0.95)
	embers.material = _additive()

	var sparks: CPUParticles2D = _emitter(accent_amount, 0.5, VfxTextures.sparkle(9), 3)
	sparks.gravity = Vector2.ZERO
	sparks.initial_velocity_min = 0.0
	sparks.initial_velocity_max = 6.0
	sparks.scale_amount_min = 0.3
	sparks.scale_amount_max = 0.7
	sparks.color_ramp = _fade(accent_tint)
	sparks.material = _additive()


## Heavy specks sinking off the BOTTOM edge. For rot/decay titles — the label
## should look like it is shedding, not radiating.
func _build_mote() -> void:
	var motes: CPUParticles2D = _emitter(primary_amount, 1.1, VfxTextures.pip(6), 2)
	motes.direction = Vector2(0, 1)
	motes.spread = 46.0
	motes.gravity = Vector2(0, 58.0) # slow sink: silt in water, not sparks
	motes.initial_velocity_min = 4.0
	motes.initial_velocity_max = 16.0
	motes.scale_amount_min = 0.4
	motes.scale_amount_max = 0.9
	motes.scale_amount_curve = _rise_and_shrink()
	motes.color_ramp = _fade(primary_tint, 0.9)

	var bubbles: CPUParticles2D = _emitter(accent_amount, 0.9, VfxTextures.dot(6), 0)
	bubbles.direction = Vector2(0, -1)
	bubbles.spread = 12.0
	bubbles.gravity = Vector2(0, -22.0)
	bubbles.initial_velocity_min = 3.0
	bubbles.initial_velocity_max = 11.0
	bubbles.scale_amount_min = 0.25
	bubbles.scale_amount_max = 0.55
	bubbles.color_ramp = _fade(accent_tint, 0.7)
	bubbles.material = _additive()


## Still sparkles at the two ENDS of the label, with a slow shimmer across the
## whole box. For sun/gold titles, where movement should read as gleam, not smoke.
func _build_glint() -> void:
	var glints: CPUParticles2D = _emitter(primary_amount, 0.8, VfxTextures.sparkle(9), 3)
	glints.gravity = Vector2.ZERO
	glints.initial_velocity_min = 0.0
	glints.initial_velocity_max = 4.0
	glints.scale_amount_min = 0.4
	glints.scale_amount_max = 1.0
	glints.scale_amount_curve = _rise_and_shrink()
	glints.color_ramp = _fade(primary_tint)
	glints.material = _additive()

	var dust: CPUParticles2D = _emitter(accent_amount, 1.2, VfxTextures.diamond(7), 0)
	dust.direction = Vector2(1, 0) # drifts across the label like blown sand
	dust.spread = 18.0
	dust.gravity = Vector2(0, 8.0)
	dust.initial_velocity_min = 5.0
	dust.initial_velocity_max = 15.0
	dust.scale_amount_min = 0.2
	dust.scale_amount_max = 0.5
	dust.color_ramp = _fade(accent_tint, 0.6)
	dust.material = _additive()


# --- Emitter plumbing --------------------------------------------------------

## Emitter defaults shared by every green-log title, with the budget clamped
## rather than trusted.
func _emitter(amount: int, lifetime: float, texture: Texture2D, span_mode: int) -> CPUParticles2D:
	var p: CPUParticles2D = CPUParticles2D.new()
	p.amount = clampi(amount, MIN_AMOUNT, MAX_AMOUNT)
	p.lifetime = clampf(lifetime, MIN_LIFETIME, MAX_LIFETIME)
	p.texture = texture
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # pixel art: no smoothing
	p.emitting = true
	p.set_meta(&"span_mode", span_mode)
	add_child(p)
	_apply_span(p, span_mode)
	return p


## Where along the label an emitter draws from.
## 0 = the whole box, 1 = the top edge, 2 = the bottom edge, 3 = the two ends.
func _apply_span(p: CPUParticles2D, mode: int) -> void:
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	match mode:
		1:
			p.emission_rect_extents = Vector2(_extent.x, 1.0)
			p.position = Vector2(0.0, -_extent.y)
		2:
			p.emission_rect_extents = Vector2(_extent.x, 1.0)
			p.position = Vector2(0.0, _extent.y)
		3:
			# Corner glints: an emission rect cannot be a ring, so the two ends are
			# approximated by a wide, very flat box — particles land mostly at the
			# extremes because that is where most of its area is once the middle is
			# covered by the glyphs anyway.
			p.emission_rect_extents = Vector2(_extent.x * 1.08, _extent.y * 0.9)
			p.position = Vector2.ZERO
		_:
			p.emission_rect_extents = _extent
			p.position = Vector2.ZERO


## Fade in fast, hold, fade out. Peak alpha lands at 0.25 of life.
func _fade(tint: Color, peak: float = 1.0) -> Gradient:
	var g: Gradient = Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	g.colors = PackedColorArray([Color(tint, 0.0), Color(tint, peak), Color(tint, 0.0)])
	return g


## Size curve peaking at 0.25 — the same point [method _fade] peaks — so a
## particle is largest exactly when it is most opaque.
func _rise_and_shrink() -> Curve:
	var c: Curve = Curve.new()
	c.add_point(Vector2(0.0, 0.35))
	c.add_point(Vector2(0.25, 1.0))
	c.add_point(Vector2(1.0, 0.15))
	return c


func _additive() -> CanvasItemMaterial:
	var m: CanvasItemMaterial = CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m
