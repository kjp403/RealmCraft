class_name Interactable
extends Area2D
## A clickable map station. On a left-click / tap it opens a client menu —
## open_menu_requested(menu_name, menu_arg). Centralizes the input-pickable +
## click-detection boilerplate that every station used to copy.
##
## Two ways to use it:
##  • SIMPLE station — just this node, configured in the inspector (menu_name +
##    menu_arg). No script needed (DungeonExit, a quest board, …).
##  • STATEFUL station — a node with its own server-side data (DungeonMaster,
##    DuelMaster) EXTENDS this, sets menu_name/menu_arg in _ready, calls
##    super._ready(), and keeps its fields. The click is inherited.
##
## The server never clicks, so it just disables input; the client wires the handler.

## The client menu to open on click. Empty = inert (a non-clickable decoration).
@export var menu_name: StringName = &""
## Argument passed to that menu's open() — e.g. a station id (master_id), or 0 when
## the menu takes none.
@export var menu_arg: int = 0


## Tracks our contribution to ClientState.world_interactables_hovered so a
## mouse-exit / free can't double-decrement the shared counter.
var _interactable_hovered: bool = false


func _ready() -> void:
	if multiplayer.is_server():
		input_pickable = false
		return
	# Beat nearby NPC click-areas when stations sit close to vendors.
	z_index = maxi(z_index, 2)
	collision_layer = PhysicsLayers.INTERACTABLE
	input_pickable = true
	input_event.connect(_on_input_event)
	# Suppress combat while hovered — same gate talkable NPCs use — so a station
	# click opens the menu without also firing the weapon (touch / rebound LMB).
	mouse_entered.connect(_set_interactable_hover.bind(true))
	mouse_exited.connect(_set_interactable_hover.bind(false))
	tree_exiting.connect(_set_interactable_hover.bind(false))


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	var clicked: bool = (
		(event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed)
		or (event is InputEventScreenTouch and event.pressed)
	)
	if clicked and menu_name != &"":
		ClientState.open_menu_requested.emit(menu_name, _build_menu_arg())


func _set_interactable_hover(on: bool) -> void:
	if not GameMode.is_client() or on == _interactable_hovered:
		return
	_interactable_hovered = on
	ClientState.world_interactables_hovered += 1 if on else -1


## The argument handed to the opened menu's open(). Defaults to [member menu_arg];
## stateful subclasses override to pass a richer payload (e.g. a resource + key).
func _build_menu_arg() -> Variant:
	return menu_arg
