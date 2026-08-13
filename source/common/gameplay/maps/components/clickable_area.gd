class_name ClickableArea
extends Area2D
## A reusable world-space CLICK TARGET: emits [signal clicked] on a left-click or tap,
## and [signal right_clicked] for desktop context actions.
## Set [member capture_left_click] false to ignore left mouse (taps and right-clicks
## still fire) so a node can sit on the forest floor without stealing woodcutting clicks.
## It carries NO policy — each user decides what the click MEANS (talk, inspect, loot,
## open) by connecting [signal clicked]. So players, NPCs, signs, lootables, doors all
## share one detection path instead of re-implementing the input-event boilerplate.
##
## Pair it with a CollisionShape2D child and tune that box (in the editor, or in code).
## It is [member input_pickable] so the mouse/touch can hit it — which has a per-area
## cost, so add it ONLY to things worth clicking, never to a shared base that enemies
## would inherit.

## Emitted once per left-click / tap that lands on this area.
signal clicked
signal right_clicked

## When false, left mouse does not emit [signal clicked] so the click can pass
## through to trees / ground-move. Taps and right-clicks still fire.
var capture_left_click: bool = true


func _ready() -> void:
	input_pickable = true
	input_event.connect(_on_input_event)


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventScreenTouch and event.pressed:
		clicked.emit()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and capture_left_click:
			clicked.emit()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			right_clicked.emit()
