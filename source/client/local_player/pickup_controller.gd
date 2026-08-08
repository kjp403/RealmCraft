class_name PickupController
extends Node
## Click a [GroundItem] once: walk into range, then request [code]item.pickup[/code].
## Mirrors [HarvestController] so drops use the same interactable click stack
## (hover suppresses click-move / combat; WASD or a ground click cancels).

const PICKUP_RANGE: float = 72.0

var _player: LocalPlayer
var _target: Node2D
var _active: bool = false
var _prop_id: int = -1


func setup(player: LocalPlayer) -> void:
	_player = player


func is_active() -> bool:
	return _active and _target != null and is_instance_valid(_target)


func start(item: Node2D, prop_id: int) -> void:
	if _player == null or item == null or not is_instance_valid(item):
		return
	if prop_id < 0:
		return
	_target = item
	_prop_id = prop_id
	_active = true
	_player._follow_peer_id = 0
	if _player._harvest_controller != null:
		_player._harvest_controller.cancel()


func cancel() -> void:
	_active = false
	_target = null
	_prop_id = -1


## Called from [method LocalPlayer.process_input] each frame while active.
## Returns true if it handled this frame (caller should skip hold-to-attack).
func tick() -> bool:
	if not is_active():
		cancel()
		return false
	if _player._dead or ClientState.menu_open or _player._has_gui_focus():
		cancel()
		return false

	var dist: float = _player.global_position.distance_to(_target.global_position)
	if dist > PICKUP_RANGE:
		_player._click_navigation.request_move(_target.global_position)
		return true

	_player._click_navigation.cancel()
	if InstanceClient.current == null:
		cancel()
		return false

	var prop_id: int = _prop_id
	cancel()
	Client.request_data(
		&"item.pickup",
		Callable(self, "_on_pickup_response"),
		{"prop_id": prop_id},
		InstanceClient.current.name
	)
	return true


func _on_pickup_response(data: Dictionary) -> void:
	if data.get("ok", false):
		return
	match str(data.get("reason", "")):
		"too_far":
			Toaster.toast("Move closer to pick that up.")
		"missing":
			Toaster.toast("That item is gone.")
		_:
			pass
