class_name TitleParticles
extends Node2D
## The particle layer for a [SkillMasterTitles] title, parented to the title
## Label and sized to it.
##
## BUDGET IS THE DESIGN CONSTRAINT, not an afterthought. These render over every
## player's head, and a bank or a boss lobby can hold thirty of them at once, so
## every emitter here obeys the same three rules:
##
##   * CPUParticles2D only. GPU particles are not safe on the web export - the
##     same call the combat VFX already make.
##   * amount within [MIN_AMOUNT, MAX_AMOUNT]. Ten to twenty-five is enough for a
##     texture-shaped emitter to read at nameplate size.
##   * lifetime within [MIN_LIFETIME, MAX_LIFETIME]. Short lives keep the count
##     on screen low for a given amount and stop a crowd smearing into fog.
##
## tools/verify_skill_master_titles.gd builds all eleven and asserts every
## emitter against those bounds, because the failure mode is invisible in a
## single-player test and only shows up as frame time in a full town.
##
## Z_INDEX 5, absolute. Nameplate art has to clear the player sprite, foliage and
## anything else drawn at world depth, and z_as_relative is off so the depth does
## not change with whatever the label happens to be parented under.

## Emitter budget. See the class header.
const MIN_AMOUNT: int = 10
const MAX_AMOUNT: int = 25
const MIN_LIFETIME: float = 0.3
const MAX_LIFETIME: float = 1.2

## Above the player sprite and world props.
const NAMEPLATE_Z: int = 5

## HIGH PRIEST ray length, as a fraction of what it used to be.
const RAY_SCALE: float = 0.4

## Nameplate label sizes are known only after layout, so the emitters are built
## against this and rescaled by [method fit_to]. Half-width, half-height.
const REF_EXTENT: Vector2 = Vector2(46.0, 9.0)

var fx: int = 0
## Half-size of the label this decorates, in label space.
var _extent: Vector2 = REF_EXTENT


## Ray fan for HIGH PRIEST, or null for every other title.
var _rays: VfxDrawLayer


var _built: bool = false


func _ready() -> void:
	build()


## Construct the emitter set. Idempotent, and callable WITHOUT the node being in
## a tree — a node added during a tool's _initialize() does not get _ready until
## the tree ticks, so tools/verify_skill_master_titles.gd would otherwise be
## measuring eleven empty nodes and reporting them as fine.
func build() -> void:
	if _built:
		return
	_built = true
	z_as_relative = false
	z_index = NAMEPLATE_Z
	_build()
	# Only one title draws anything per frame; the other ten are pure emitters
	# and must not pay for a _process call over every head in a busy town.
	set_process(_rays != null)


## Resize to the label this hangs off. Called after the label has laid out, and
## again whenever the text changes - a title is only a few words, but "Deep Sea
## Legend" is twice the width of "High Priest" and an emitter sized for one looks
## wrong on the other.
func fit_to(label_size: Vector2) -> void:
	if label_size.x <= 1.0:
		return
	_extent = label_size * 0.5
	for child: Node in get_children():
		var p: CPUParticles2D = child as CPUParticles2D
		if p == null:
			continue
		var mode: int = int(p.get_meta(&"span_mode", 0))
		_apply_span(p, mode)


## Emitter defaults shared by every title, with the budget clamped rather than
## trusted. Clamping here (and asserting in the verifier) means a future title
## cannot quietly cost ten times what the others do.
func _emitter(amount: int, lifetime: float, texture: Texture2D, span_mode: int) -> CPUParticles2D:
	var p: CPUParticles2D = CPUParticles2D.new()
	p.amount = clampi(amount, MIN_AMOUNT, MAX_AMOUNT)
	p.lifetime = clampf(lifetime, MIN_LIFETIME, MAX_LIFETIME)
	p.texture = texture
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
			# Corner glints: an emission rect cannot be a ring, so the two ends
			# are approximated by a wide, very flat box - particles land mostly at
			# the extremes because that is where most of its area is once the
			# middle is covered by the glyphs anyway.
			p.emission_rect_extents = Vector2(_extent.x * 1.08, _extent.y * 0.9)
			p.position = Vector2.ZERO
		_:
			p.emission_rect_extents = _extent
			p.position = Vector2.ZERO


func _fade(tint: Color, peak: float = 1.0) -> Gradient:
	var g: Gradient = Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	g.colors = PackedColorArray([Color(tint, 0.0), Color(tint, peak), Color(tint, 0.0)])
	return g


func _additive() -> CanvasItemMaterial:
	var m: CanvasItemMaterial = CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


func _build() -> void:
	match fx:
		0: _mining()
		1: _smithing()
		2: _fishing()
		3: _cooking()
		4: _crafting()
		5: _woodcutting()
		6: _farming()
		7: _fletching()
		8: _herblore()
		9: _slayer()
		_: _prayer()


## MASTER MINER - rock chips spalling outward, plus diamond glints at the corners.
func _mining() -> void:
	var chips: CPUParticles2D = _emitter(12, 0.7, VfxTextures.pip(6), 0)
	chips.explosiveness = 0.85 # spall in bursts, not a steady dribble
	chips.direction = Vector2(0, -1)
	chips.spread = 180.0
	chips.gravity = Vector2(0, 210.0)
	chips.initial_velocity_min = 22.0
	chips.initial_velocity_max = 58.0
	chips.scale_amount_min = 0.5
	chips.scale_amount_max = 1.0
	chips.color_ramp = _fade(Color(0.62, 0.57, 0.50), 0.95)

	var glints: CPUParticles2D = _emitter(10, 0.9, VfxTextures.sparkle(9), 3)
	glints.gravity = Vector2.ZERO
	glints.initial_velocity_min = 0.0
	glints.initial_velocity_max = 4.0
	glints.scale_amount_min = 0.4
	glints.scale_amount_max = 0.9
	glints.color_ramp = _fade(Color(1.0, 0.92, 0.62))
	glints.material = _additive()


## FORGE MASTER - heavy sparks showering DOWN off the base of the letters.
func _smithing() -> void:
	var sparks: CPUParticles2D = _emitter(18, 0.8, VfxTextures.dot(6), 2)
	sparks.direction = Vector2(0, 1)
	sparks.spread = 32.0
	sparks.gravity = Vector2(0, 320.0) # heavy: anvil sparks fall, they do not drift
	sparks.initial_velocity_min = 12.0
	sparks.initial_velocity_max = 42.0
	sparks.scale_amount_min = 0.3
	sparks.scale_amount_max = 0.8
	var cooling: Curve = Curve.new()
	cooling.add_point(Vector2(0.0, 1.0))
	cooling.add_point(Vector2(1.0, 0.2))
	sparks.scale_amount_curve = cooling
	var ramp: Gradient = Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	ramp.colors = PackedColorArray([
		Color(1.0, 0.95, 0.75, 0.0), Color(1.0, 0.72, 0.20, 1.0), Color(0.8, 0.18, 0.02, 0.0),
	])
	sparks.color_ramp = ramp
	sparks.material = _additive()


## DEEP SEA LEGEND - bubbles rising and popping, ripples along the base.
func _fishing() -> void:
	var bubbles: CPUParticles2D = _emitter(14, 1.2, VfxTextures.pip(6), 0)
	bubbles.direction = Vector2(0, -1)
	bubbles.spread = 14.0
	bubbles.gravity = Vector2(0, -34.0)
	bubbles.initial_velocity_min = 8.0
	bubbles.initial_velocity_max = 20.0
	bubbles.scale_amount_min = 0.3
	bubbles.scale_amount_max = 0.8
	# Swell on the way up then vanish - a bubble pops, it does not shrink away.
	var swell: Curve = Curve.new()
	swell.add_point(Vector2(0.0, 0.6))
	swell.add_point(Vector2(0.85, 1.0))
	swell.add_point(Vector2(1.0, 1.25))
	bubbles.scale_amount_curve = swell
	bubbles.color_ramp = _fade(Color(0.70, 0.96, 1.0), 0.8)

	var ripples: CPUParticles2D = _emitter(10, 1.0, VfxTextures.dot(8), 2)
	ripples.gravity = Vector2.ZERO
	ripples.initial_velocity_min = 2.0
	ripples.initial_velocity_max = 8.0
	ripples.spread = 180.0
	ripples.scale_amount_min = 0.5
	ripples.scale_amount_max = 1.4
	ripples.color_ramp = _fade(Color(0.35, 0.80, 1.0), 0.35)


## CULINARY KING - steam off the top edge, with a few embers in it.
func _cooking() -> void:
	var steam: CPUParticles2D = _emitter(12, 1.2, VfxTextures.puff(16), 1)
	steam.direction = Vector2(0, -1)
	steam.spread = 20.0
	steam.gravity = Vector2(0, -22.0)
	steam.initial_velocity_min = 6.0
	steam.initial_velocity_max = 16.0
	steam.scale_amount_min = 0.5
	steam.scale_amount_max = 1.2
	var grow: Curve = Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 1.3))
	steam.scale_amount_curve = grow
	steam.color_ramp = _fade(Color(1.0, 1.0, 1.0), 0.22) # low opacity: steam, not smoke

	var embers: CPUParticles2D = _emitter(10, 1.0, VfxTextures.dot(6), 1)
	embers.direction = Vector2(0, -1)
	embers.spread = 40.0
	embers.gravity = Vector2(0, -30.0)
	embers.initial_velocity_min = 8.0
	embers.initial_velocity_max = 22.0
	embers.scale_amount_min = 0.25
	embers.scale_amount_max = 0.6
	embers.color_ramp = _fade(Color(1.0, 0.62, 0.20), 0.85)
	embers.material = _additive()


## GRAND ARTISAN - gem glints in three colours flashing along the letter edges.
##
## One emitter with a THREE-STOP ramp rather than three emitters: a particle
## samples the ramp over its life, so a single glint flashes ruby, then sapphire,
## then emerald as it fades. Three emitters would have cost three times the budget
## for a worse result - each glint stuck on one colour.
func _crafting() -> void:
	var gems: CPUParticles2D = _emitter(16, 0.9, VfxTextures.sparkle(9), 3)
	gems.gravity = Vector2.ZERO
	gems.initial_velocity_min = 0.0
	gems.initial_velocity_max = 6.0
	gems.spread = 180.0
	gems.scale_amount_min = 0.35
	gems.scale_amount_max = 0.85
	var ramp: Gradient = Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.5, 0.8, 1.0])
	ramp.colors = PackedColorArray([
		Color(1.0, 0.25, 0.35, 0.0),
		Color(1.0, 0.25, 0.35, 1.0), # ruby
		Color(0.35, 0.55, 1.0, 1.0), # sapphire
		Color(0.35, 1.0, 0.55, 1.0), # emerald
		Color(1.0, 1.0, 1.0, 0.0),
	])
	gems.color_ramp = ramp
	gems.material = _additive()


## TIMBER LORD - leaves drifting down across the width, rotating as they fall.
func _woodcutting() -> void:
	var leaves: CPUParticles2D = _emitter(12, 1.2, VfxTextures.leaf(9), 1)
	leaves.direction = Vector2(0, 1)
	leaves.spread = 25.0
	leaves.gravity = Vector2(0, 26.0) # gentle: a leaf falls slowly
	leaves.initial_velocity_min = 4.0
	leaves.initial_velocity_max = 14.0
	leaves.scale_amount_min = 0.5
	leaves.scale_amount_max = 1.0
	leaves.angular_velocity_min = -140.0
	leaves.angular_velocity_max = 140.0
	leaves.color_ramp = _fade(Color(0.42, 0.82, 0.35), 0.9)


## ARCH-BOTANIST - pollen rising, blossoms popping at the ends.
func _farming() -> void:
	var pollen: CPUParticles2D = _emitter(14, 1.2, VfxTextures.dot(6), 0)
	pollen.direction = Vector2(0, -1)
	pollen.spread = 35.0
	pollen.gravity = Vector2(0, -14.0)
	pollen.initial_velocity_min = 3.0
	pollen.initial_velocity_max = 12.0
	pollen.scale_amount_min = 0.25
	pollen.scale_amount_max = 0.6
	pollen.color_ramp = _fade(Color(1.0, 0.92, 0.45), 0.8)
	pollen.material = _additive()

	var blossoms: CPUParticles2D = _emitter(10, 1.0, VfxTextures.sparkle(9), 3)
	blossoms.explosiveness = 1.0 # a repeating POP rather than a steady sprinkle
	blossoms.gravity = Vector2(0, -20.0)
	blossoms.spread = 180.0
	blossoms.initial_velocity_min = 6.0
	blossoms.initial_velocity_max = 20.0
	blossoms.scale_amount_min = 0.4
	blossoms.scale_amount_max = 0.9
	blossoms.color_ramp = _fade(Color(1.0, 0.72, 0.88), 0.9)


## MASTER FLETCHER - horizontal wind streaks, plus slow drifting down.
func _fletching() -> void:
	# The streak read comes from SPEED and a short life, not from a stretched
	# sprite: CPUParticles2D scales uniformly, so there is no way to elongate a
	# particle along its travel. Fast enough and brief enough, the eye supplies
	# the motion blur itself.
	var wind: CPUParticles2D = _emitter(10, 0.5, VfxTextures.dot(8), 0)
	wind.direction = Vector2(1, 0)
	wind.spread = 4.0 # dead flat: a wind streak has no vertical component
	wind.gravity = Vector2.ZERO
	wind.initial_velocity_min = 90.0
	wind.initial_velocity_max = 165.0
	wind.scale_amount_min = 0.4
	wind.scale_amount_max = 0.9
	wind.color_ramp = _fade(Color(1.0, 0.95, 0.95), 0.55)
	wind.material = _additive()

	var down: CPUParticles2D = _emitter(10, 1.2, VfxTextures.leaf(9), 0)
	down.direction = Vector2(0, 1)
	down.spread = 60.0
	down.gravity = Vector2(0, 10.0)
	down.initial_velocity_min = 2.0
	down.initial_velocity_max = 9.0
	down.scale_amount_min = 0.3
	down.scale_amount_max = 0.7
	down.angular_velocity_min = -70.0
	down.angular_velocity_max = 70.0
	down.color_ramp = _fade(Color(1.0, 0.94, 0.94), 0.7)


## GRAND ALCHEMIST - green chemical steam and popping droplets.
func _herblore() -> void:
	var fumes: CPUParticles2D = _emitter(12, 1.2, VfxTextures.puff(16), 1)
	fumes.direction = Vector2(0, -1)
	fumes.spread = 28.0
	fumes.gravity = Vector2(0, -26.0)
	fumes.initial_velocity_min = 7.0
	fumes.initial_velocity_max = 20.0
	fumes.scale_amount_min = 0.5
	fumes.scale_amount_max = 1.1
	fumes.color_ramp = _fade(Color(0.45, 1.0, 0.38), 0.35)
	fumes.material = _additive()

	var drops: CPUParticles2D = _emitter(10, 0.7, VfxTextures.droplet(8), 0)
	drops.explosiveness = 0.9
	drops.direction = Vector2(0, -1)
	drops.spread = 70.0
	drops.gravity = Vector2(0, 150.0)
	drops.initial_velocity_min = 14.0
	drops.initial_velocity_max = 40.0
	drops.scale_amount_min = 0.3
	drops.scale_amount_max = 0.7
	drops.color_ramp = _fade(Color(0.72, 0.45, 1.0), 0.9)


## SLAYER MASTER - shadow smoke pooling under the title, red souls rising.
func _slayer() -> void:
	var smoke: CPUParticles2D = _emitter(12, 1.2, VfxTextures.puff(16), 2)
	smoke.direction = Vector2(0, 1)
	smoke.spread = 70.0
	smoke.gravity = Vector2(0, 8.0) # sinks and pools rather than rising
	smoke.initial_velocity_min = 3.0
	smoke.initial_velocity_max = 12.0
	smoke.scale_amount_min = 0.7
	smoke.scale_amount_max = 1.5
	# NOT additive. Additive black is invisible - this one has to darken.
	smoke.color_ramp = _fade(Color(0.05, 0.03, 0.06), 0.55)

	var souls: CPUParticles2D = _emitter(10, 1.1, VfxTextures.dot(6), 2)
	souls.direction = Vector2(0, -1)
	souls.spread = 22.0
	souls.gravity = Vector2(0, -40.0)
	souls.initial_velocity_min = 10.0
	souls.initial_velocity_max = 26.0
	souls.scale_amount_min = 0.25
	souls.scale_amount_max = 0.6
	souls.color_ramp = _fade(Color(0.95, 0.18, 0.14), 0.85)
	souls.material = _additive()

	# Blood running off the base of the letters. Emitted from the bottom edge
	# (span mode 2) and thrown DOWN with real weight, so it falls away beneath the
	# text instead of hanging level with it - the drip has to read as leaving the
	# glyphs, which is what separates it from the smoke pooling in the same place.
	var drips: CPUParticles2D = _emitter(10, 0.9, VfxTextures.droplet(8), 2)
	drips.direction = Vector2(0, 1)
	drips.spread = 12.0
	drips.gravity = Vector2(0, 260.0)
	drips.initial_velocity_min = 6.0
	drips.initial_velocity_max = 18.0
	drips.scale_amount_min = 0.3
	drips.scale_amount_max = 0.7
	drips.color_ramp = _fade(Color(0.545, 0.0, 0.0), 0.95)


## HIGH PRIEST - light specks ascending, over a fan of rays drawn behind.
func _prayer() -> void:
	# 0.3 s, and slow: lifetime is what actually bounds a rising particle. At the
	# old 1.2 s these climbed clear of the nameplate and read as a separate effect
	# floating above the player rather than as part of the title.
	var specks: CPUParticles2D = _emitter(14, 0.3, VfxTextures.sparkle(9), 0)
	specks.direction = Vector2(0, -1)
	specks.spread = 18.0
	specks.gravity = Vector2(0, -12.0)
	specks.initial_velocity_min = 3.0
	specks.initial_velocity_max = 9.0
	specks.scale_amount_min = 0.3
	specks.scale_amount_max = 0.75
	specks.color_ramp = _fade(Color(1.0, 0.95, 0.72), 0.95)
	specks.material = _additive()

	# The rays sit BEHIND the glyphs but still above the world, so they get their
	# own layer one step under the nameplate depth rather than being drawn by this
	# node (which is above the label, where they would wash the text out).
	#
	# VfxDrawLayer exists for exactly this - a child canvas item with its own
	# blend mode that calls back to paint.
	_rays = VfxDrawLayer.new()
	_rays.painter = _paint_rays
	_rays.z_as_relative = false
	_rays.z_index = NAMEPLATE_Z - 1
	_rays.material = _additive()
	add_child(_rays)


func _process(_delta: float) -> void:
	if _rays != null:
		_rays.queue_redraw()


## HIGH PRIEST's rays. Drawn rather than particled because a ray is a long
## triangle anchored at one point - a particle system can only place sprites, and
## a fan of sprites reads as a row of streaks, not as light from a single source.
func _paint_rays(layer: Node2D) -> void:
	var t: float = Time.get_ticks_msec() * 0.001
	for i: int in 7:
		var k: float = float(i) / 6.0
		var angle: float = lerpf(-2.5, -0.65, k) + sin(t * 0.5) * 0.05
		# Scaled to 40% of the old length and then capped at the half-height, so
		# the fan is strictly bounded by the title's own line rather than spraying
		# out to the label's full width.
		var reach: float = minf(
			_extent.x * (0.75 + 0.35 * sin(t * 0.9 + k * 3.0)) * RAY_SCALE, _extent.y
		)
		var half: float = 0.09
		var tip_a: Vector2 = Vector2.from_angle(angle - half) * reach
		var tip_b: Vector2 = Vector2.from_angle(angle + half) * reach
		var alpha: float = 0.10 + 0.06 * sin(t * 1.6 + k * 2.2)
		layer.draw_colored_polygon(
			PackedVector2Array([Vector2.ZERO, tip_a, tip_b]),
			Color(1.0, 0.92, 0.62, alpha)
		)
