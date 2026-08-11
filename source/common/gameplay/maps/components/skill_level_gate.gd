class_name SkillLevelGate
extends StaticBody2D
## Visible corridor gate that blocks players under a job level requirement.
## Collision stays up for under-leveled players; those who qualify get the
## collider disabled while inside the approach Area2D.

@export var required_skill: StringName = &"mining"
@export var required_level: int = 50
@export var gate_size: Vector2 = Vector2(96, 24)
@export var label_text: String = "Mining 50+"

var _collision: CollisionShape2D
var _area: Area2D
var _visual: ColorRect
var _label: Label
var _qualified: Dictionary = {} # instance_id -> true


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0

	var shape := RectangleShape2D.new()
	shape.size = gate_size
	_collision = CollisionShape2D.new()
	_collision.shape = shape
	add_child(_collision)

	_visual = ColorRect.new()
	_visual.color = Color(0.55, 0.15, 0.85, 0.45)
	_visual.size = gate_size
	_visual.position = -gate_size * 0.5
	_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_visual)

	var border := ColorRect.new()
	border.color = Color(0.85, 0.55, 1.0, 0.85)
	border.size = Vector2(gate_size.x, 3)
	border.position = Vector2(-gate_size.x * 0.5, -gate_size.y * 0.5)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(border)

	var border2 := ColorRect.new()
	border2.color = Color(0.85, 0.55, 1.0, 0.85)
	border2.size = Vector2(gate_size.x, 3)
	border2.position = Vector2(-gate_size.x * 0.5, gate_size.y * 0.5 - 3)
	border2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(border2)

	_label = Label.new()
	_label.text = label_text if not label_text.is_empty() else (
		"%s %d+" % [JobRegistry.display_name(required_skill), required_level]
	)
	_label.add_theme_font_size_override(&"font_size", 11)
	_label.add_theme_color_override(&"font_color", Color(0.95, 0.85, 1.0))
	_label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 1))
	_label.add_theme_constant_override(&"shadow_offset_x", 1)
	_label.add_theme_constant_override(&"shadow_offset_y", 1)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(-gate_size.x * 0.5, -gate_size.y * 0.5 - 16)
	_label.size = Vector2(gate_size.x, 16)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	_area = Area2D.new()
	_area.collision_layer = 0
	_area.collision_mask = 1
	_area.monitoring = true
	var area_shape := CollisionShape2D.new()
	var area_rect := RectangleShape2D.new()
	area_rect.size = gate_size + Vector2(48, 64)
	area_shape.shape = area_rect
	_area.add_child(area_shape)
	add_child(_area)
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	var player := body as Player
	if player == null or player.player_resource == null:
		return
	if _player_qualifies(player):
		_qualified[player.get_instance_id()] = true
		_refresh_collision()
	elif multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		# Soft bump: push under-leveled players back a step.
		var away: Vector2 = (player.global_position - global_position).normalized()
		if away == Vector2.ZERO:
			away = Vector2.DOWN
		player.global_position += away * 28.0


func _on_body_exited(body: Node2D) -> void:
	var player := body as Player
	if player == null:
		return
	_qualified.erase(player.get_instance_id())
	_refresh_collision()


func _player_qualifies(player: Player) -> bool:
	var skill: Dictionary = player.player_resource.get_skill(required_skill)
	return int(skill.get("level", 1)) >= required_level


func _refresh_collision() -> void:
	# Open the gate if ANY nearby player qualifies (local / single-instance).
	# Under-leveled peers still collide with the StaticBody when closed.
	_collision.disabled = not _qualified.is_empty()
	_visual.color = (
		Color(0.25, 0.75, 0.45, 0.35) if _collision.disabled
		else Color(0.55, 0.15, 0.85, 0.45)
	)
