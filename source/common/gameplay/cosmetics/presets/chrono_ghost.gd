class_name ChronoGhost
extends Sprite2D
## One after-image left behind by [TrailChronoEchoPreset]: a copy of the wearer's
## sprite frame, frozen where they stood, coming apart into pixel blocks.
##
## It is a plain Sprite2D holding the SAME Texture2D the wearer's AnimatedSprite2D
## is drawing this frame - not a copy of the pixels. SpriteFrames hands out
## AtlasTexture regions into an already-loaded sheet, so a ghost costs a node and
## a material, never an image allocation, which is what makes it affordable to
## spawn one every 0.12 s per wearer.
##
## Pinned to the world (top_level) and self-freeing: the wearer runs on, the ghost
## stays exactly where the step happened and queue_free()s itself the moment its
## dissolve completes. Nothing tracks it and nothing has to clean it up.

const SHADER: Shader = preload("res://source/common/gameplay/cosmetics/presets/shaders/pixel_dissolve.gdshader")

## Seconds from spawn to fully dissolved.
var life: float = 0.4
var tint: Color = Color(0.55, 0.85, 1.0)
## Peak opacity. Well under half: the point is a smear of where someone WAS, and
## a solid ghost reads as a second player standing in the room.
var ghost_alpha: float = 0.45

var _material: ShaderMaterial
var _elapsed: float = 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # crisp, like the body
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter(&"tint", tint)
	_material.set_shader_parameter(&"alpha", ghost_alpha)
	_material.set_shader_parameter(&"progress", 0.0)
	material = _material


## Copy everything about how [param source] is currently being drawn, so the ghost
## lands exactly on top of where the body was rather than near it.
##
## offset and centered are the load-bearing pair: the character body carries an
## offset of (0,-30) on 64 px art to put its feet on the node origin, and a ghost
## that ignored it would float a full body-height above the footprints.
func adopt(source: AnimatedSprite2D) -> bool:
	if source == null or source.sprite_frames == null:
		return false
	var anim: StringName = source.animation
	if not source.sprite_frames.has_animation(anim):
		return false
	var frame: Texture2D = source.sprite_frames.get_frame_texture(anim, source.frame)
	if frame == null:
		return false
	texture = frame
	offset = source.offset
	centered = source.centered
	flip_h = source.flip_h
	flip_v = source.flip_v
	return true


func _process(delta: float) -> void:
	_elapsed += delta
	var progress: float = _elapsed / maxf(0.01, life)
	if progress >= 1.0:
		queue_free()
		return
	_material.set_shader_parameter(&"progress", progress)
