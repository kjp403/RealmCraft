class_name VipParticleLayer
extends Resource
## One emitter in a [VipTierProfile]'s stack, as tunable data rather than code.
##
## The eleven mastery titles build their emitters in GDScript ([TitleParticles]),
## which is right for them - each is a one-off with its own hand-drawn curve and
## no two share a shape. The four VIP donation tiers are the opposite case: they
## are a LADDER, they get retuned together whenever the ladder is repriced, and
## the thing being tuned is always the same short list of numbers. Holding that
## list in a resource means a tier can be re-balanced in the inspector, and means
## the four .tres profiles are the single place a palette lives.
##
## What is NOT here is the emitter's shape logic. `shape` picks one of the shared
## [VfxTextures] masks and nothing else - there is no room in this schema for a
## bespoke draw pass, and there should not be, because the moment a tier needs one
## it belongs in code next to the mastery looks.

## Which shared [VfxTextures] mask this layer emits. White masks, tinted by the
## ramp below, so one shape serves every tier.
enum Shape { DOT, PIP, SPARKLE, DIAMOND, DROPLET, LEAF, PUFF, SHARD }

## Where along the title this layer emits from. Mirrors [TitleParticles]'s span
## modes, which the nameplate layout is already tuned against.
## BOX = the whole label, TOP / BOTTOM = one edge, ENDS = biased to the two ends.
enum Span { BOX, TOP, BOTTOM, ENDS }

## For the verifier's failure messages. Never shown to a player.
@export var id: StringName = &""

@export_group("Shape")
@export var shape: Shape = Shape.DOT
## Mask resolution in pixels. These are drawn at nameplate scale; above ~16 the
## extra pixels are invisible and only cost VRAM.
@export_range(3, 24, 1) var shape_px: int = 8
@export var span: Span = Span.BOX
## Grow the emission box past the label by this factor. 1.0 emits strictly within
## the text; above that the layer drifts around it.
##
## THIS IS THE AURA DIAL, and it is the one number in this file with a rule
## attached rather than a taste. Titles in this game are text VFX and explicitly
## never character auras - a field wide enough to wrap the player is a different
## product decision, made by someone else. [VipTitleEffect] clamps this to
## [constant VipTitleEffect.MAX_SPAN_SCALE] and the verifier fails a profile that
## asks for more, so the rule cannot erode one retune at a time.
@export_range(1.0, 2.0, 0.05) var span_scale: float = 1.0

@export_group("Budget")
## Particles alive at once. Clamped to [VipTitleEffect]'s budget when built - the
## clamp is the guarantee, this is the request.
@export_range(1, 40, 1) var amount: int = 12
## Seconds. Short lives are what keep the on-screen count low for a given amount
## and stop a crowd of titles smearing into fog.
@export_range(0.1, 3.0, 0.05) var lifetime: float = 0.9
@export_range(0.0, 1.0, 0.01) var explosiveness: float = 0.0
## Dropped entirely at medium LOD. Flag the layer a tier reads fine without -
## the ambient dust, the second smoke bank - never its signature layer.
@export var detail: bool = false

@export_group("Motion")
@export var direction: Vector2 = Vector2(0.0, -1.0)
@export_range(0.0, 180.0, 1.0) var spread: float = 30.0
@export var gravity: Vector2 = Vector2.ZERO
@export var velocity_min: float = 0.0
@export var velocity_max: float = 20.0
@export_range(0.0, 100.0, 0.5) var damping: float = 0.0
## Degrees per second, applied as a symmetric +/- range so a layer of leaves or
## shards does not all spin the same way.
@export_range(0.0, 360.0, 1.0) var angular_velocity: float = 0.0

@export_group("Size")
@export var scale_min: float = 0.3
@export var scale_max: float = 0.8
## Size over life, start -> end. Left equal, no curve is built at all: a Curve is
## a resource per emitter and there is no reason to pay for a flat one.
@export var scale_start: float = 1.0
@export var scale_end: float = 1.0

@export_group("Colour")
## Three-stop ramp a particle walks as it lives. Entering and leaving are always
## fully transparent - a VIP layer that pops in or cuts out reads as a bug, not
## as an accolade - so only the middle stop carries [member peak_alpha].
@export var color_in: Color = Color(1.0, 1.0, 1.0)
@export var color_mid: Color = Color(1.0, 1.0, 1.0)
@export var color_out: Color = Color(1.0, 1.0, 1.0)
## Optional FOURTH ramp stop, for a layer that has to walk through more than one
## colour on its way out. Diamond's dust uses it to fade white -> cyan -> magenta,
## so a field of specks at mixed ages shows mixed colour - dispersion, spread over
## the particles instead of over one particle's life.
##
## Position in the particle's life, 0 disables it. Must sit after the peak (0.28)
## and before the end, or it is ignored: a stop out of order does not error, the
## Gradient just resorts it and the ramp quietly stops meaning what it says.
@export_range(0.0, 0.95, 0.01) var late_stop: float = 0.0
@export var color_late: Color = Color(1.0, 1.0, 1.0)
@export_range(0.0, 1.0, 0.01) var peak_alpha: float = 0.9
## Additive blending. TRUE for anything that is light - glints, embers, sparks.
## FALSE for anything that must DARKEN, which is the trap: additive black is
## invisible, so a smoke or fog layer set additive renders as nothing at all.
@export var additive: bool = true


## The shared mask for this layer. Cached inside [VfxTextures] per shape+size, so
## every wearer on screen shares one upload.
func texture() -> Texture2D:
	match shape:
		Shape.PIP: return VfxTextures.pip(shape_px)
		Shape.SPARKLE: return VfxTextures.sparkle(shape_px)
		Shape.DIAMOND: return VfxTextures.diamond(shape_px)
		Shape.DROPLET: return VfxTextures.droplet(shape_px)
		Shape.LEAF: return VfxTextures.leaf(shape_px)
		Shape.PUFF: return VfxTextures.puff(shape_px)
		Shape.SHARD: return VfxTextures.shard(shape_px)
		_: return VfxTextures.dot(shape_px)


## The ramp described by the three colour stops. Built per emitter because a
## Gradient is mutable and sharing one across emitters means a future tweak in
## one place silently moves every layer that borrowed it.
func ramp() -> Gradient:
	var g: Gradient = Gradient.new()
	if late_stop > 0.28 and late_stop < 1.0:
		g.offsets = PackedFloat32Array([0.0, 0.28, late_stop, 1.0])
		g.colors = PackedColorArray([
			Color(color_in, 0.0),
			Color(color_mid, peak_alpha),
			Color(color_late, peak_alpha * 0.8),
			Color(color_out, 0.0),
		])
		return g
	g.offsets = PackedFloat32Array([0.0, 0.28, 1.0])
	g.colors = PackedColorArray([
		Color(color_in, 0.0),
		Color(color_mid, peak_alpha),
		Color(color_out, 0.0),
	])
	return g
