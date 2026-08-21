class_name BagOrder
## Client-persisted bag slot order for drag-to-rearrange. Inventory stacks are
## keyed by uid with no grid index; this keeps a uid sequence in settings so
## the dock (and fullscreen) can honor player arrangement across sessions.
## Empty grid cells are stored as [constant EMPTY] so items can sit past gaps.


const SECTION: StringName = &"inventory"
const PROPERTY: StringName = &"bag_order"
## Placeholder in the saved order for an empty bag square.
const EMPTY: int = -1


## Visible drag ghost for bag rearrange. Tall atlas weapon icons shrink badly
## in a tiny box — use a generous square + nearest filtering so the art reads.
static func make_drag_preview(texture: Texture2D, box: Vector2 = Vector2(48, 48)) -> Control:
	var host := Control.new()
	host.custom_minimum_size = box
	host.size = box
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.z_as_relative = false
	host.z_index = 4096
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.92)
	style.set_border_width_all(1)
	style.border_color = Color(0.75, 0.78, 0.88, 0.85)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override(&"panel", style)
	host.add_child(panel)
	var icon := TextureRect.new()
	icon.texture = texture
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 4
	icon.offset_top = 4
	icon.offset_right = -4
	icon.offset_bottom = -4
	host.add_child(icon)
	return host


## Godot parents set_drag_preview() under the root Viewport (canvas layer 0),
## so the ghost draws UNDER the UI CanvasLayer (layer 10). Reparent onto the
## UI layer (or a temporary high layer) so it tracks above inventory menus.
static func elevate_drag_preview(host: Control, preview: Control) -> void:
	if host == null or preview == null:
		return
	host.set_drag_preview(preview)
	var ui_layer: CanvasLayer = _find_ui_canvas_layer(host)
	if ui_layer != null:
		# Defer: set_drag_preview parents under the viewport first.
		preview.call_deferred(&"reparent", ui_layer)
		return
	# Fallback when UI isn't mounted yet — own a high CanvasLayer for the drag.
	var layer := CanvasLayer.new()
	layer.layer = 128
	layer.name = &"BagDragLayer"
	host.get_tree().root.add_child(layer)
	preview.tree_exiting.connect(layer.queue_free)
	preview.call_deferred(&"reparent", layer)


static func _find_ui_canvas_layer(from: Node) -> CanvasLayer:
	var node: Node = from
	while node != null:
		if node is CanvasLayer and String(node.name) == "UI":
			return node as CanvasLayer
		node = node.get_parent()
	var tree := from.get_tree()
	if tree == null:
		return null
	return tree.root.find_child("UI", true, false) as CanvasLayer


static func load_order() -> Array:
	var raw: Variant = ClientState.settings.get_value(SECTION, PROPERTY)
	if raw is Array:
		return (raw as Array).duplicate()
	return []


static func save_order(order: Array) -> void:
	ClientState.settings.set_value(SECTION, PROPERTY, order)


## Merge live inventory uids into the saved order: keep known order (and empty
## gaps), append new uids, drop missing ones.
static func sync_with_entries(entries: Array) -> Array:
	var live: Array = []
	for entry: Variant in entries:
		if entry is Dictionary and entry.has("uid"):
			live.append(int(entry["uid"]))
	var order: Array = load_order()
	var kept: Array = []
	var used: Dictionary = {}
	for uid: Variant in order:
		var id: int = int(uid)
		if id == EMPTY:
			kept.append(EMPTY)
			continue
		if id in live and not used.has(id):
			kept.append(id)
			used[id] = true
	# Drop trailing empties so newly gained items pack after the last real slot.
	while not kept.is_empty() and int(kept[kept.size() - 1]) == EMPTY:
		kept.pop_back()
	for id: int in live:
		if not used.has(id):
			kept.append(id)
	if kept != order:
		save_order(kept)
	return kept


## Sort key helper: lower index in order first; unknown uids go last by uid.
static func index_of(order: Array, uid: int) -> int:
	var idx: int = order.find(uid)
	return idx if idx >= 0 else 1_000_000 + uid


static func swap(order: Array, uid_a: int, uid_b: int) -> Array:
	var ia: int = order.find(uid_a)
	var ib: int = order.find(uid_b)
	# A dragged item the saved order has never seen (freshly looted, or the
	# order was pruned while another bag was open) used to fall through here and
	# silently do nothing. Put it where the player dropped it instead.
	if ia < 0 and ib >= 0:
		# move_to_index needs the uid to already be in the list, so place it
		# here directly.
		order.insert(ib, uid_a)
		save_order(order)
		return order
	if ia < 0 or ib < 0 or ia == ib:
		return order
	var tmp: Variant = order[ia]
	order[ia] = order[ib]
	order[ib] = tmp
	save_order(order)
	return order


## Move uid_a to the index currently occupied by uid_b (insert-style).
static func move_before(order: Array, uid_a: int, uid_b: int) -> Array:
	var ia: int = order.find(uid_a)
	var ib: int = order.find(uid_b)
	if ia < 0 or ib < 0 or ia == ib:
		return order
	order.remove_at(ia)
	if ia < ib:
		ib -= 1
	order.insert(ib, uid_a)
	save_order(order)
	return order


## Place [param uid] at bag grid [param index], preserving empty squares.
## Trailing empties are trimmed after the move.
static func move_to_index(order: Array, uid: int, index: int) -> Array:
	if uid < 0 or index < 0:
		return order
	var ia: int = order.find(uid)
	if ia < 0:
		return order
	while order.size() <= index:
		order.append(EMPTY)
	order.remove_at(ia)
	if ia < index:
		index -= 1
	if index < order.size() and int(order[index]) == EMPTY:
		order[index] = uid
	else:
		order.insert(clampi(index, 0, order.size()), uid)
	while not order.is_empty() and int(order[order.size() - 1]) == EMPTY:
		order.pop_back()
	save_order(order)
	return order
