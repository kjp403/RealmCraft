class_name FloatingDamageNumber
extends Node2D
## Spawns at a world position, displays a damage amount, tweens upward while
## fading, and frees itself. Generic — used by every weapon's hit feedback
## via the combat.hit push.

## How far upward the number rises across its lifetime.
const RISE_DISTANCE: float = 28.0
## Total lifetime (rise + fade run in parallel).
const LIFETIME: float = 0.9
## Horizontal jitter so back-to-back hits don't stack into one unreadable
## blob.
const JITTER_X: float = 12.0

## Orange for melee (physical, non-ranged) damage.
const DAMAGE_COLOR: Color = Color(1.0, 0.55, 0.15)
## Blue for ranged (bow) damage.
const RANGED_COLOR: Color = Color(0.35, 0.65, 1.0)
## Purple for magic damage.
const MAGIC_COLOR: Color = Color(0.75, 0.45, 1.0)
## Green for poison DoT.
const POISON_COLOR: Color = Color(0.45, 0.95, 0.2)
## Red for burn DoT.
const BURN_COLOR: Color = Color(0.95, 0.25, 0.2)
## Green for heals.
const HEAL_COLOR: Color = Color(0.2, 0.9, 0.45)
## High-tier arrow procs. Each tier owns a colour so a player reading a busy
## fight can tell WHICH quiver just fired without watching the log. These match
## the AmmoProcService.SPLAT_* constants by string — rename one without the
## other and the splat silently falls back to default orange.
## Dragon: fiery orange-red thermal burn.
const ARROW_THERMAL_COLOR: Color = Color(1.0, 0.42, 0.12)
## Obsidian: deep crimson-purple life siphon.
const ARROW_SIPHON_COLOR: Color = Color(0.85, 0.16, 0.42)
## Celestial: radiant gold-white holy splash.
const ARROW_SPLASH_COLOR: Color = Color(1.0, 0.9, 0.55)
## Astralite: electric starfield cyan gravity slow.
const ARROW_GRAVITY_COLOR: Color = Color(0.35, 0.95, 1.0)
## Pale spectral blue for Spectral Ward reflect damage. Its own colour because a
## reflect is the only damage number a player sees on an enemy that THEY did not
## choose to deal — reading it as a normal melee hit hides the ward working.
const REFLECT_COLOR: Color = Color(0.62, 0.88, 1.0)

@onready var label: Label = $Label

var _amount: int = 0
var _is_heal: bool = false
var _damage_type: StringName = &""
var _effect_kind: StringName = &""
var _spawn_position: Vector2


## Set before adding to the tree so [member label] has the value when it wakes
## up. [param is_heal] renders a green "+N" instead of a white "N".
func set_amount(amount: int, is_heal: bool = false, damage_type: StringName = &"", effect_kind: StringName = &"") -> void:
	_amount = amount
	_is_heal = is_heal
	_damage_type = damage_type
	_effect_kind = effect_kind
	if label != null:
		_apply_label()


func _apply_label() -> void:
	label.text = ("+%d" % _amount) if _is_heal else str(_amount)
	label.add_theme_color_override(&"font_color", _color())


func _color() -> Color:
	# Effect identity is checked BEFORE the heal colour: an arrow siphon is a
	# heal, but showing it as a generic green number hides which quiver paid it.
	if _effect_kind == &"arrow_thermal":
		return ARROW_THERMAL_COLOR
	if _effect_kind == &"arrow_siphon":
		return ARROW_SIPHON_COLOR
	if _effect_kind == &"arrow_splash":
		return ARROW_SPLASH_COLOR
	if _effect_kind == &"arrow_gravity":
		return ARROW_GRAVITY_COLOR
	if _is_heal:
		return HEAL_COLOR
	if _effect_kind == &"poison":
		return POISON_COLOR
	if _effect_kind == &"burn":
		return BURN_COLOR
	if _effect_kind == &"ward_reflect":
		return REFLECT_COLOR
	if _damage_type == &"magic":
		return MAGIC_COLOR
	if _damage_type == &"ranged":
		return RANGED_COLOR
	return DAMAGE_COLOR


## Pass the world-space spawn position BEFORE add_child. _ready uses this
## to seed the tween's start point — if we set global_position AFTER
## add_child instead, _ready has already created a tween against (0,0) and
## the number snaps to a wrong location.
func set_spawn(pos: Vector2) -> void:
	_spawn_position = pos


func _ready() -> void:
	_apply_label()
	# Random horizontal offset for visual variety. Use roundi to keep the
	# number on a whole pixel — labels at fractional positions blur badly
	# under the project's stretched 960x540 base resolution.
	var jitter: int = int(round(randf_range(-JITTER_X, JITTER_X)))
	global_position = _spawn_position + Vector2(jitter, 0)

	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(self, ^"global_position:y", global_position.y - RISE_DISTANCE, LIFETIME)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, ^"modulate:a", 0.0, LIFETIME)\
		.set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)
