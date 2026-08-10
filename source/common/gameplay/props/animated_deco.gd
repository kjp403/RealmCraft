class_name AnimatedDeco
extends Node2D
## Client-only looping prop (torch / candle / spike). Optional PointLight2D child.

@export var sprite_frames: SpriteFrames
@export var anim_name: StringName = &"default"
@export var scale_factor: float = 1.0
@export var light_color: Color = Color(1, 0.7, 0.3, 1)
@export var light_energy: float = 0.0
@export var light_scale: float = 1.2

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	if GameMode.is_any_server():
		queue_free()
		return
	if sprite_frames != null:
		_sprite.sprite_frames = sprite_frames
	_sprite.scale = Vector2(scale_factor, scale_factor)
	_sprite.centered = true
	if _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(anim_name):
		_sprite.play(anim_name)
	if light_energy > 0.0:
		var light := PointLight2D.new()
		light.texture = load("res://source/common/gameplay/lighting/light_radial.tres")
		light.color = light_color
		light.energy = light_energy
		light.texture_scale = light_scale
		add_child(light)
