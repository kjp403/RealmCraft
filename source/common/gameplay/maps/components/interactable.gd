class_name Interactable
extends Area2D
## A clickable map station. On a left-click / tap the local player walks into
## [constant INTERACT_RANGE] (if needed) then opens a client menu —
## open_menu_requested(menu_name, menu_arg). Centralizes the input-pickable +
## click-detection + approach boilerplate that every station used to copy.
##
## Two ways to use it:
##  • SIMPLE station — just this node, configured in the inspector (menu_name +
##    menu_arg). No script needed (DungeonExit, a quest board, …).
##  • STATEFUL station — a node with its own server-side data (DungeonMaster,
##    DuelMaster) EXTENDS this, sets menu_name/menu_arg in _ready, calls
##    super._ready(), and keeps its fields. The click is inherited.
##
## The server never clicks, so it just disables input; the client wires the handler.

## Max distance (px) before the player must walk closer. Matches [constant NPC.INTERACT_RANGE].
const INTERACT_RANGE: float = 90.0

## The client menu to open on click. Empty = inert (a non-clickable decoration).
@export var menu_name: StringName = &""
## Argument passed to that menu's open() — e.g. a station id (master_id), or 0 when
## the menu takes none.
@export var menu_arg: int = 0
## Optional world name shown above this interactable while the cursor hovers it
## (same pattern as mineable node NameLabels). Empty = no hover label.
@export var hover_name: String = ""


## Tracks our contribution to ClientState.world_interactables_hovered so a
## mouse-exit / free can't double-decrement the shared counter.
var _interactable_hovered: bool = false
var _hover_name_label: Label


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
	_setup_hover_name_label()


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	var clicked: bool = (
		(event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed)
		or (event is InputEventScreenTouch and event.pressed)
	)
	if clicked and menu_name != &"":
		get_viewport().set_input_as_handled()
		_request_interact()


## Walk into range (if needed), then open the configured menu. Subclasses that
## override click handling should call this (or [method _do_interact]) instead of
## toasting "Too far".
func _request_interact() -> void:
	var lp: LocalPlayer = ClientState.local_player
	if lp == null or not is_instance_valid(lp):
		return
	if _player_in_range():
		_do_interact()
		return
	lp.start_auto_interact(self, INTERACT_RANGE, _do_interact)


func _do_interact() -> void:
	if menu_name == &"":
		return
	ClientState.open_menu_requested.emit(menu_name, _build_menu_arg())


func _player_in_range() -> bool:
	var lp: LocalPlayer = ClientState.local_player
	if lp == null or not is_instance_valid(lp):
		return false
	return global_position.distance_to(lp.global_position) <= INTERACT_RANGE


func _set_interactable_hover(on: bool) -> void:
	if not GameMode.is_client() or on == _interactable_hovered:
		return
	_interactable_hovered = on
	ClientState.world_interactables_hovered += 1 if on else -1
	if _hover_name_label != null:
		_hover_name_label.visible = on


func _setup_hover_name_label() -> void:
	if hover_name.is_empty():
		return
	_hover_name_label = Label.new()
	_hover_name_label.name = "HoverNameLabel"
	_hover_name_label.text = hover_name
	_hover_name_label.visible = false
	_hover_name_label.z_index = 20
	_hover_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hover_name_label.add_theme_font_size_override("font_size", 12)
	_hover_name_label.add_theme_color_override("font_color", Color.WHITE)
	_hover_name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hover_name_label.add_theme_constant_override("outline_size", 3)
	var half_h: float = 48.0
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node != null and shape_node.shape is RectangleShape2D:
		half_h = (shape_node.shape as RectangleShape2D).size.y * 0.5
	_hover_name_label.position = Vector2(-56.0, -half_h - 18.0)
	_hover_name_label.size = Vector2(112.0, 20.0)
	add_child(_hover_name_label)


## The argument handed to the opened menu's open(). Defaults to [member menu_arg];
## stateful subclasses override to pass a richer payload (e.g. a resource + key).
func _build_menu_arg() -> Variant:
	return menu_arg
