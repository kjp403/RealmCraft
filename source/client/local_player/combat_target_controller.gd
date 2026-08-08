class_name CombatTargetController
extends Node
## Right-click Attack: walk into range of a hostile and keep swinging the
## primary weapon until the target dies, you cancel (WASD / ground click), or
## you open a menu. Mirrors [HarvestController]'s click-to-act loop.


const ATTACK_RANGE: float = 72.0

var _player: LocalPlayer
var _target: HostileNpc
var _active: bool = false


func setup(player: LocalPlayer) -> void:
	_player = player


func is_active() -> bool:
	return _active and _target != null and is_instance_valid(_target) and not _target.is_dead


func start(npc: HostileNpc) -> void:
	if _player == null or npc == null or not is_instance_valid(npc) or npc.is_dead:
		return
	_target = npc
	_active = true
	_player._follow_peer_id = 0


func cancel() -> void:
	_active = false
	_target = null


## Called from [method LocalPlayer.process_input]. Returns true when it handled
## look/attack this frame (caller should skip hold-to-attack).
func tick() -> bool:
	if not is_active():
		cancel()
		return false
	if _player._dead or ClientState.menu_open or _player._has_gui_focus():
		cancel()
		return false
	if not _player.is_armed():
		Toaster.toast("Equip a weapon to attack.")
		cancel()
		return false

	var to_target: Vector2 = _target.global_position - _player.global_position
	var dist: float = to_target.length()
	if to_target != Vector2.ZERO:
		_player.look_direction = to_target.normalized()

	if dist > ATTACK_RANGE:
		_player._click_navigation.request_move(_target.global_position)
		return true

	_player._click_navigation.cancel()
	if _player.equipment_component.can_use(&"weapon", 0) and InstanceClient.current != null:
		Client.request_data(
			&"action.perform",
			Callable(),
			{"d": _player.look_direction, "i": 0},
			InstanceClient.current.name
		)
	return true
