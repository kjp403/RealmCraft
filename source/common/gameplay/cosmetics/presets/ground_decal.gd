class_name GroundDecal
extends Node2D
## One dissolving mark on the floor, dropped by a trail preset at a world position
## and freeing itself when it has dissolved away.
##
## A Node2D holding one shader quad, rather than the quad itself: the trail code
## places these with global_position, and a bare Control would fight it (a
## Control's position is its top-left, and centring it would be overwritten every
## time it was moved). The quad child owns the centring and the ground-plane
## squash, so the decal as a whole positions like every other world object.
##
## Lifetime is driven from here rather than from TIME in the shader so that decals
## dropped a frame apart dissolve out of phase — see the shader header.

const SHADER: Shader = preload("res://source/common/gameplay/cosmetics/presets/shaders/ground_decal.gdshader")

enum Variant { SLUDGE, SPLATTER, SCORCH, DUST }

var variant: int = Variant.SLUDGE
var tint: Color = Color(0.35, 0.85, 0.15)
var diameter: float = 22.0
var life: float = 1.2
## Heading the wearer was moving in when this was dropped; splatters throw along it.
var heading: Vector2 = Vector2.RIGHT

var _material: ShaderMaterial
var _elapsed: float = 0.0


func _ready() -> void:
	# Depth is inherited from whatever mounted the trail (see
	# CosmeticTrailPreset._add_ribbon): the floor plane under a Character in the
	# world, panel depth in the wardrobe preview.
	var quad: ColorRect = ColorRect.new()
	quad.size = Vector2(diameter, diameter)
	# Centred on the drop point, then flattened onto the ground plane so the mark
	# lies on the tiles instead of standing up out of them.
	quad.position = Vector2(-diameter * 0.5, -diameter * 0.5 * CosmeticPreset.GROUND_SQUASH)
	quad.scale = Vector2(1.0, CosmeticPreset.GROUND_SQUASH)
	quad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter(&"variant", variant)
	_material.set_shader_parameter(&"tint", tint)
	_material.set_shader_parameter(&"rand", randf())
	_material.set_shader_parameter(&"heading", heading)
	_material.set_shader_parameter(&"decal_pixels", maxf(8.0, diameter))
	quad.material = _material
	add_child(quad)


func _process(delta: float) -> void:
	_elapsed += delta
	var age: float = _elapsed / maxf(0.01, life)
	if age >= 1.0:
		queue_free()
		return
	_material.set_shader_parameter(&"age", age)
