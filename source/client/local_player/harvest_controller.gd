class_name HarvestController
extends Node
## Commercial-MMO gather loop: click a [MineableNode] once, walk into range,
## auto-swing the equipped tool until THIS player's charge pool on the node is
## depleted, then stop and require a fresh click. Cancel with WASD, a ground
## click, death, or opening a menu.
##
## Authority stays on the server — this only drives the existing
## [code]action.perform[/code] → PickArc → [method MineableNode.register_gather_hit]
## path. No client-side ore awards.

## How close (px) before we stop pathing and start swinging.
const GATHER_RANGE: float = 48.0


var _player: LocalPlayer
var _target: MineableNode
var _active: bool = false


func setup(player: LocalPlayer) -> void:
	_player = player


func is_active() -> bool:
	return _active and _target != null and is_instance_valid(_target)


func start(node: MineableNode) -> void:
	if _player == null or node == null or not is_instance_valid(node):
		return
	if node.data == null or node.data.ore == null:
		return
	if not _has_correct_tool(node):
		var needed: String = String(node.data.required_tool)
		if needed.is_empty():
			Toaster.toast("You need a gathering tool equipped.")
		else:
			Toaster.toast("You need a %s for this." % needed.capitalize())
		return

	_target = node
	_active = true
	_player._follow_peer_id = 0


func cancel() -> void:
	_active = false
	_target = null


## Called from [method LocalPlayer.process_input] each frame while active.
## Returns true if it handled look/attack this frame (caller should skip
## normal hold-to-attack).
func tick() -> bool:
	if not is_active():
		cancel()
		return false
	# Typing in chat doesn't break the gather loop — only death or a menu does.
	if _player._dead or ClientState.menu_open:
		cancel()
		return false
	if not _has_correct_tool(_target):
		Toaster.toast("You need a gathering tool equipped.")
		cancel()
		return false

	var to_node: Vector2 = _target.global_position - _player.global_position
	var dist: float = to_node.length()
	if to_node != Vector2.ZERO:
		_player.look_direction = to_node.normalized()

	if dist > GATHER_RANGE:
		# Walk in — use the pathfinder directly so ground-click cancel stays clean.
		_player._click_navigation.request_move(_target.global_position)
		return true

	_player._click_navigation.cancel()

	# Fully depleted for this player: stop and require a new click after regen.
	var charges: int = _target.client_charges_left()
	if charges == 0:
		Toaster.toast(_depleted_toast())
		cancel()
		return false

	if _player.equipment_component.can_use(&"weapon", 0) and InstanceClient.current != null:
		Client.request_data(
			&"action.perform",
			Callable(),
			{"d": _player.look_direction, "i": 0},
			InstanceClient.current.name
		)
	return true


## React to [code]mining.gather_result[/code] for our target.
func on_gather_result(data: Dictionary) -> void:
	if not is_active():
		return
	var raw_path: Variant = data.get("node_path", null)
	if raw_path == null or InstanceClient.current == null:
		return
	var node: Node = InstanceClient.current.get_node_or_null(raw_path as NodePath)
	if node != _target:
		return

	if not data.get("ok", false):
		match str(data.get("reason", "")):
			"wrong_tool", "no_tool", "level", "depleted":
				cancel()
			# cooldown / mid-swing: keep going
		return

	# Last charge just yielded — stop so the player must re-click after regen.
	if int(data.get("charges_left", 1)) <= 0:
		Toaster.toast(_depleted_toast())
		cancel()


func _depleted_toast() -> String:
	if _target != null and _target.harvests_on_right_click():
		return "Resource depleted. Right-click again when it regenerates."
	return "Resource depleted. Click again when it regenerates."


func _has_correct_tool(node: MineableNode) -> bool:
	if node == null or node.data == null:
		return false
	var required: StringName = node.data.required_tool
	if required == &"":
		return true
	var item: Item = _player.equipment_component.equipped_items.get(&"weapon", null)
	if item is ToolItem:
		return (item as ToolItem).tool_type == required
	return false
