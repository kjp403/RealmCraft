extends CanvasLayer
## Compact pickup feed (client only) — the Genshin-style answer to loot: small
## [icon] Name ×N pills on the LEFT edge, one row per item, self-coalescing
## (another pickup of the same item bumps the ×N + pulses instead of stacking a
## new row). Replaces the "Looted 1 Tooth" text lines that used to bloat the
## kill cards (docs/notifications.md, toast-lane rework). Purely cosmetic —
## never gameplay-authoritative.
##   LootFeed.add_item(item_id, amount, fallback_name)

## Rows on screen at once (oldest dropped past this) before the player has
## touched the lane. See [member max_rows].
const DEFAULT_MAX_ROWS: int = 6
## Hard bounds on what dragging the lane can set.
const MIN_ROWS: int = 2
const MAX_ROWS_CEILING: int = 12
## One row plus the column separation. The lane height / this = the row count,
## which is what the drag actually controls.
const ROW_PITCH: float = 36.0
## Seconds a row stays after its last bump.
const DWELL_S: float = 2.8

## Icon box per row. One step below ItemSlots.SLOT_SIZE (32) — a pickup pill is a
## FEED entry, not a slot the player can click, so it should not carry the same
## visual weight as the quickslot bar directly below it. PixelIcon integer-scales
## into this box, so 16px item art still draws 1:1 and 64px pack art comes down
## to fit.
const ICON_BOX: float = 24.0

## Row width. LANE_RIGHT keeps the old right edge so widening the left inset
## cannot push a long item name into the centre of the screen.
const LANE_RIGHT: float = 260.0

## How many pills the lane shows.
##
## WHY THE LOOT FEED IS RESIZED BY ROW COUNT AND NOT BY RECT
## Dragging this lane WIDER would be a grip that does nothing: every row is
## SIZE_SHRINK_BEGIN and sizes to its own text, so the column's width is a clamp
## that nothing ever reaches — a 260px lane holding a 95px pill looks identical
## to a 400px one. What a player actually wants to control here is how much of
## the screen loot is allowed to occupy, which is the row COUNT. So the vertical
## drag maps to this, via ROW_PITCH.
var max_rows: int = DEFAULT_MAX_ROWS

var _column: VBoxContainer
## item_id -> {"row": PanelContainer, "label": Label, "count": int}
var _active: Dictionary = {}


func _ready() -> void:
	# Mirrors Toaster: client-only UI.
	if not GameMode.is_client():
		queue_free()
		return
	layer = 90 # Under Announcer (110) and Toaster (128).
	_column = VBoxContainer.new()
	_column.anchor_top = 0.4
	_column.anchor_bottom = 0.4
	# Share ONE left edge with the toast lane sitting above this column. Read from
	# Toaster rather than copied, so the two cannot drift apart: Toaster is
	# registered before LootFeed in project.godot's [autoload] block, so its
	# constants are already resolvable here.
	_column.offset_left = float(Toaster.MARGIN_LEFT)
	_column.offset_right = LANE_RIGHT
	_column.add_theme_constant_override(&"separation", 4)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A floor on the lane height even when it is empty. Without it the column
	# collapses to nothing between pickups and there is no rect for the player to
	# grab in edit mode — the feed would be resizable only while loot happened to
	# be on screen. Costs nothing visually: the column has no background and
	# ignores the mouse.
	_column.custom_minimum_size.y = float(DEFAULT_MAX_ROWS) * ROW_PITCH
	add_child(_column)

	# Vertical only, and the height is read back as a row count (see max_rows).
	var resizer: HudResizer = HudResizer.attach(
		_column,
		&"loot_feed",
		HudResizer.AXIS_Y,
		HudResizer.SizeMode.MODE_MIN_SIZE,
		Vector2(0.0, float(MIN_ROWS) * ROW_PITCH),
		Vector2(0.0, float(MAX_ROWS_CEILING) * ROW_PITCH)
	)
	resizer.size_changed.connect(func(new_size: Vector2) -> void:
		max_rows = clampi(int(new_size.y / ROW_PITCH), MIN_ROWS, MAX_ROWS_CEILING)
		_trim_to_max())


## Feed one pickup. Resolves icon + pretty name from the items registry
## ([param fallback_name] covers unresolvable ids, e.g. content mid-refresh).
func add_item(item_id: int, amount: int, fallback_name: String = "") -> void:
	if _column == null or amount <= 0:
		return

	# Gold gets its coin-flip tick (quiet, slight pitch wobble so streams don't
	# machine-gun one identical sample).
	if item_id == Economy.gold_id():
		UISound.play(UISound.COIN, randf_range(0.95, 1.08), -8.0)

	# Same item already showing: bump the count, pulse, keep it alive longer.
	if _active.has(item_id):
		var entry: Dictionary = _active[item_id]
		var row: PanelContainer = entry.get("row")
		if is_instance_valid(row):
			entry["count"] = int(entry["count"]) + amount
			(entry["label"] as Label).text = "%s ×%d" % [str(entry["name"]), int(entry["count"])]
			_pulse(row)
			_restart_dwell(row)
			return
		_active.erase(item_id) # freed — build fresh below

	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	var display_name: String = str(item.item_name) if item != null else fallback_name
	var icon_texture: Texture2D = item.item_icon if item != null else null

	_trim_to_max(1)

	var row: PanelContainer = PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.modulate.a = 0.0
	# The shared overlay-card look, identical to a toast: same near-black, same
	# hairline accent border, same radius. Previously a bare fill with no border
	# and no radius, which is why the pills read as a different UI from the cards
	# stacked directly above them.
	row.add_theme_stylebox_override(&"panel", PixelUI.hud_card())

	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override(&"separation", 5)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(box)

	var icon_host: Control = Control.new()
	icon_host.custom_minimum_size = Vector2(ICON_BOX, ICON_BOX)
	icon_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon_host)
	PixelIcon.mount(icon_host, icon_texture)

	var label: Label = PixelUI.hud_text(
		display_name if amount == 1 else "%s ×%d" % [display_name, amount],
		PixelUI.SIZE_CAPTION,
		PixelUI.INK
	)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(label)

	_column.add_child(row)
	# Drop the coalesce entry when the row frees so the next pickup starts fresh.
	row.tree_exited.connect(func() -> void:
		if (_active.get(item_id, {}) as Dictionary).get("row") == row:
			_active.erase(item_id))
	_active[item_id] = {"row": row, "label": label, "count": amount, "name": display_name}
	_restart_dwell(row)


## The pills currently in the lane, oldest first.
##
## Filtered rather than read straight off get_child_count(), because the lane's
## HudResizer is a child of the column too. Counting it would drop a real pill
## one early, and picking children by index would eventually free the resizer
## itself and silently kill the feed's edit handle.
func _rows() -> Array[Node]:
	var rows: Array[Node] = []
	for child: Node in _column.get_children():
		if child is PanelContainer:
			rows.append(child)
	return rows


## Drop the oldest pills until at most [member max_rows] minus [param headroom]
## remain, so the caller can add one without overflowing.
func _trim_to_max(headroom: int = 0) -> void:
	var rows: Array[Node] = _rows()
	var allowed: int = maxi(max_rows - headroom, 0)
	var index: int = 0
	while rows.size() - index > allowed:
		var oldest: Node = rows[index]
		index += 1
		_column.remove_child(oldest)
		oldest.queue_free()


## Fade in (if new), dwell, fade out, free — restartable, so repeat pickups keep
## the row alive (same pattern as Toaster's dwell).
func _restart_dwell(row: Control) -> void:
	if row.has_meta(&"tween"):
		var old: Tween = row.get_meta(&"tween")
		if old != null and old.is_valid():
			old.kill()
	var tween: Tween = create_tween()
	tween.tween_property(row, ^"modulate:a", 1.0, 0.15)
	tween.tween_interval(DWELL_S)
	tween.tween_property(row, ^"modulate:a", 0.0, 0.5)
	tween.tween_callback(row.queue_free)
	row.set_meta(&"tween", tween)


func _pulse(row: Control) -> void:
	row.pivot_offset = Vector2(0.0, row.size.y * 0.5) # grow from the left edge
	var tween: Tween = create_tween()
	tween.tween_property(row, ^"scale", Vector2(1.08, 1.08), 0.08)
	tween.tween_property(row, ^"scale", Vector2.ONE, 0.08)
