class_name InteractController
extends Node
## Click a station / NPC once: walk into [member _range], then run [member _on_arrived].
## Shared by crafting stations, talkable NPCs, and other Interactables so nothing
## toasts "Too far" — the player just approaches. Cancel with WASD, a ground click,
## death, or a competing auto-action (gather / pickup / combat).

var _player: LocalPlayer
var _target: Node2D
var _range: float = 90.0
var _on_arrived: Callable
var _active: bool = false


func setup(player: LocalPlayer) -> void:
	_player = player


func is_active() -> bool:
	return _active and _target != null and is_instance_valid(_target)


func start(target: Node2D, interact_range: float, on_arrived: Callable) -> void:
	if _player == null or target == null or not is_instance_valid(target):
		return
	if not on_arrived.is_valid():
		return
	_target = target
	_range = maxf(8.0, interact_range)
	_on_arrived = on_arrived
	_active = true
	_player._follow_peer_id = 0


func cancel() -> void:
	_active = false
	_target = null
	_on_arrived = Callable()


## Called from [method LocalPlayer.process_input] each frame while active.
## Returns true if it handled this frame (caller should skip hold-to-attack).
func tick() -> bool:
	if not is_active():
		cancel()
		return false
	if _player._dead:
		cancel()
		return false
	# A blocking menu mid-approach means the player opened something else — abort.
	# Chat focus doesn't count: typing while walking to an NPC is normal.
	if ClientState.menu_open:
		cancel()
		return false

	var dist: float = _player.global_position.distance_to(_target.global_position)
	if dist > _range:
		_player._click_navigation.request_move(_target.global_position)
		return true

	_player._click_navigation.cancel()
	var cb: Callable = _on_arrived
	cancel()
	if cb.is_valid():
		cb.call()
	return true
