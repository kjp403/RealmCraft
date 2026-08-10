class_name AmbientCritter
extends Node2D
## Client-only wandering fauna for atmosphere. Not attackable, not networked.

@export var sprite_frames: SpriteFrames
@export var wander_radius: float = 48.0
@export var move_speed: float = 22.0
@export var scale_factor: float = 1.0
@export var idle_anim: StringName = &"idle"
@export var walk_anim: StringName = &"walk"
@export var pause_min_s: float = 1.8
@export var pause_max_s: float = 4.5

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

var _home: Vector2
var _target: Vector2
var _pausing: bool = true
var _pause_left: float = 0.0


func _ready() -> void:
	if GameMode.is_any_server():
		queue_free()
		return
	_home = global_position
	_target = _home
	if sprite_frames != null:
		_sprite.sprite_frames = sprite_frames
	_sprite.scale = Vector2(scale_factor, scale_factor)
	_sprite.centered = true
	# Anchor feet so tall frames don't float / stack weirdly.
	_sprite.offset = Vector2(0, -_sprite_half_h() * 0.35)
	z_as_relative = true
	y_sort_enabled = true
	_play_idle()
	_pause_left = randf_range(0.4, pause_max_s)


func _sprite_half_h() -> float:
	if _sprite.sprite_frames == null:
		return 16.0
	var anim: StringName = idle_anim if _sprite.sprite_frames.has_animation(idle_anim) else walk_anim
	if not _sprite.sprite_frames.has_animation(anim):
		return 16.0
	var tex: Texture2D = _sprite.sprite_frames.get_frame_texture(anim, 0)
	if tex == null:
		return 16.0
	return float(tex.get_height()) * 0.5


func _process(delta: float) -> void:
	if _pausing:
		_pause_left -= delta
		if _pause_left <= 0.0:
			_pick_target()
			_pausing = false
			_play_walk()
		return

	var to: Vector2 = _target - global_position
	var dist: float = to.length()
	if dist < 3.0:
		_pausing = true
		_pause_left = randf_range(pause_min_s, pause_max_s)
		_play_idle()
		return

	var step: Vector2 = to.normalized() * move_speed * delta
	if step.length() > dist:
		step = to
	# Soft leash — never leave wander circle (prevents stacking through walls).
	var next: Vector2 = global_position + step
	if next.distance_to(_home) > wander_radius:
		_pausing = true
		_pause_left = randf_range(pause_min_s, pause_max_s)
		_play_idle()
		return
	global_position = next
	if absf(step.x) > 0.05:
		_sprite.flip_h = step.x < 0.0


func _pick_target() -> void:
	var angle: float = randf() * TAU
	# Prefer mid-radius so they don't pile on home or scrape the leash edge.
	var radius: float = wander_radius * (0.25 + randf() * 0.6)
	_target = _home + Vector2(cos(angle), sin(angle)) * radius


func _play_idle() -> void:
	if _sprite.sprite_frames == null:
		return
	if _sprite.sprite_frames.has_animation(idle_anim):
		_sprite.play(idle_anim)
	elif _sprite.sprite_frames.has_animation(walk_anim):
		_sprite.play(walk_anim)


func _play_walk() -> void:
	if _sprite.sprite_frames == null:
		return
	if _sprite.sprite_frames.has_animation(walk_anim):
		_sprite.play(walk_anim)
	elif _sprite.sprite_frames.has_animation(idle_anim):
		_sprite.play(idle_anim)
