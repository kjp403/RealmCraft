extends Node
## Screenshot the REAL [FishingComboHud] through its real gather handler, in the
## states a player actually meets: building, capped, broken, and the two ways the
## bucket can stop paying for the next catch.
##
## Runs as a SCENE, windowed, in CLIENT mode:
##   godot --path . --mode=client res://tools/render_fishing_combo_previews.tscn
##
## All three parts of that are load-bearing. `-s` starts a bare SceneTree with no
## autoloads and the chip names ClientState, so under `-s` it fails to COMPILE and
## there is nothing to screenshot. `--headless` has no rasteriser. And without
## `--mode=client`, ClientState queue_frees itself in _ready and the chip's
## connect() calls land on a freed node — see render_xp_tracker_previews.gd,
## which runs the same way for the same reasons.
##
## The chip is driven by handing it gather payloads shaped exactly like the ones
## MineableNode builds, so what is rendered is the real ramp, the real colour
## lerp and the real bait copy — not a mock of them.

const CHIP_SCRIPT: GDScript = preload("res://source/client/ui/hud/fishing_combo_hud.gd")
const OUT_DIR: String = "res://previews"

## Wide enough for the whole pill plus its caption; the chip sizes itself to its
## contents, so this is headroom, not a layout.
const CELL_W: int = 300
const CELL_H: int = 46
const ROWS: int = 7
## Captured at 1x and upscaled NEAREST — the pips are 3px wide and the entire
## point is to check them individually. A filtered upscale would smear exactly
## the detail this tool exists to inspect.
const ZOOM: int = 3

## caption, streak, bait, has_bucket, break_first
const CASES: Array = [
	["first cast — no streak yet", 0, 240, true, false],
	["building — 5 catches", 5, 235, true, false],
	["building — 13 catches", 13, 227, true, false],
	["capped — 20 catches", 20, 220, true, false],
	["streak broken (flash)", 0, 214, true, true],
	["bucket ran dry", 3, 0, true, false],
	["bucket left in the bank", 0, 412, false, false],
]

var _sv: SubViewport


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var out_abs: String = ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_abs)

	_sv = SubViewport.new()
	_sv.size = Vector2i(CELL_W, CELL_H * ROWS)
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_sv.transparent_bg = false
	_sv.disable_3d = true
	get_tree().root.add_child(_sv)

	# Stand-in for the water the chip is actually read against — the pill is
	# translucent, so judging its contrast on black would flatter it.
	var ground := ColorRect.new()
	ground.size = Vector2(_sv.size)
	ground.color = Color(0.14, 0.22, 0.28)
	_sv.add_child(ground)

	for i: int in range(CASES.size()):
		var case: Array = CASES[i]
		var chip: PanelContainer = CHIP_SCRIPT.new()
		# run_clock_chip.dress pins the pill to the TOP-RIGHT of its parent,
		# which is right for the HUD rail and useless in a grid of cells. Undone
		# per instance so each case gets its own row; nothing else is touched.
		_sv.add_child(chip)
		chip.anchor_left = 0.0
		chip.anchor_right = 0.0
		chip.grow_horizontal = Control.GROW_DIRECTION_END
		chip.position = Vector2(10.0, float(i * CELL_H) + 6.0)
		_label(str(case[0]), 10, i * CELL_H + 30)
		_drive(chip, case)

	# Long enough for the labels to lay out, short enough that the 900ms break
	# flash on case 5 is still lit.
	await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout
	await get_tree().process_frame

	# The pill sizes itself to its contents, and the rail stacks the next widget
	# directly under whatever that comes out as (HUD._place_right_rail), so the
	# measured size is the thing worth printing — not a number anyone re-derives.
	for i: int in range(CASES.size()):
		var chip_node: Control = _sv.get_child(1 + i * 2) as Control
		print("case %d %-28s size %s" % [i, str(CASES[i][0]), str(chip_node.size)])

	var dest: String = out_abs.path_join("fishing-combo-meter.png")
	var image: Image = _sv.get_texture().get_image()
	image.resize(image.get_width() * ZOOM, image.get_height() * ZOOM, Image.INTERPOLATE_NEAREST)
	image.save_png(dest)
	print("wrote ", dest)

	await _render_hover(out_abs)
	await _render_rail(out_abs)
	get_tree().quit(0)


## Where the chip actually LANDS. The upper-right rail, laid out from HUD's own
## constants and [method HUD._place_right_rail]'s own order, so this answers
## "does it collide with the minimap / the orb / an open bag" from the numbers
## the game uses rather than from a mock-up someone drew once.
##
## The minimap and the quest tracker are drawn as their exact RECTS rather than
## instantiated: the minimap needs a live map and a local player to build itself,
## and a placeholder at the right coordinates answers the geometry question
## honestly while a half-built minimap would not.
func _render_rail(out_abs: String) -> void:
	for child: Node in _sv.get_children():
		child.queue_free()
	await get_tree().process_frame

	# The BASE viewport, not a window size. project.godot stretches canvas_items
	# from 960x540, and the probe confirms a taller window only makes the HUD
	# rect TALLER — 540 is the floor, and therefore the worst case. Every rect
	# below is that floor, so this is the crowded picture, not a flattering one.
	var screen := Vector2i(960, 540)
	_sv.size = screen
	var ground := ColorRect.new()
	ground.size = Vector2(screen)
	ground.color = Color(0.16, 0.24, 0.20)
	_sv.add_child(ground)

	var right: float = float(screen.x)
	_ghost(Rect2(right - 158.0, 8.0, 150.0, 112.0), "minimap  y8..120", 8.0)
	# The compact bag, from compact_menu_host's own placement maths. It is the
	# reason the rail has only one safe slot.
	_danger(
		Rect2(
			right - CompactPanelProbe.WIDTH - 12.0,
			float(screen.y) - CompactPanelProbe.HEIGHT - 48.0,
			CompactPanelProbe.WIDTH, CompactPanelProbe.HEIGHT
		),
		"open bag  y%d..  x%d.." % [
			int(float(screen.y) - CompactPanelProbe.HEIGHT - 48.0),
			int(right - CompactPanelProbe.WIDTH - 12.0),
		]
	)

	# Where the orb sits TODAY, and where slot-one stacking would push it.
	var orb_now: float = HUD.RIGHT_RAIL_TOP
	var orb_pushed: float = HUD.RIGHT_RAIL_TOP + 24.0 + HUD.RIGHT_RAIL_GAP
	_ghost(Rect2(right - HUD.RIGHT_RAIL_MARGIN - 48.0, orb_pushed, 48.0, 48.0),
		"orb if stacked  y%d..%d  (under the bag)" % [
			int(orb_pushed), int(orb_pushed + 48.0)],
		orb_pushed + 50.0)

	var orb: Control = load(
		"res://source/client/ui/hud/xp_tracker/xp_tracker_hud.tscn"
	).instantiate() as Control
	_sv.add_child(orb)
	orb.position = Vector2(right - HUD.RIGHT_RAIL_MARGIN - 48.0, orb_now)
	orb.modulate.a = 1.0
	orb.visible = true

	# The XP floating numbers, whose anchor is tuned to top out at y132 clear of
	# the minimap (XpTrackerHud.DROPS_ANCHOR). They own the space immediately
	# left of the orb, which is why the meter cannot simply sit beside it.
	var drop_top: float = orb_now + XpTrackerHud.DROPS_ANCHOR.y - 26.0
	_ghost(Rect2(right - HUD.RIGHT_RAIL_MARGIN - 48.0 - 6.0 - 70.0, drop_top,
		70.0, 26.0 + 16.0), "XP drops  y%d.." % int(drop_top), drop_top - 12.0)

	# The ability bar the meter rides above, from hud.tscn's own offsets.
	_ghost(Rect2(float(screen.x) * 0.5 - 100.0, float(screen.y) - 104.0, 200.0, 44.0),
		"ability bar  y%d..%d" % [screen.y - 104, screen.y - 60],
		float(screen.y) - 104.0 - 12.0)

	# Where the meter actually lands. Added as a real child of a full-rect parent
	# so its own anchoring does the placing — if _place() is wrong, this picture
	# is wrong in the same way, which is the point of rendering it at all.
	var stage := Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sv.add_child(stage)
	var chip: PanelContainer = CHIP_SCRIPT.new()
	stage.add_child(chip)
	_drive(chip, CASES[2])
	await get_tree().process_frame
	_caption("combo meter  y%d..%d  x%d..%d" % [
		int(chip.position.y), int(chip.position.y + chip.size.y),
		int(chip.position.x), int(chip.position.x + chip.size.x),
	], chip.position.x, chip.position.y - 12.0)

	await get_tree().process_frame
	await get_tree().process_frame
	var dest: String = out_abs.path_join("fishing-combo-rail.png")
	var image: Image = _sv.get_texture().get_image()
	image.save_png(dest)
	print("wrote ", dest)


## The bag's own numbers, named here so this picture cannot drift from it.
class CompactPanelProbe:
	const WIDTH: float = 224.0
	const HEIGHT: float = 330.0


## A filled warning rect for a panel that BURIES what it covers, as opposed to
## _ghost's hairline outline for one that merely sits somewhere.
func _danger(rect: Rect2, text: String) -> void:
	var box := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.85, 0.30, 0.28, 0.22)
	style.border_color = Color(1.0, 0.42, 0.38, 0.75)
	style.set_border_width_all(1)
	box.add_theme_stylebox_override(&"panel", style)
	box.position = rect.position
	box.size = rect.size
	_sv.add_child(box)
	_caption(text, rect.position.x + 4.0, rect.position.y + 4.0)


## A hairline outline standing in for a widget this tool cannot build — the
## minimap needs a live map and a local player, the quest tracker needs quests.
## Their RECTS are the part this picture is about, and those are exact.
func _ghost(rect: Rect2, text: String, caption_y: float) -> void:
	var box := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 0.05)
	style.border_color = Color(1.0, 1.0, 1.0, 0.28)
	style.set_border_width_all(1)
	box.add_theme_stylebox_override(&"panel", style)
	box.position = rect.position
	box.size = rect.size
	_sv.add_child(box)
	_caption(text, rect.position.x + 4.0, caption_y)


func _caption(text: String, x: float, y: float) -> void:
	var label: Label = PixelUI.text(text, PixelUI.SIZE_TINY, PixelUI.INK_DIM)
	label.position = Vector2(x, y)
	_sv.add_child(label)


## The other half of the fix: the bag's hover card for the bucket itself. Drawn
## from [method ItemTooltip.hover_text] — the exact string compact_menu_host puts
## in `tooltip_text` — so what is checked here is the copy players read, not a
## re-typed approximation of it. Godot draws the real hover in an OS-level popup
## that a SubViewport cannot capture, which is why it is laid into a label.
func _render_hover(out_abs: String) -> void:
	for child: Node in _sv.get_children():
		child.queue_free()
	await get_tree().process_frame

	_sv.size = Vector2i(CELL_W, 150)
	var ground := ColorRect.new()
	ground.size = Vector2(_sv.size)
	ground.color = Color(0.14, 0.22, 0.28)
	_sv.add_child(ground)

	var bucket: Item = ContentRegistryHub.load_by_id(
		&"items", BaitBucket.bucket_id()
	) as Item
	var y: float = 8.0
	# Owned-and-stocked, and the unowned shop case where the stored line must not
	# appear at all rather than printing a zero the player cannot act on.
	for case: Array in [[true, 1842], [false, 0]] as Array:
		ClientState.has_bait_bucket = bool(case[0])
		ClientState.stored_bait = int(case[1])
		ClientState.bait_capacity = BaitBucket.MAX_STORED
		var card := PanelContainer.new()
		card.add_theme_stylebox_override(&"panel", PixelUI.hud_card(8, 6))
		card.position = Vector2(10.0, y)
		_sv.add_child(card)
		var text: Label = PixelUI.hud_label(
			Label.new(), PixelUI.SIZE_TINY,
			PixelUI.INK if bool(case[0]) else PixelUI.INK_DIM
		)
		text.text = ItemTooltip.hover_text(bucket)
		card.add_child(text)
		await get_tree().process_frame
		y += card.size.y + 10.0

	await get_tree().process_frame
	var dest: String = out_abs.path_join("bait-bucket-hover.png")
	var image: Image = _sv.get_texture().get_image()
	image.resize(image.get_width() * ZOOM, image.get_height() * ZOOM, Image.INTERPOLATE_NEAREST)
	image.save_png(dest)
	print("wrote ", dest)


## Feed the chip a gather payload shaped exactly like MineableNode's, through the
## same handler the live push lands in. The bucket mirror is set on ClientState
## first, because that is where the chip reads it from — the payload's bait block
## goes through ClientState in game too.
func _drive(chip: PanelContainer, case: Array) -> void:
	var streak: int = int(case[1])
	ClientState.stored_bait = int(case[2])
	ClientState.has_bait_bucket = bool(case[3])
	ClientState.bait_capacity = BaitBucket.MAX_STORED

	# The break case has to arrive as a TRANSITION: the chip flashes on a streak
	# going to zero, not on a zero streak, so a single push could never show it.
	if bool(case[4]):
		chip.call(&"_on_gather", _payload(9))
	chip.call(&"_on_gather", _payload(streak))


func _payload(streak: int) -> Dictionary:
	return {
		"job": "fishing",
		"combo_streak": streak,
		"combo_multiplier": FishingComboManager.multiplier_for(streak),
	}


func _label(text: String, x: int, y: int) -> void:
	var label: Label = PixelUI.text(text, PixelUI.SIZE_TINY, PixelUI.INK_DIM)
	label.position = Vector2(float(x), float(y))
	_sv.add_child(label)
