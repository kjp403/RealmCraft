extends CosmeticTrailPreset
## SHADOW TWIN. A living silhouette of the wearer that follows a fraction of a
## second behind, replaying their exact run cycle along their exact path - every
## turn, every stop - then melts back into them when they stand still.
##
## Built on the same trick as [TrailChronoEchoPreset]: it reads the wearer's
## CURRENT sprite frame rather than drawing art of its own, so it is every skin's
## shadow for free. Where Chrono Echo stamps frozen copies, this keeps ONE sprite
## and feeds it a delayed recording - (position, frame, facing) sampled every
## frame into a short ring - which is what makes it read as a second figure
## moving rather than as a smear.
##
##   TWIN    one top_level Sprite2D, silhouette shader, replaying DELAY_S ago.
##   WISPS   smoke rising off the twin while it is separated from the wearer.

const SHADER: Shader = preload("res://source/common/gameplay/cosmetics/presets/shaders/shadow_twin.gdshader")

## How far behind the twin runs. Long enough to clear the body at a jog, short
## enough that it still reads as attached to this player and not as a stranger.
const DELAY_S: float = 0.32
## Below this separation the twin fades out: standing on top of the wearer it
## only makes the body look dirty.
const MERGE_PX: float = 6.0
const SEPARATE_PX: float = 18.0

const FILL: Color = Color(0.09, 0.05, 0.16)
const RIM: Color = Color(0.64, 0.46, 1.0)

## Recording, oldest first: {"t", "p", "tex", "flip", "off"}.
var _tape: Array[Dictionary] = []
var _twin: Sprite2D
var _material: ShaderMaterial
var _wisps: CPUParticles2D

## Sprite to read INSTEAD of the wearer's - the render-tool seam, same as
## [member TrailChronoEchoPreset.sprite_source].
var sprite_source: AnimatedSprite2D


func _build() -> void:
	_twin = Sprite2D.new()
	_twin.top_level = true
	# Below the wearer: top_level would otherwise draw the twin over them.
	_twin.z_index = -2
	_twin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter(&"fill", FILL)
	_material.set_shader_parameter(&"rim", RIM)
	_twin.material = _material
	_twin.visible = false
	add_child(_twin)

	# Parented to the twin, emitting in world space, so the smoke comes off the
	# shadow and hangs in the air where it was.
	var p: CPUParticles2D = CPUParticles2D.new()
	p.amount = 10
	p.lifetime = 0.9
	p.local_coords = false
	p.texture = VfxTextures.puff(10)
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.position = Vector2(0, CHEST_Y)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(6.0, 12.0)
	p.direction = Vector2(0, -1)
	p.spread = 25.0
	p.gravity = Vector2(0, -18.0)
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 12.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	p.color_ramp = _fade_ramp(RIM.darkened(0.35), 0.35)
	_twin.add_child(p)
	_wisps = p


func _tick(delta: float) -> void:
	super(delta)
	var source: AnimatedSprite2D = _source()
	if source == null or source.sprite_frames == null or not _viewer_in_range():
		_twin.visible = false
		_wisps.emitting = false
		return
	var tex: Texture2D = source.sprite_frames.get_frame_texture(source.animation, source.frame)
	_tape.append({
		"t": _elapsed, "p": source.global_position, "tex": tex,
		"flip": source.flip_h, "off": source.offset, "scale": source.global_scale,
	})
	# Keep one sample older than the delay, so there is always a frame to show.
	var cutoff: float = _elapsed - DELAY_S
	while _tape.size() > 2 and float(_tape[1]["t"]) <= cutoff:
		_tape.pop_front()

	var shown: Dictionary = _tape[0]
	if shown["tex"] == null:
		_twin.visible = false
		return
	_twin.texture = shown["tex"]
	_twin.flip_h = shown["flip"]
	_twin.offset = shown["off"]
	_twin.scale = shown["scale"]
	_twin.global_position = shown["p"]

	var apart: float = (shown["p"] as Vector2).distance_to(source.global_position) / maxf(0.001, source.global_scale.x)
	var presence: float = clampf((apart - MERGE_PX) / (SEPARATE_PX - MERGE_PX), 0.0, 1.0)
	_twin.visible = presence > 0.0
	_material.set_shader_parameter(&"alpha", 0.8 * presence)
	_wisps.emitting = presence > 0.5


func _source() -> AnimatedSprite2D:
	if is_instance_valid(sprite_source):
		return sprite_source
	if wearer == null or not is_instance_valid(wearer):
		return null
	return wearer.animated_sprite
