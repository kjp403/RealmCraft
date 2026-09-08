extends Node
## Before/after screenshots + a collision check for the boss-fight HUD: the run
## clock (BossHuntHud / DungeonHud) and the in-fight callout line (CombatAlert).
##
## Runs as a SCENE, not a `-s` tool, and windowed (headless has no rasteriser):
##   godot --path . --mode=client res://tools/render_boss_alerts.tscn
##
## `-s` starts a bare SceneTree with no autoloads, and everything here reaches
## Client / Announcer / UISound. --mode=client is what keeps those alive.
##
## It instances the REAL hud.tscn and measures the REAL node rects rather than a
## table of copied numbers, so the check cannot drift from the HUD it is
## checking. (A ghost outline is still drawn per box, because "PASS" is easier to
## trust when you can see the boxes it means.) Expect one script error out of
## chat_menu's _ready — there is no local player in a tool run; it is noise.
##
## BEFORE is not a mock either: it is the real Announcer banner (untouched by
## this change) plus the run clock's previous chrome — a 26px timer over a 14px
## detail line in a 20px-padded slab pinned at offset_top = 44 — rebuilt from the
## values this branch replaced, so the two frames are comparable.

const OUT_BEFORE: String = "res://previews/boss-alerts-before.png"
const OUT_AFTER: String = "res://previews/boss-alerts-after.png"
## The longest mechanic line in the game, on the same pill — the width case.
const OUT_LONG: String = "res://previews/boss-alerts-long.png"
## The other wearer of the same chip: a hard dungeon run.
const OUT_DUNGEON: String = "res://previews/boss-alerts-dungeon.png"
const VIEW: Vector2i = Vector2i(960, 540)

const HUD_SCENE: String = "res://source/client/ui/hud/hud.tscn"

## Source of truth for the on-demand compact panels, so their footprint cannot
## drift from the hosts themselves (same trick as render_toast_lane.gd).
const MENU_HOST: GDScript = preload("res://source/client/ui/compact_menus/compact_menu_host.gd")
const MASTERY_HOST: GDScript = preload("res://source/client/ui/compact_menus/compact_mastery_host.gd")

## Longest real callout: ossuran_arena.gd's phase-3 opener. If the pill can hold
## this one it can hold every other.
const LONGEST_CALLOUT: String = "The pillars fall. Ossuran is open — hit him with everything."

## The fight this is judged against — the 2026-09-07 report. The level suffix is
## HostileNpc's exact format, so the pill's trim is exercised for real.
const BOSS_NAME: String = "The Fungal Heart (Lv 42)"
const OLD_DETAIL: String = "The Fungal Heart  ·  18 killed  ·  3 lives"
const REMAINING_S: float = 1038.0 # 17:18

var _hud: Control
var _ghosts: Node2D
var _old_slab: PanelContainer
## Rects captured while the thing they measure was actually on screen.
var _long_rect: Rect2 = Rect2()
var _contract_rect: Rect2 = Rect2()
## The top-centre column while a boss bar is up, captured before the no-bar pass
## moves it — this is the layout the whole change is about.
var _stack_docked: String = ""
var _dungeon_rect: Rect2 = Rect2()


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	get_window().size = VIEW
	_stage()
	await _mount_hud()

	await _frame_before()
	await _frame_after()
	await _frame_long()
	await _frame_dungeon()
	await _print_no_boss_bar()
	_report()
	get_tree().quit()


# --- Frames -------------------------------------------------------------------

## What the player saw: a 34px Announcer banner across the fight, plus the run
## clock sitting inside the boss bar.
func _frame_before() -> void:
	_old_slab = _build_old_slab()
	add_child(_old_slab)
	Announcer.announce("%s enrages!" % BOSS_NAME, "", {"color": Color(1.0, 0.42, 0.38)})
	await get_tree().create_timer(1.1).timeout # let the banner finish fading in
	await _shoot(OUT_BEFORE)


## What it is now: the clock out in the right rail, and the enrage as a label in
## the reserved band under the boss bar.
func _frame_after() -> void:
	_old_slab.queue_free()
	_old_slab = null
	Announcer._cancel_current() # tool-only: clear the banner without waiting it out

	Client.data_push(&"boss_hunt.hud", {
		"active": true, "remaining_s": REMAINING_S, "boss": "The Fungal Heart",
		"kills": 18, "lives": 3,
	})
	Client.data_push(&"boss.enrage", {"name": BOSS_NAME})
	await get_tree().create_timer(0.6).timeout
	_contract_rect = _rect_of(_find_run_clock())
	_stack_docked = _describe_stack()
	await _shoot(OUT_AFTER)


## The width case: the longest mechanic callout in the game on the same pill. It
## must stay inside the viewport and clear of the HUD.
func _frame_long() -> void:
	Client.data_push(&"boss.callout", {"text": LONGEST_CALLOUT})
	await get_tree().create_timer(0.4).timeout
	# Captured here, not in _report: later frames reuse the same pill for their
	# own (shorter) lines, and the width case is what has to be judged.
	_long_rect = _rect_of(_find_alert_pill())
	await _shoot(OUT_LONG)


## The other wearer of the same chip: a HARD dungeon run, which trades the kill
## tally for the revive count. A contract and a run can never be on screen
## together, so the contract ends first.
func _frame_dungeon() -> void:
	Client.data_push(&"boss_hunt.hud", {"active": false})
	Client.data_push(&"dungeon.hud", {
		"active": true, "elapsed_s": 754.0, "has_pool": true, "revives": 1,
	})
	Client.data_push(&"boss.callout", {"text": "Searing Wound"})
	await get_tree().create_timer(0.4).timeout
	_dungeon_rect = _rect_of(_find_run_clock())
	await _shoot(OUT_DUNGEON)


## Normal play, no boss in sight: the callout band is empty but its slot is
## still reserved, which is what pushes the buff strip 32px down the screen
## everywhere. Printed rather than shot — an empty band photographs as nothing.
func _print_no_boss_bar() -> void:
	(_hud.get_node(^"BossBar") as Control).visible = false
	await get_tree().process_frame
	var band: Control = _find_alert_pill().get_parent() as Control
	var strip: Control = _hud.get_node(^"StatusBar") as Control
	print("no boss bar: callout band y %.0f..%.0f, StatusBar y %.0f..%.0f" % [
		band.global_position.y, band.global_position.y + band.size.y,
		strip.global_position.y, strip.global_position.y + strip.size.y,
	])


# --- Staging ------------------------------------------------------------------

## Ground and a boss body where the fight actually happens: dead centre, which is
## where a top-down camera always puts it. This is the field of view the HUD is
## supposed to stay out of.
func _stage() -> void:
	var ground: ColorRect = ColorRect.new()
	ground.color = Color(0.24, 0.22, 0.26)
	ground.size = VIEW
	add_child(ground)
	_blob(Vector2(480, 232), Vector2(64, 64), Color(0.72, 0.36, 0.24))
	_blob(Vector2(480, 320), Vector2(28, 40), Color(0.35, 0.55, 0.85))


## The real HUD, with the boss bar forced up: it only hides itself on _unbind,
## which needs a bound boss, so showing it by hand sticks for the whole run — and
## showing it is what makes Hud._reflow_top_center dock the callout band.
func _mount_hud() -> void:
	_hud = load(HUD_SCENE).instantiate()
	add_child(_hud)
	await get_tree().process_frame
	await get_tree().process_frame
	var boss_bar: Control = _hud.get_node(^"BossBar")
	boss_bar.modulate.a = 1.0
	boss_bar.visible = true
	await get_tree().process_frame

	_ghosts = Node2D.new()
	add_child(_ghosts)
	var boxes: Dictionary = _boxes()
	for box_name: String in boxes:
		_ghost(box_name, boxes[box_name])


## Every HUD box the new pieces have to stay out of, measured off the live nodes
## (plus the compact panels, which are placed at runtime from their hosts' own
## constants and would otherwise be missed entirely).
func _boxes() -> Dictionary:
	var boxes: Dictionary = {}
	for path: String in [
		"BossBar", "StatusBar", "AbilityBar", "ItemSlots", "BottomMenuDock",
		"NavigationMinimap", "QuestTracker",
	]:
		var node: Control = _hud.get_node_or_null(NodePath(path)) as Control
		if node != null:
			boxes[path] = Rect2(node.global_position, node.size)
	# Tallest and widest of the bottom-right panels, i.e. the worst case for
	# anything drawing in that corner.
	var panel: Vector2 = Vector2(
		maxf(MENU_HOST.PANEL_SIZE.x, MASTERY_HOST.PANEL_SIZE_PERKS.x),
		maxf(MENU_HOST.PANEL_SIZE.y, MASTERY_HOST.PANEL_SIZE_PERKS.y)
	)
	boxes["Compact panels"] = Rect2(
		Vector2(
			VIEW.x - panel.x - MENU_HOST.RIGHT_MARGIN,
			VIEW.y - panel.y - MENU_HOST.BOTTOM_CLEARANCE
		),
		panel
	)
	return boxes


func _blob(center: Vector2, blob_size: Vector2, color: Color) -> void:
	var rect: ColorRect = ColorRect.new()
	rect.color = color
	rect.size = blob_size
	rect.position = center - blob_size * 0.5
	add_child(rect)


func _ghost(box_name: String, rect: Rect2) -> void:
	var panel: Panel = Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.35, 0.35, 0.07)
	style.border_color = Color(1.0, 0.5, 0.4, 0.55)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override(&"panel", style)
	_ghosts.add_child(panel)

	var label: Label = Label.new()
	label.text = box_name
	label.add_theme_font_size_override(&"font_size", 9)
	label.add_theme_color_override(&"font_color", Color(1, 0.8, 0.8))
	label.position = rect.position + Vector2(2, 1)
	_ghosts.add_child(label)


## The run clock as it was before this branch: PanelContainer at offset_top 44,
## bg (0.06,0.06,0.08,0.55), 20px side padding, 26px timer over a 14px detail.
func _build_old_slab() -> PanelContainer:
	var chip: PanelContainer = PanelContainer.new()
	chip.anchor_left = 0.5
	chip.anchor_right = 0.5
	chip.offset_top = 44.0
	chip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	chip.grow_vertical = Control.GROW_DIRECTION_END
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.08, 0.55)
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	style.content_margin_left = 20
	style.content_margin_right = 20
	chip.add_theme_stylebox_override(&"panel", style)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 0)
	chip.add_child(box)

	var timer: Label = Label.new()
	timer.text = "17:18"
	timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer.add_theme_font_size_override(&"font_size", 26)
	box.add_child(timer)

	var detail: Label = Label.new()
	detail.text = OLD_DETAIL
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_font_size_override(&"font_size", 14)
	detail.add_theme_color_override(&"font_color", Color(1.0, 0.88, 0.6))
	box.add_child(detail)
	return chip


func _shoot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(path))
	print("wrote ", path)


# --- The check ----------------------------------------------------------------

## The visible run clock, whichever of the two is up.
func _find_run_clock() -> Control:
	for child: Node in _hud.get_children():
		if (child is DungeonHud or child is BossHuntHud) and (child as Control).visible:
			return child as Control
	return null


## The callout pill itself, not its band — the band is a full-width invisible
## rect and would "overlap" half the HUD by definition.
func _find_alert_pill() -> Control:
	for child: Node in _hud.get_children():
		var pill: Node = child.get_node_or_null(^"AlertCard")
		if pill != null:
			return pill as Control
	return null


## Measure the new pieces against the live HUD. The screenshots are for taste;
## this is the part that can fail.
func _report() -> void:
	print("boss fight: ", _stack_docked)

	var clashes: int = 0
	clashes += _check("run clock (contract)", _contract_rect, ["QuestTracker"])
	clashes += _check("run clock (hard dungeon)", _dungeon_rect, ["QuestTracker"])
	clashes += _check("callout pill (longest line)", _long_rect, [])
	if _long_rect.position.x < 0.0 or _long_rect.end.x > float(VIEW.x):
		clashes += 1
		print("    RUNS OFF SCREEN (viewport is %d wide)" % VIEW.x)
	if clashes > 0:
		print("FAIL: %d overlap(s)" % clashes)
	else:
		print("PASS: run clocks and callout are clear of the HUD")


## The top-centre column, top to bottom, so the reserved band is legible as
## numbers and not only as a screenshot.
func _describe_stack() -> String:
	var band: Control = _find_alert_pill().get_parent() as Control
	var bar: Control = _hud.get_node(^"BossBar") as Control
	var strip: Control = _hud.get_node(^"StatusBar") as Control
	return "BossBar y %.0f..%.0f, callout band y %.0f..%.0f (reserved), StatusBar y %.0f..%.0f" % [
		bar.global_position.y, bar.global_position.y + bar.size.y,
		band.global_position.y, band.global_position.y + band.size.y,
		strip.global_position.y, strip.global_position.y + strip.size.y,
	]


func _rect_of(node: Control) -> Rect2:
	return Rect2(node.global_position, node.size) if node != null else Rect2()


## [param skip] names boxes this piece is allowed to touch — the quest tracker
## shares the rail with the clock and is re-placed BY it, so the two can never be
## at the same coordinates even though the tracker's parked rect (it is authored
## hidden, at y196) says otherwise.
func _check(what: String, rect: Rect2, skip: Array) -> int:
	print("%s: %s (%.0f x %.0f px)" % [what, str(rect), rect.size.x, rect.size.y])
	var clashes: int = 0
	var boxes: Dictionary = _boxes()
	for box_name: String in boxes:
		if skip.has(box_name):
			continue
		if rect.intersects(boxes[box_name]):
			clashes += 1
			print("    OVERLAPS ", box_name, " ", boxes[box_name])
	return clashes
