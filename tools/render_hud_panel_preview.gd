extends Node
## Screenshot of the reworked HUD instrument panel: the keybind tiles (LMB / Q /
## E / R / C plus the 1-5 quick rail) drawn with the REAL HudSlotStyle faces, and the
## REAL health / mana / prayer bar scenes with their ink-in-water fills.
##
## Runs as a SCENE, not a `-s` tool, and windowed (headless has no rasteriser):
##   godot --path . --mode=client res://tools/render_hud_panel_preview.tscn
##
## `-s` starts a bare SceneTree with no autoloads, and the bar scripts reference
## ClientState — under `-s` they fail to COMPILE, so there is nothing to shoot.
## The bars normally read their values off the local player; there is no server
## here, so a fixture is pushed straight into the ProgressBars instead.
##
## The second tile row shows the LIVE (key-held) face, and the health bar is left
## mid-chip so the red damage residue behind the green is visible.

const SLOT_STYLE: GDScript = preload("res://source/client/ui/hud/hud_slot_style.gd")
const HEALTH: String = "res://source/client/ui/hud/health_bar/health_bar.tscn"
const MANA: String = "res://source/client/ui/hud/mana_bar/mana_bar.tscn"
const PRAYER: String = "res://source/client/ui/hud/prayer_bar/prayer_bar.tscn"
const OUT: String = "res://previews/hud-panel.png"

const TILE: Vector2 = Vector2(36, 44) # AbilityBar.TILE_SIZE
const TILE_GAP: int = 5               # hud.tscn AbilityBar separation
const QUICK: Vector2 = Vector2(32, 32)
const QUICK_GAP: int = 4
const BAR_WIDTH: float = 200.0
## The HUD is pixel-art small; render at 2x so the 1px frames survive the PNG.
const ZOOM: int = 2
const VIEW: Vector2i = Vector2i(420, 250)


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var root: Control = Control.new()
	root.size = VIEW
	root.scale = Vector2(ZOOM, ZOOM)
	var ground: ColorRect = ColorRect.new()
	ground.color = Color(0.16, 0.11, 0.08) # the tavern planks the HUD sits on
	ground.size = VIEW
	root.add_child(ground)
	add_child(root)

	var centre_x: float = VIEW.x * 0.5
	_ability_row(root, centre_x, 26.0, -1)
	_bars(root, centre_x, 84.0)
	_label(root, Vector2(18.0, 156.0), "key held ->", 9)
	_ability_row(root, centre_x, 166.0, 2) # E held down
	_quick_rail(root, VIEW.x - 8.0 - QUICK.x, 26.0, 1)

	# Two frames: one for the bar scenes to run _ready, one to draw them.
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT))
	print("wrote ", OUT, "  ability row = ", 5 * TILE.x + 4 * TILE_GAP, "px vs ", BAR_WIDTH, "px bars")
	get_tree().quit()


## [param live_index] lights that tile with the key-held face (-1 = all idle).
func _ability_row(root: Control, centre_x: float, top: float, live_index: int) -> void:
	var keys: PackedStringArray = ["LMB", "Q", "E", "R", "C"]
	var total: float = keys.size() * TILE.x + (keys.size() - 1) * TILE_GAP
	var x: float = centre_x - total * 0.5
	for i: int in keys.size():
		var tile: Button = Button.new()
		SLOT_STYLE.apply(tile)
		tile.size = TILE
		tile.position = Vector2(x, top)
		tile.text = ["Bolt", "MR", "Bw", "PB", "As"][i]
		tile.add_theme_font_size_override(&"font_size", 12)
		root.add_child(tile)
		if i == live_index:
			SLOT_STYLE.set_live(tile, true)
		root.add_child(_corner(Vector2(x + 6, top + 3), keys[i], 9, Color(0.75, 0.78, 0.85)))
		root.add_child(_corner(
			Vector2(x + TILE.x - 17, top + TILE.y - 17), "12", 10, Color(0.45, 0.75, 1.0)
		))
		x += TILE.x + TILE_GAP


## The three REAL bar scenes, stacked exactly as hud.tscn stacks them: each one
## anchors to the bottom of its parent, so the host Control's height is what puts
## them in the right places relative to each other.
func _bars(root: Control, centre_x: float, top: float) -> void:
	var host: Control = Control.new()
	host.size = Vector2(BAR_WIDTH, 60.0)
	host.position = Vector2(centre_x - BAR_WIDTH * 0.5, top)
	root.add_child(host)

	var health: Control = (load(HEALTH) as PackedScene).instantiate() as Control
	host.add_child(health)
	var mana: Control = (load(MANA) as PackedScene).instantiate() as Control
	host.add_child(mana)
	var prayer: Control = (load(PRAYER) as PackedScene).instantiate() as Control
	host.add_child(prayer)

	# A mid-fight fixture: hurt but not dying, half mana spent, prayer draining.
	# The chip sits ABOVE the main value so the red damage residue shows.
	_fill(health.get_node("ChipBar") as ProgressBar, 430.0, 550.0)
	_fill(health.get_node("MainBar") as ProgressBar, 330.0, 550.0)
	(health.get_node("MainBar/Label") as Label).text = "330 / 550"
	_fill(mana.get_node("ProgressBar") as ProgressBar, 450.0, 676.0)
	(mana.get_node("ProgressBar/Label") as Label).text = "450 / 676"
	_fill(prayer.get_node("ProgressBar") as ProgressBar, 36.0, 80.0)
	(prayer.get_node("ProgressBar/Label") as Label).text = "36 / 80"


func _fill(bar: ProgressBar, value: float, maximum: float) -> void:
	bar.max_value = maximum
	bar.value = value


## [param live_index] lights that slot with the flash face (-1 = all idle).
func _quick_rail(root: Control, left: float, top: float, live_index: int) -> void:
	for i: int in 5:
		var slot: Button = Button.new()
		SLOT_STYLE.apply(slot)
		slot.size = QUICK
		slot.position = Vector2(left, top + i * (QUICK.y + QUICK_GAP))
		root.add_child(slot)
		if i == live_index:
			SLOT_STYLE.set_live(slot, true)
		root.add_child(_corner(
			Vector2(left + 5, top + i * (QUICK.y + QUICK_GAP) + 2),
			str(i + 1), 8, Color(0.75, 0.78, 0.85)
		))


func _label(root: Control, at: Vector2, text: String, font_size: int) -> void:
	root.add_child(_corner(at, text, font_size, Color(0.70, 0.72, 0.78)))


func _corner(at: Vector2, text: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	return label
