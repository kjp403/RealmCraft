extends ColorRect
## The visible fill of a HUD resource bar, drawn as ink in water by
## ink_fill.gdshader. Sits over a ProgressBar that it never draws — the
## ProgressBar keeps being the source of truth (its `value` is what the bars'
## existing tweens animate), this node just renders it.
##
## Splitting it this way is what keeps the change cheap: health's damage-chip
## tweens, mana's fill tween and prayer's drain logic all still drive plain
## ProgressBar values, and none of them had to learn about shaders.

## The bar this fill mirrors. Its fill StyleBox is emptied in the scene — the
## ProgressBar is a value holder here, not a visual.
@export var source: ProgressBar

## Body gradient, per resource (green blood / blue mana / violet prayer).
@export var ink_deep: Color = Color(0.04, 0.22, 0.07)
@export var ink_bright: Color = Color(0.42, 0.95, 0.45)
@export var edge_color: Color = Color(0.88, 1.0, 0.90)

## Off for the health bar's damage chip: residue behind the live fill must not
## compete with it for the eye.
@export var edge_glow: float = 1.0

## Slower for prayer (it drains over minutes), faster for health.
@export var flow_speed: float = 0.28

const SHADER: Shader = preload("res://source/client/ui/hud/ink_fill.gdshader")
const BOX: GDScript = preload("res://source/client/ui/hud/hud_slot_box.gd")

var _material: ShaderMaterial
var _last_fill: float = -1.0


func _ready() -> void:
	# The fragment writes COLOR outright, so ColorRect.color never reaches the
	# output — white just keeps the node honest if anyone inspects it.
	color = Color(1.0, 1.0, 1.0, 1.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter(&"ink_deep", ink_deep)
	_material.set_shader_parameter(&"ink_bright", ink_bright)
	_material.set_shader_parameter(&"edge_color", edge_color)
	_material.set_shader_parameter(&"edge_glow", edge_glow)
	_material.set_shader_parameter(&"flow_speed", flow_speed)
	material = _material
	resized.connect(_push_size)
	_push_size()


## The shader works in pixels for the corner cut and the edge widths, so it has
## to be told the control's real size rather than inferring it from UV.
func _push_size() -> void:
	_material.set_shader_parameter(&"rect_size", size)
	_material.set_shader_parameter(&"chamfer", BOX.chamfer_for(size))


func _process(_delta: float) -> void:
	if source == null or not is_instance_valid(source):
		return
	var span: float = float(source.max_value) - float(source.min_value)
	var ratio: float = 0.0
	if span > 0.0:
		ratio = clampf((float(source.value) - float(source.min_value)) / span, 0.0, 1.0)
	# Uniform writes are cheap but not free, and these tick every frame on three
	# bars — skip the ones that would change nothing.
	if is_equal_approx(ratio, _last_fill):
		return
	_last_fill = ratio
	_material.set_shader_parameter(&"fill", ratio)
