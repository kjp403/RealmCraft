class_name HostileContextMenu
extends Node
## Right-click menu on hostiles — Attack walks in and keeps swinging.


const ACTION_ATTACK: int = 0
const TARGET_HEADING_ID: int = 100

var _menu: PopupMenu
var _target: HostileNpc


func _ready() -> void:
	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_action)
	add_child(_menu)
	ClientState.hostile_context_requested.connect(_open_for_npc)


func _open_for_npc(npc: HostileNpc) -> void:
	if npc == null or not is_instance_valid(npc) or _is_dead(npc):
		return
	_target = npc
	_menu.clear()
	var title: String = npc.display_name if not npc.display_name.is_empty() else String(npc.enemy_type)
	_menu.add_item(title, TARGET_HEADING_ID)
	_menu.set_item_disabled(0, true)
	_menu.add_separator()
	_menu.add_item("Attack", ACTION_ATTACK)
	_menu.position = Vector2i(get_viewport().get_mouse_position())
	_menu.popup()


func _on_action(action_id: int) -> void:
	if action_id != ACTION_ATTACK:
		return
	if _target == null or not is_instance_valid(_target) or _is_dead(_target):
		return
	var local_player: LocalPlayer = ClientState.local_player
	if local_player == null:
		return
	local_player.start_hostile_attack(_target)


func _is_dead(npc: HostileNpc) -> bool:
	if npc.is_dead:
		return true
	if npc.enemy_state == HostileNpc.EnemyState.DEAD \
			or npc.enemy_state == HostileNpc.EnemyState.REVIVING:
		return true
	if npc.stats_component != null and npc.stats_component.get_stat(Stat.HEALTH) <= 0.0:
		return true
	return false
