class_name CompanionPreset
extends CosmeticTrailPreset
## Base for COMPANIONS: small living things that follow the wearer around.
##
## What every companion shares is the body plumbing, not the look:
##
##   BODY     one top_level node, [member body], sprung toward a target the
##            subclass chooses each frame. Underdamped, so it lags on a start and
##            overshoots on a hard turn - that overshoot is what reads as alive.
##   STILL    [member still_for] counts seconds the wearer has stood still, so a
##            companion can do something different when they stop (orbit, land).
##   DEPTH    [method set_in_front] swaps the body above or below the wearer, so
##            a companion can pass BEHIND them instead of across their face.
##
## Extends the trail base only for its movement reading (heading, is_moving),
## which is sampled from the transform and so works for remote players too.
##
## Subclasses override [method target_local] and draw into [member body] (add
## VfxDrawLayers to it); nothing else.

var stiffness: float = 110.0
var damping: float = 13.0

## The flying node. Its children inherit its world position and scale.
var body: Node2D
## Seconds the wearer has been standing still (0 while moving).
var still_for: float = 0.0

var _pos: Vector2 = Vector2.ZERO
var _vel: Vector2 = Vector2.ZERO
var _placed: bool = false


func _ready() -> void:
	body = Node2D.new()
	body.name = "Companion"
	body.top_level = true
	add_child(body)
	super()


## Override: where the companion wants to be, in the wearer's local space
## (origin at the feet, +y down), given this frame's delta.
func target_local(_delta: float) -> Vector2:
	return Vector2(0, -34)


## A draw layer riding [member body]. Same contract as [method _add_draw_layer].
func add_body_layer(painter: Callable, additive: bool = false, layer_z: int = 0) -> VfxDrawLayer:
	var layer: VfxDrawLayer = VfxDrawLayer.new()
	layer.painter = painter
	layer.z_index = layer_z
	# Crisp: the pixel-canvas sprites are native-resolution art.
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if additive:
		layer.material = _additive()
	body.add_child(layer)
	_draw_layers.append(layer)
	return layer


## World-space sparkles shed off [member body] as it moves - the Wisp's trail,
## shared. Additive, so give it a bright colour.
func add_motes(tint: Color, amount: int = 10, texture: Texture2D = null, offset: Vector2 = Vector2.ZERO) -> CPUParticles2D:
	var p: CPUParticles2D = CPUParticles2D.new()
	p.amount = amount
	p.lifetime = 0.8
	p.local_coords = false
	p.texture = texture if texture != null else VfxTextures.sparkle(7)
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.position = offset
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 3.0
	p.gravity = Vector2(0, 10.0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 7.0
	p.spread = 180.0
	p.scale_amount_min = 0.45
	p.scale_amount_max = 0.8
	p.color_ramp = _fade_ramp(tint, 0.9)
	p.material = _additive()
	body.add_child(p)
	return p


## Deepest z a companion's own layers reach above [member body] (glow 0, art
## 1, highlights 2). "Behind" has to put ALL of them below the wearer.
const LAYER_Z_SPAN: int = 3


## In front of the wearer's body, or behind it.
##
## BEHIND MUST CLEAR THE WHOLE LAYER STACK, NOT JUST THE BODY NODE. The body is
## top_level, and Godot draws a top_level item ON TOP of everything else at the
## same z. Behind used to be z -1: the art layer at +1 inside it landed on z 0,
## the wearer's own depth, won the tie, and drew over their face - so the Ghost's
## peek-a-boo, the Wisp's far orbit and the Moon's far pass never went behind
## anyone at all.
func set_in_front(front: bool) -> void:
	body.z_index = 2 if front else -(LAYER_Z_SPAN + 1)


# --- Faces -------------------------------------------------------------------
# Shared so every companion's face reads as one family: dark pixel eyes with a
# one-pixel shine, and optional blush. The shine is what makes a two-pixel eye
# read as "cute" rather than as a hole.

const FACE_DARK: Color = Color(0.08, 0.07, 0.14)
const FACE_SHINE: Color = Color(1.0, 1.0, 1.0)
const FACE_BLUSH: Color = Color(1.0, 0.55, 0.70, 0.85)


## Two eyes centred on [param at], [param gap] px either side, nudged by
## [param look] (a direction, at most a pixel). A blink draws closed lines.
func draw_eyes(layer: CanvasItem, at: Vector2, gap: float, look: Vector2, blink: bool, tall: int = 3) -> void:
	for side: float in [-1.0, 1.0]:
		var p: Vector2 = (at + Vector2(side * gap, 0.0) + look.limit_length(1.0)).round()
		if blink:
			layer.draw_rect(Rect2(p.x - 1.0, p.y, 2.0, 1.0), FACE_DARK)
			continue
		layer.draw_rect(Rect2(p.x - 1.0, p.y - 1.0, 2.0, float(tall)), FACE_DARK)
		layer.draw_rect(Rect2(p.x - 1.0, p.y - 1.0, 1.0, 1.0), FACE_SHINE)


func draw_blush(layer: CanvasItem, at: Vector2, gap: float) -> void:
	for side: float in [-1.0, 1.0]:
		layer.draw_rect(Rect2((at.x + side * gap - 1.0), at.y, 2.0, 1.0), FACE_BLUSH)


## True for a short blink every [param period] seconds, offset by [param salt]
## so companions on screen do not blink in unison.
func blinking(period: float = 3.2, salt: float = 0.0) -> bool:
	return fposmod(_elapsed + salt, period) < 0.13


# --- The wearer's body ----------------------------------------------------------

## Render-tool seam, as on [TrailChronoEchoPreset]: a sprite to read instead of
## the wearer's own.
var sprite_source: AnimatedSprite2D

## Texture instance id -> top opaque row (px from the top of the frame).
static var _top_rows: Dictionary = {}


func wearer_sprite() -> AnimatedSprite2D:
	if is_instance_valid(sprite_source):
		return sprite_source
	if wearer == null or not is_instance_valid(wearer):
		return null
	return wearer.animated_sprite


## Local y of the top of the wearer's head (origin at the feet, -y up).
##
## MEASURED, not assumed: skins are different heights, so the top opaque row of
## the frame on screen is read once per texture and cached. A fixed height
## perches a companion inside a tall skin's hat or floating over a short one.
func wearer_head_top() -> float:
	var source: AnimatedSprite2D = wearer_sprite()
	if source == null or source.sprite_frames == null:
		return -26.0
	var tex: Texture2D = source.sprite_frames.get_frame_texture(source.animation, source.frame)
	if tex == null:
		return -26.0
	var h: float = float(tex.get_height())
	var top_of_frame: float = source.offset.y - (h * 0.5 if source.centered else 0.0)
	return top_of_frame + float(_top_row(tex))


static func _top_row(tex: Texture2D) -> int:
	var key: int = tex.get_instance_id()
	if _top_rows.has(key):
		return _top_rows[key]
	var row: int = 0
	var image: Image = tex.get_image()
	if image != null:
		var found: bool = false
		for y: int in image.get_height():
			for x: int in image.get_width():
				if image.get_pixel(x, y).a > 0.5:
					row = y
					found = true
					break
			if found:
				break
	_top_rows[key] = row
	return row


## Snap the body straight to its target, killing its velocity. For companions
## that "poof" to catch up instead of flying the whole way.
func teleport_to_target() -> void:
	_pos = global_position + target_local(0.0) * global_scale
	_vel = Vector2.ZERO


## Current velocity of the body in world px/s, for looks that lean or flap
## harder when moving fast.
func body_velocity() -> Vector2:
	return _vel


func _tick(delta: float) -> void:
	super(delta)
	still_for = 0.0 if is_moving() else still_for + delta
	var s: Vector2 = global_scale
	var target: Vector2 = global_position + target_local(delta) * s
	if not _placed:
		_pos = target
		_placed = true
	var accel: Vector2 = (target - _pos) * stiffness - _vel * damping
	_vel += accel * delta
	_pos += _vel * delta
	body.global_position = _pos
	body.scale = s
