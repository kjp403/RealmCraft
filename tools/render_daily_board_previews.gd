extends Node
## Screenshot the REAL Daily Skilling Board and the REAL chest reward window at
## the shipping 960x540 client size, driven by hand-built payloads.
##
## Runs as a SCENE, not a `-s` tool, and windowed (headless has no rasteriser):
##   godot --path . --mode=client res://tools/render_daily_board_previews.tscn
##
## The scene route is not a style choice: `-s` starts a bare SceneTree with no
## autoloads, and both of these scripts reference Client / ClientState / Toaster /
## UniversalChestManager — under `-s` they fail to COMPILE, so there is nothing
## to screenshot. `--mode=client` keeps the Client autoload alive.
##
## Both UIs are fed the exact payload shapes their servers send, so what renders
## here is what the client will draw. Nothing is mocked but the transport.

const BOARD_SCENE: String = "res://source/client/ui/menus/daily_board/daily_board_menu.tscn"
const WINDOW_SCRIPT: String = "res://source/client/ui/overlays/chest_reward_window.gd"
const OUT_DIR: String = "res://previews"
const W: int = 960
const H: int = 540

var _sv: SubViewport
var _out_abs: String


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	_out_abs = ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(_out_abs)

	_sv = SubViewport.new()
	_sv.size = Vector2i(W, H)
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_sv.transparent_bg = false
	_sv.disable_3d = true
	get_tree().root.add_child(_sv)

	# Stand-in for the world behind the menu so the shell's dim backdrop reads the
	# way it does over a real map rather than over pure black.
	var ground: ColorRect = ColorRect.new()
	ground.size = Vector2(W, H)
	ground.color = Color(0.20, 0.26, 0.20)
	_sv.add_child(ground)

	await _render_board()
	await _render_reward_window()
	await _render_hunt_chest()

	get_tree().quit(0)


# --- Daily board -------------------------------------------------------------

func _render_board() -> void:
	var scene: PackedScene = load(BOARD_SCENE) as PackedScene
	if scene == null:
		push_error("Could not load %s" % BOARD_SCENE)
		return
	var board: Control = scene.instantiate() as Control
	_sv.add_child(board)
	await get_tree().process_frame
	await get_tree().process_frame

	board._apply(_board_payload())
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await _capture("daily-board.png")
	board.queue_free()
	await get_tree().process_frame


## One card in each state, which is the whole point of the shot: an untouched
## slot showing its three choices, one mid-grind, one finished and waiting to be
## opened.
func _board_payload() -> Dictionary:
	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	return {
		"ok": true,
		"refresh_at_ms": now_ms + 7 * 3600 * 1000 + 12 * 60 * 1000,
		"all_claimed": false,
		"bonus_gold": 3000,
		"bonus_xp": 250,
		"bonus_skill_xp": 2500,
		"entries": [
			{
				"slot": 0,
				"skill": "woodcutting",
				"skill_name": "Woodcutting",
				"skill_level": 52,
				"accepted": false,
				"claimed": false,
				"complete": false,
				"progress": 0,
				"required": 0,
				"progress_noun": "logs cut",
				"description": "Woodcutting - choose a difficulty",
				"options": [
					_option(0, "Easy", 35, 500, 1840, 1, "Lesser Skilling Chest", 0.001),
					_option(1, "Medium", 155, 2250, 8280, 2, "Skilling Chest", 0.005),
					_option(2, "Hard", 315, 7000, 25760, 3, "Greater Skilling Chest", 0.01),
				],
			},
			{
				"slot": 1,
				"skill": "mining",
				"skill_name": "Mining",
				"skill_level": 68,
				"accepted": true,
				"claimed": false,
				"complete": false,
				"difficulty": 2,
				"difficulty_name": "Hard",
				"chest_tier": 3,
				"chest_name": "Greater Skilling Chest",
				"outfit_chance": 0.01,
				"progress": 145,
				"required": 300,
				"progress_noun": "ore mined",
				"description": "Mining - 300 ore mined",
				"reward_gold": 7000,
				"reward_xp": 420,
				"reward_skill_xp": 31_500,
			},
			{
				"slot": 2,
				"skill": "herblore",
				"skill_name": "Herblore",
				"skill_level": 41,
				"accepted": true,
				"claimed": false,
				"complete": true,
				"difficulty": 1,
				"difficulty_name": "Medium",
				"chest_tier": 2,
				"chest_name": "Skilling Chest",
				"outfit_chance": 0.005,
				"progress": 150,
				"required": 150,
				"progress_noun": "potions brewed",
				"description": "Herblore - 150 potions brewed",
				"reward_gold": 2250,
				"reward_xp": 135,
				"reward_skill_xp": 6_120,
			},
		],
	}


func _option(
	difficulty: int, name: String, target: int, gold: int, skill_xp: int,
	tier: int, chest: String, outfit: float
) -> Dictionary:
	return {
		"difficulty": difficulty,
		"name": name,
		"target": target,
		"reward_gold": gold,
		"reward_xp": gold / 16,
		"reward_skill_xp": skill_xp,
		"chest_tier": tier,
		"chest_name": chest,
		"outfit_chance": outfit,
	}


# --- Chest reward window -----------------------------------------------------

## Driven through the REAL UniversalChestManager signals rather than by poking the
## window's internals, so this also proves the signal wiring the window depends on.
func _render_reward_window() -> void:
	# The inventory the reward window must NOT close, built as a REAL grid: the
	# same PixelUI slot texture the window's own reward rows use, real item icons
	# and real quantity labels. It is populated from a fixture rather than from a
	# live session (there is no logged-in player in a preview rig), but every
	# pixel of chrome is the shipping chrome — so this shot is a genuine check of
	# how the two panels sit together, not a grey rectangle standing in for one.
	var inventory: Control = _build_inventory_grid()
	_sv.add_child(inventory)

	var script: GDScript = load(WINDOW_SCRIPT)
	var window: Control = script.new() as Control
	_sv.add_child(window)
	await get_tree().process_frame
	await get_tree().process_frame

	window.set_target_chest(_id(&"outfit_miner_hat"), 43)

	UniversalChestManager.batch_started.emit("Greater Skilling Chest", UniversalChestManager.ALL)
	await get_tree().process_frame
	UniversalChestManager.batch_progress.emit(31, 12, [])

	for row: Dictionary in _ledger():
		UniversalChestManager.reward_granted.emit(row)
		if str(row.get("rarity", "common")) in ["rare", "ultra"]:
			UniversalChestManager.rare_granted.emit(row)
		await get_tree().process_frame

	UniversalChestManager.pending_changed.emit(_ledger(), 4)
	# Mid-run: the progress bar and the Opening... subtitle are part of what this
	# shot is checking, so it is captured BEFORE batch_finished.
	for _i: int in 6:
		await get_tree().process_frame
	await _capture("chest-reward-window.png")

	UniversalChestManager.batch_finished.emit({
		"chest": "Greater Skilling Chest",
		"opened": 43,
		"gold": 318_400,
		"items": _ledger(),
		"pending": _ledger(),
		"free_slots": 4,
	})
	for _i: int in 8:
		await get_tree().process_frame
	await _capture("chest-reward-window-done.png")
	window.queue_free()
	inventory.queue_free()


## The Boss Hunt stash in the SAME window, driven through the same manager
## signals. This shot is the check that unification actually landed: the Open
## buttons must be absent (there is nothing to open), the subtitle must read as
## stacks-against-capacity, and Claim All / Bank All must still be there.
func _render_hunt_chest() -> void:
	var inventory: Control = _build_inventory_grid()
	_sv.add_child(inventory)

	var script: GDScript = load(WINDOW_SCRIPT)
	var window: Control = script.new() as Control
	_sv.add_child(window)
	await get_tree().process_frame
	await get_tree().process_frame

	# requested 0 is the manager's "standing pile, nothing opened" signal.
	UniversalChestManager.batch_started.emit("Hunt Chest", 0)
	await get_tree().process_frame
	var stash: Array = _stash()
	UniversalChestManager.pending_changed.emit(stash, 6)
	UniversalChestManager.batch_finished.emit({
		"chest": "Hunt Chest",
		"opened": 0,
		"gold": 0,
		"items": [],
		"pending": stash,
		"free_slots": 6,
		"source": UniversalChestManager.Source.HUNT,
		"capacity": HuntChest.MAX_STACKS,
	})
	for _i: int in 8:
		await get_tree().process_frame
	await _capture("hunt-chest-window.png")
	window.queue_free()
	inventory.queue_free()


## Boss Hunt loot in STORAGE shape ({id, a}), which is what the server sends —
## deliberately not the reward-ledger shape, so the window's translation is
## exercised rather than bypassed.
func _stash() -> Array:
	var out: Array = []
	for row: Array in [
		[&"dragon_bones", 34], [&"runite_ore", 52], [&"gold_bar", 18],
		[&"starblossom", 25], [&"wraithsilk_cloth", 9], [&"behemoth_gem", 2],
	]:
		var id: int = _id(row[0])
		if id > 0:
			out.append({"id": id, "a": int(row[1])})
	return out


## A 6x4 inventory grid in the shipping pixel chrome.
func _build_inventory_grid() -> Control:
	const COLS: int = 6
	const ROWS: int = 4
	const SLOT: int = 44

	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(28, 96)
	PixelUI.make_pixel_perfect(panel)
	PixelUI.panel(panel, "frame_stone", 10)

	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	panel.add_child(col)
	col.add_child(PixelUI.text("Backpack", PixelUI.SIZE_HEADING, PixelUI.INK_GOLD))

	var grid: GridContainer = GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override(&"h_separation", 4)
	grid.add_theme_constant_override(&"v_separation", 4)
	col.add_child(grid)

	# slug -> stack size. A working bag mid-session, including the chests the
	# Open 1 / 5 / All buttons act on.
	var fixture: Array = [
		[&"wood_silver_small", 43], [&"iron_ore", 214], [&"coal_ore", 98],
		[&"oak_log", 61], [&"healing_herb", 27], [&"bone", 44],
		[&"copper_ore", 180], [&"tin_ore", 175], [&"iron_bar", 32],
		[&"maple_log", 18], [&"trout", 9], [&"frostpetal", 12],
		[&"gem_vital_high", 3], [&"mithril_ore", 21], [&"silver_ore", 40],
		[&"steel_bar", 15], [&"yew_log", 6], [&"moonbloom", 4],
	]
	for i: int in COLS * ROWS:
		var cell: PanelContainer = PanelContainer.new()
		cell.custom_minimum_size = Vector2(SLOT, SLOT)
		cell.add_theme_stylebox_override(&"panel", PixelUI.slot_style())
		grid.add_child(cell)
		if i >= fixture.size():
			continue
		var slug: StringName = fixture[i][0]
		var item: Item = ContentRegistryHub.load_by_slug(&"items", slug) as Item
		if item == null or item.item_icon == null:
			continue
		var host: CenterContainer = CenterContainer.new()
		cell.add_child(host)
		PixelIcon.mount(host, item.item_icon)
		# Quantity, bottom-right, over the icon — the standard inventory read.
		var qty: Label = PixelUI.text(str(int(fixture[i][1])), PixelUI.SIZE_TINY, PixelUI.INK_GOLD)
		qty.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		qty.offset_left = -SLOT + 4
		qty.offset_top = -14
		qty.offset_right = -3
		qty.offset_bottom = -2
		qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(qty)
	return panel


## A believable Open All haul, including one ultra piece so the glow + particle
## path is actually exercised by the shot.
func _ledger() -> Array:
	return [
		_row(&"iron_ore", "Iron Ore", 1_240, "common"),
		_row(&"coal_ore", "Coal Ore", 860, "common"),
		_row(&"mithril_ore", "Mithril Ore", 214, "common"),
		_row(&"runite_ore", "Runite Ore", 61, "uncommon"),
		_row(&"gem_vital_high", "Pristine Vital Gem", 3, "rare"),
		_row(&"outfit_miner_hat", "Prospector's Helm", 1, "ultra"),
	]


func _row(slug: StringName, name: String, amount: int, rarity: String) -> Dictionary:
	return {"id": _id(slug), "amount": amount, "name": name, "rarity": rarity}


func _id(slug: StringName) -> int:
	return ContentRegistryHub.id_from_slug(&"items", slug)


# --- Capture -----------------------------------------------------------------

## Grab the SubViewport at the real client size, then upscale x2 with NEAREST so
## the pixel art stays crisp and clipping is still visible at 1:1 proportions.
##
## MUST be awaited: it waits a frame before sampling, so a bare call lets the
## caller run on and free or mutate the very thing being photographed.
func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = _sv.get_texture().get_image()
	image.resize(W * 2, H * 2, Image.INTERPOLATE_NEAREST)
	var path: String = _out_abs.path_join(file_name)
	image.save_png(path)
	print("wrote ", path)
