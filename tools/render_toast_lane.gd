extends Node
## Screenshot + collision check for the Toaster lane against the REAL HUD footprint.
##
## Runs as a SCENE, not a `-s` tool, and windowed (headless has no rasteriser):
##   godot --path . --mode=client res://tools/render_toast_lane.tscn
##
## `-s` starts a bare SceneTree with no autoloads — Toaster IS an autoload, so there
## would be nothing to shoot. --mode=client is what makes GameMode.is_client() true;
## without it Toaster queue_frees itself in _ready and the lane renders empty.
##
## The first version of this tool only measured the STATIC rects authored in
## hud.tscn and therefore reported a clean PASS for a lane that the inventory panel
## completely covered. The panels that actually collide are the ones placed at
## RUNTIME, so the compact-menu boxes below are computed from those hosts' own
## constants rather than copied — if someone resizes a panel, this check follows.

const OUT: String = "res://previews/toast-lane.png"
## Same frame with the HUD ghosts hidden — what the player actually sees.
const OUT_CLEAN: String = "res://previews/toast-lane-clean.png"
const VIEW: Vector2i = Vector2i(960, 540)

# Source of truth for the on-demand panels, so this tool cannot drift from them.
const MENU_HOST: GDScript = preload("res://source/client/ui/compact_menus/compact_menu_host.gd")
const EQUIP_HOST: GDScript = preload("res://source/client/ui/compact_menus/compact_equipment_host.gd")
const SKILLS_HOST: GDScript = preload("res://source/client/ui/compact_menus/compact_skills_host.gd")
const MASTERY_HOST: GDScript = preload("res://source/client/ui/compact_menus/compact_mastery_host.gd")
const SETTINGS_HOST: GDScript = preload("res://source/client/ui/compact_menus/compact_settings_host.gd")

## Always-on furniture authored in hud.tscn / navigation_minimap.gd.
const STATIC_BOXES: Dictionary = {
	"NavigationMinimap": Rect2(802, 8, 150, 112),
	"StatusBar": Rect2(380, 8, 200, 32),
	"ButtonRail": Rect2(10, 10, 40, 136),
	"ItemSlots": Rect2(918, 182, 34, 176),
	"AbilityBar": Rect2(380, 436, 200, 44),
	"BottomMenuDock": Rect2(756, 504, 194, 28),
}

## Shown on demand. These are the ones the static-only version of this tool missed.
## QuestTracker / SlayerTracker are authored visible = false; Chat's full feed is
## hidden in _ready and opened from the left rail.
const DYNAMIC_BOXES: Dictionary = {
	"QuestTracker": Rect2(736, 196, 216, 28),
	"SlayerTracker": Rect2(6, 6, 220, 44),
	"Chat.FullFeed": Rect2(8, 192, 260, 340),
	"LootFeed": Rect2(12, 216, 248, 160),
}

var _boxes: Dictionary = {}
var _ghosts: Node2D


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	get_window().size = VIEW
	_boxes = _collect_boxes()

	var ground: ColorRect = ColorRect.new()
	ground.color = Color(0.29, 0.55, 0.20) # the grass the bug report was shot on
	ground.size = VIEW
	add_child(ground)

	# A dirt path, so the cards are judged over BOTH the bright and the dark ground
	# they actually have to stay readable on.
	var path: ColorRect = ColorRect.new()
	path.color = Color(0.45, 0.31, 0.18)
	path.position = Vector2(120, 0)
	path.size = Vector2(190, VIEW.y)
	add_child(path)

	_ghosts = Node2D.new()
	add_child(_ghosts)
	for box_name: String in _boxes:
		_ghost(box_name, _boxes[box_name])
	_lane_guides()

	# WORST CASE on purpose: MAX_TOASTS two-line cards, which is the tallest the
	# stack can ever get. A one-line burst would flatter the margins.
	Toaster.toast_group("Mastery", PackedStringArray(["Wand Mastery is now level 23"]), 8.0)
	for i: int in 4:
		Toaster.toast_feed(
			"kill:goblin_runt",
			"Defeated a Goblin Runt",
			PackedStringArray(["+15 Combat XP"]),
			8.0
		)
	Toaster.toast_group("Bag", PackedStringArray(["Full (28/28) — bank some items"]), 8.0)

	# Let the slide-in finish before the shutter.
	await get_tree().create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT))

	_ghosts.hide()
	await RenderingServer.frame_post_draw
	var clean: Image = get_viewport().get_texture().get_image()
	clean.save_png(ProjectSettings.globalize_path(OUT_CLEAN))

	_report()
	await _burst_check()
	get_tree().quit()


## Every compact host runs the same placement math:
##   position = (hud.size.x - PANEL_SIZE.x - RIGHT_MARGIN,
##               hud.size.y - PANEL_SIZE.y - BOTTOM_CLEARANCE)
## so one helper covers all of them, and the union is the zone a toast lane must
## never enter.
func _collect_boxes() -> Dictionary:
	var boxes: Dictionary = {}
	boxes.merge(STATIC_BOXES)
	boxes.merge(DYNAMIC_BOXES)

	var panels: Dictionary = {
		"Compact.Inventory": MENU_HOST.PANEL_SIZE,
		"Compact.Equipment": EQUIP_HOST.PANEL_SIZE,
		"Compact.Skills": SKILLS_HOST.PANEL_SIZE,
		"Compact.Mastery": MASTERY_HOST.PANEL_SIZE_PERKS,
		"Compact.Settings": SETTINGS_HOST.PANEL_SIZE,
	}
	for panel_name: String in panels:
		var panel_size: Vector2 = panels[panel_name]
		boxes[panel_name] = Rect2(
			Vector2(
				VIEW.x - panel_size.x - MENU_HOST.RIGHT_MARGIN,
				VIEW.y - panel_size.y - MENU_HOST.BOTTOM_CLEARANCE
			),
			panel_size
		)
	return boxes


## Outline of a HUD element, so an overlap is visible rather than argued about.
func _ghost(box_name: String, rect: Rect2) -> void:
	var compact: bool = box_name.begins_with("Compact.")
	var panel: Panel = Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.35, 0.35, 0.10 if compact else 0.16)
	style.border_color = Color(1.0, 0.55, 0.25, 0.9) if compact else Color(1.0, 0.4, 0.4, 0.85)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override(&"panel", style)
	_ghosts.add_child(panel)

	var label: Label = Label.new()
	label.text = box_name
	label.add_theme_font_size_override(&"font_size", 9)
	label.add_theme_color_override(&"font_color", Color(1, 0.8, 0.8))
	label.position = rect.position + Vector2(2, 1)
	_ghosts.add_child(label)


## The band Toaster is allowed to draw in, from its own constants.
func _lane_guides() -> void:
	var lane: Panel = Panel.new()
	lane.position = Vector2(Toaster.MARGIN_LEFT, Toaster.MARGIN_TOP)
	lane.size = Vector2(
		VIEW.x - Toaster.MARGIN_LEFT - Toaster.MARGIN_RIGHT,
		VIEW.y - Toaster.MARGIN_TOP - Toaster.MARGIN_BOTTOM
	)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.3, 1.0, 0.5, 0.06)
	style.border_color = Color(0.4, 1.0, 0.6, 0.5)
	style.set_border_width_all(1)
	lane.add_theme_stylebox_override(&"panel", style)
	_ghosts.add_child(lane)


## Measure every live card against every HUD box and print the verdict, so the check
## does not depend on someone squinting at the PNG.
func _report() -> void:
	var column: Node = Toaster.get_node_or_null("ToastMargin/ToastColumn")
	if column == null:
		print("FAIL: no toast column — is --mode=client set?")
		return
	print("cards on screen: ", column.get_child_count(), " (MAX_TOASTS=", Toaster.MAX_TOASTS, ")")

	var clashes: int = 0
	var stack_top: float = VIEW.y
	for slot: Node in column.get_children():
		if slot.get_child_count() == 0:
			continue
		var card: Control = slot.get_child(0)
		var rect: Rect2 = Rect2((slot as Control).global_position + card.position, card.size)
		stack_top = minf(stack_top, rect.position.y)
		print("  [%s] %s" % [str(rect), _card_text(card)])
		for box_name: String in _boxes:
			if rect.intersects(_boxes[box_name]):
				clashes += 1
				print("    OVERLAPS ", box_name, " ", _boxes[box_name])

	print("stack top y=%.0f vs MARGIN_TOP=%d — %s" % [
		stack_top, Toaster.MARGIN_TOP,
		"inside band" if stack_top >= Toaster.MARGIN_TOP else "OVERFLOWS the band"
	])
	print("FAIL: %d overlap(s)" % clashes if clashes > 0 else "PASS: lane is clear of the HUD")


## Requirement check, not a screenshot: 12 DISTINCT toasts at once (nothing to
## coalesce) must stay capped on screen and must leave nothing behind afterwards.
func _burst_check() -> void:
	var column: Node = Toaster.get_node_or_null("ToastMargin/ToastColumn")
	if column == null:
		return
	for slot: Node in column.get_children():
		slot.free()

	for i: int in 12:
		Toaster.toast("Burst notification %d" % i, 0.3)
	var peak: int = column.get_child_count()
	print("burst: 12 fired, %d nodes in column (cap %d, hard cap %d)" % [
		peak, Toaster.MAX_TOASTS, Toaster.HARD_CAP
	])

	await get_tree().create_timer(1.6).timeout
	var left: int = column.get_child_count()
	print("burst: %d node(s) left after dwell — %s" % [left, "PASS" if left == 0 else "FAIL"])
	print("burst: peak %s hard cap" % ("respects" if peak <= Toaster.HARD_CAP else "EXCEEDS"))


func _card_text(card: Control) -> String:
	var parts: PackedStringArray = []
	for label: Node in card.get_child(0).get_children():
		if label is Label:
			parts.append((label as Label).text)
	return " / ".join(parts)
