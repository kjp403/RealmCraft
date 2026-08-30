class_name BloodVignette
extends CanvasLayer
## The Blood aura's screen-space layer: a slow dark-red pulse in the corners of
## the wearer's own screen.
##
## Mounted as a child of [AuraBloodPreset] - a CanvasLayer draws in screen space
## no matter where it hangs in the tree, so parenting it to the preset means it
## dies with the cosmetic automatically and needs no unequip hook of its own.
##
## LAYER 5, which is below the HUD (10) and the reward windows (20) and above the
## world. That ordering is not cosmetic: health, prayer and damage numbers must
## never be dimmed by a cosmetic the player bought.
##
## The pulse is a HEARTBEAT, not a sine - a strong beat, a weaker second beat,
## then a long rest. Driven from script rather than from TIME in the shader so the
## waveform stays readable as GDScript and so it can be eased on and off when the
## cosmetic is equipped mid-session.

const SHADER: Shader = preload("res://source/common/gameplay/cosmetics/presets/shaders/blood_vignette.gdshader")

## Below the HUD. See the class header before changing this.
const LAYER: int = 5
## Seconds per heartbeat cycle. Roughly a resting pulse - fast enough to feel
## alive, slow enough that hours of wear are not agitating.
const BEAT_PERIOD_S: float = 1.35
## Seconds to ease the whole overlay in when equipped, so it never snaps on.
const FADE_IN_S: float = 1.2

var _material: ShaderMaterial
var _rect: ColorRect
var _elapsed: float = 0.0


func _ready() -> void:
	layer = LAYER
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_rect = ColorRect.new()
	_rect.material = _material
	_rect.color = Color(1, 1, 1, 1) # the shader paints; this is just the quad
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Full-viewport and stays that way through window resizes.
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


func _process(delta: float) -> void:
	_elapsed += delta
	var ease_in: float = clampf(_elapsed / FADE_IN_S, 0.0, 1.0)
	_material.set_shader_parameter(&"pulse", _heartbeat() * ease_in)
	_material.set_shader_parameter(&"depth", 0.30 * ease_in)


## 0..1 heartbeat: lub, dub, rest. Two decaying thumps inside one period, with the
## second at roughly two thirds the height of the first, then silence for the back
## half of the cycle. A plain sine here reads as a screen fading in and out, which
## is a bug report; this reads as a pulse.
func _heartbeat() -> float:
	var phase: float = fposmod(_elapsed, BEAT_PERIOD_S) / BEAT_PERIOD_S
	var lub: float = exp(-pow((phase - 0.06) * 14.0, 2.0))
	var dub: float = exp(-pow((phase - 0.24) * 14.0, 2.0)) * 0.62
	return clampf(lub + dub, 0.0, 1.0)
