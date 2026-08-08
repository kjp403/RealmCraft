class_name NpcContextMenu
extends Node
## Right-click menu on friendly NPCs — Talk plus capability shortcuts (Bank).


const ACTION_TALK: int = 0
const ACTION_BANK: int = 1
const TARGET_HEADING_ID: int = 100

var _menu: PopupMenu
var _target: NPC
var _has_bank: bool = false


func _ready() -> void:
	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_action)
	add_child(_menu)
	ClientState.npc_context_requested.connect(_open_for_npc)


func _open_for_npc(npc: NPC) -> void:
	if npc == null or not is_instance_valid(npc) or npc.npc_resource == null:
		return
	_target = npc
	_has_bank = false
	for interaction: NPCInteraction in npc.npc_resource.interactions:
		if interaction is BankInteraction:
			_has_bank = true
			break
	_menu.clear()
	var title: String = npc.display_name if not npc.display_name.is_empty() else "NPC"
	_menu.add_item(title, TARGET_HEADING_ID)
	_menu.set_item_disabled(0, true)
	_menu.add_separator()
	_menu.add_item("Talk", ACTION_TALK)
	if _has_bank:
		_menu.add_item("Bank", ACTION_BANK)
	_menu.position = Vector2i(get_viewport().get_mouse_position())
	_menu.popup()


func _on_action(action_id: int) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	match action_id:
		ACTION_TALK:
			_target.open_interactions()
		ACTION_BANK:
			if _has_bank:
				ClientState.open_menu_requested.emit(&"bank", null)
