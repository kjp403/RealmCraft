class_name AmbientCritter
extends Node2D
## Client-only wandering fauna for atmosphere. Not attackable, not networked,
## and never placed under ReplicatedPropsContainer.

@export var sprite_frames: SpriteFrames
@export var wander_radius: float = 72.0
@export var move_speed: float = 26.0
@export var scale_factor: float = 1.0
@export var idle_anim: StringName = &"idle"
@export var walk_anim: StringName = &"walk"
@export var pause_min_s: float = 1.2
@export var pause_max_s: float = 3.8

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

var _home: Vector2
var _target: Vector2
var _pausing: bool = true
var _pause_left: float = 0.0


func _ready() -> void:
	# Only strip on dedicated servers. Keep alive for client + tool/preview runs
	# (empty GameMode when launched via -s without --mode=client).
	if GameMode.is_any_server():
		queue_free()
		return
	_home = global_position
	_target = _home
	if sprite_frames != null:
		_sprite.sprite_frames = sprite_frames
	_sprite.scale = Vector2(scale_factor, scale_factor)
	_sprite.centered = true
	_sprite.offset = Vector2(0, -2)
	_play_idle()
	_pause_left = randf_range(0.2, pause_max_s)


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
	if dist < 2.0:
		_pausing = true
		_pause_left = randf_range(pause_min_s, pause_max_s)
		_play_idle()
		return

	var step: Vector2 = to.normalized() * move_speed * delta
	if step.length() > dist:
		step = to
	global_position += step
	if absf(step.x) > 0.05:
		_sprite.flip_h = step.x < 0.0


func _pick_target() -> void:
	var angle: float = randf() * TAU
	var radius: float = randf() * wander_radius
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
