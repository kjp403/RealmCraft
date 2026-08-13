class_name SkillLevelGate
extends StaticBody2D
## Solid corridor gate that blocks players under a job level requirement.
## Must span the FULL throat of a dead-end (flush with rock walls) — a floating
## floor sticker players can walk around is not a gate.
## Collision stays up for under-leveled players; those who qualify get the
## collider disabled while inside the approach Area2D.
##
## Movement is client-authoritative, so qualification MUST resolve on the
## client via [member ClientState.skill_levels] (mirrored at login + on
## skills.get / gather / craft). Server peers still read PlayerResource when
## present (dedicated world simulation / tests).

@export var required_skill: StringName = &"mining"
@export var required_level: int = 50
@export var gate_size: Vector2 = Vector2(40, 112)
@export var label_text: String = "Mining 50+"
## Safe eject axis for under-leveled players. Must point toward walkable
## approach ground — never into walls / void beyond the sealed side.
## Mining Cave used LEFT (toward the cave entrance) when it had a DeepVeinGate.
@export var eject_direction: Vector2 = Vector2.LEFT
## How far to shove along [member eject_direction] (must clear the approach Area2D).
@export var eject_distance: float = 96.0

var _collision: CollisionShape2D
var _area: Area2D
var _visual: ColorRect
var _label: Label
var _qualified: Dictionary = {} # instance_id -> true
## Per-player cooldown so a stuck overlap can't spam-shove into a null cell.
var _last_eject_msec: Dictionary = {} # instance_id -> int
const _EJECT_COOLDOWN_MS: int = 750


func _ready() -> void:
	# Characters mask WORLD (layer 2) for movement — not CHARACTER_BODY.
	collision_layer = PhysicsLayers.WORLD
	collision_mask = 0

	var shape := RectangleShape2D.new()
	shape.size = gate_size
	_collision = CollisionShape2D.new()
	_collision.shape = shape
	add_child(_collision)

	_visual = ColorRect.new()
	_visual.color = Color(0.55, 0.15, 0.85, 0.60)
	_visual.size = gate_size
	_visual.position = -gate_size * 0.5
	_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_visual)

	# Borders along the long axis so a vertical throat-seal still reads as a wall.
	_add_edge_borders()

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
	_label.position = Vector2(-maxi(60, int(gate_size.x)) * 0.5, -gate_size.y * 0.5 - 18)
	_label.size = Vector2(maxi(60, int(gate_size.x)), 16)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	_area = Area2D.new()
	_area.collision_layer = 0
	_area.collision_mask = PhysicsLayers.CHARACTER_BODY
	_area.monitoring = true
	var area_shape := CollisionShape2D.new()
	var area_rect := RectangleShape2D.new()
	area_rect.size = gate_size + Vector2(72, 72)
	area_shape.shape = area_rect
	_area.add_child(area_shape)
	add_child(_area)
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)

	# Re-evaluate if skill levels arrive/update while standing in the approach.
	if not Engine.is_editor_hint() and GameMode.is_client():
		ClientState.skill_levels_changed.connect(_on_skill_levels_changed)


func _add_edge_borders() -> void:
	var edge := Color(0.85, 0.55, 1.0, 0.95)
	if gate_size.y >= gate_size.x:
		# Vertical gate — left/right rails.
		for x_off: float in [-gate_size.x * 0.5, gate_size.x * 0.5 - 3.0]:
			var rail := ColorRect.new()
			rail.color = edge
			rail.size = Vector2(3, gate_size.y)
			rail.position = Vector2(x_off, -gate_size.y * 0.5)
			rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(rail)
	else:
		# Horizontal gate — top/bottom rails.
		for y_off: float in [-gate_size.y * 0.5, gate_size.y * 0.5 - 3.0]:
			var rail := ColorRect.new()
			rail.color = edge
			rail.size = Vector2(gate_size.x, 3)
			rail.position = Vector2(-gate_size.x * 0.5, y_off)
			rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(rail)


func _on_body_entered(body: Node2D) -> void:
	var player := body as Player
	if player == null:
		return
	if _player_qualifies(player):
		_qualified[player.get_instance_id()] = true
		_refresh_collision()
		return
	# Soft eject only the local avatar on clients (position is client-owned).
	# Remote dummies must not be shoved — that desyncs their replicated pose.
	if GameMode.is_client() and not _is_local_player(player):
		return
	_eject_player(player)
	# Levels may still be hydrating — pull skills.get once so a late mirror
	# can open the gate without forcing a relog.
	if GameMode.is_client() and _is_local_player(player) and ClientState.skill_levels.is_empty():
		_request_skill_mirror()


func _on_body_exited(body: Node2D) -> void:
	var player := body as Player
	if player == null:
		return
	var id: int = player.get_instance_id()
	_qualified.erase(id)
	_last_eject_msec.erase(id)
	_refresh_collision()


## Push under-leveled players along the authored safe axis far enough to leave
## the approach Area2D. Never use (player - gate).normalized() — near corners
## that vector can shove into rock / void and soft-lock movement.
func _eject_player(player: Player) -> void:
	var id: int = player.get_instance_id()
	var now: int = Time.get_ticks_msec()
	if now - int(_last_eject_msec.get(id, -99999)) < _EJECT_COOLDOWN_MS:
		return
	_last_eject_msec[id] = now

	var dir: Vector2 = eject_direction
	if dir.length_squared() < 0.0001:
		dir = Vector2.LEFT
	else:
		dir = dir.normalized()

	# Already clear of the sealed side — don't yank them again.
	var from_gate: Vector2 = player.global_position - global_position
	if from_gate.dot(dir) >= eject_distance * 0.5:
		return

	var target: Vector2 = global_position + dir * eject_distance
	# Keep their offset along the gate's long axis so a vertical throat-seal
	# doesn't snap everyone to the exact center line.
	if absf(dir.x) >= absf(dir.y):
		target.y = player.global_position.y
	else:
		target.x = player.global_position.x
	player.global_position = target


func _on_skill_levels_changed() -> void:
	if not GameMode.is_client() or ClientState.local_player == null:
		return
	var lp: Player = ClientState.local_player
	if not is_instance_valid(lp):
		return
	# Only refresh when the local player is still inside the approach area.
	if not _area.get_overlapping_bodies().has(lp):
		return
	if _player_qualifies(lp):
		_qualified[lp.get_instance_id()] = true
	else:
		_qualified.erase(lp.get_instance_id())
	_refresh_collision()


func _player_qualifies(player: Player) -> bool:
	# Server / tests: authoritative PlayerResource when present.
	if player.player_resource != null:
		var skill: Dictionary = player.player_resource.get_skill(required_skill)
		return int(skill.get("level", 1)) >= required_level
	# Client: position is client-authoritative; use the mirrored skill levels.
	if GameMode.is_client() and _is_local_player(player):
		return ClientState.skill_level(required_skill) >= required_level
	return false


func _is_local_player(player: Player) -> bool:
	return GameMode.is_client() and ClientState.local_player != null and player == ClientState.local_player


func _request_skill_mirror() -> void:
	if InstanceClient.current == null:
		return
	Client.request_data(
		&"skills.get",
		func(data: Dictionary) -> void:
			ClientState.apply_skills_payload(data.get("skills", {})),
		{},
		InstanceClient.current.name
	)


func _refresh_collision() -> void:
	# Open only while a qualifying player is in the approach area.
	_collision.disabled = not _qualified.is_empty()
	_visual.color = (
		Color(0.25, 0.75, 0.45, 0.40) if _collision.disabled
		else Color(0.55, 0.15, 0.85, 0.60)
	)
