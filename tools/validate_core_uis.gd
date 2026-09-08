extends Node
## Regression guard for the PixelIcon expand_mode fix, across the UIs that mount
## icons through PixelIcon.
##
## Runs as a SCENE, windowed:
##   godot --path . --mode=client res://tools/validate_core_uis.tscn
##
## WHY NOT HEADLESS
## `--headless` has no rasteriser, so the PNGs would come out empty, and `-s` has
## no autoloads — every UI below reaches for ClientState / Client / the content
## registry and would fail to COMPILE, let alone build. Windowed + --mode=client
## is the only configuration in which these panels exist at all.
##
## WHAT IS ACTUALLY BEING CHECKED
## PixelIcon.mount sets `icon.size = art * factor` so the art fits its host. Until
## the expand_mode fix that assignment was silently overruled: TextureRect
## defaults to EXPAND_KEEP_SIZE, which reports the TEXTURE size as the control's
## minimum, and a Control is clamped UP to its minimum. So a 64x64 item icon told
## to draw at 44x44 snapped back to 64x64 and spilled out of its slot. The
## invariant that catches both that bug and its opposite (an icon collapsed to
## nothing) is:
##       0 < icon.size <= host.size,  and the icon's rect sits inside the host's.
##
## THE VACUOUS PASS IS THE REAL RISK HERE
## There is no server in this process, so a menu driven only by its normal
## `Client.request_data` path renders EMPTY — nought slots, nought icons, and a
## checker that just walks TextureRects would report a serene all-clear having
## measured nothing. So every panel below is populated by calling its OWN slot
## builder with real content ids, and a panel that yields fewer icons than
## MIN_ICONS is reported INCONCLUSIVE rather than PASS.

const OUT_DIR: String = "res://previews/"
const VIEW: Vector2i = Vector2i(960, 540)

## PNGs are saved at the native 960x540 canvas, NOT upscaled.
##
## Image.resize() on a viewport image is not trustworthy here: it invented ghost
## copies of item art at coordinates no live node occupied (verified by dumping
## every Control in the region - nothing was there, and the un-resized shot of
## the same frame was clean). Converting to RGBA8 first did not help. A preview
## whose artifacts have to be explained away is worse than a small one, so these
## ship at 1:1 and are zoomed in an image viewer.

const BANK_MENU: String = "res://source/client/ui/menus/bank/bank_menu.tscn"
const MASTERY_MENU: String = "res://source/client/ui/menus/mastery_tree/mastery_tree_menu.tscn"
## THE INVENTORY IS A SCENE PLUS A SCRIPT OVERRIDE, NOT A SCENE.
## compact_menu_host.tscn's ROOT carries compact_equipment_host.gd — instancing
## it and stopping there renders the EQUIPMENT panel with the word "Inventory" in
## its header, which is exactly the wrong-panel screenshot this tool produced on
## its first run. hud.tscn instances that scene and then replaces the script
## (ext_resource 19_ft5kn), so this has to do the same.
const INVENTORY_HOST: String = "res://source/client/ui/compact_menus/compact_menu_host.tscn"
const INVENTORY_SCRIPT: String = "res://source/client/ui/compact_menus/compact_menu_host.gd"
const TRADE_PANEL: GDScript = preload("res://source/client/ui/hud/trade_panel.gd")
const MASTERY_TREE: String = "res://source/common/gameplay/mastery/trees/sword.tres"

## Real ids out of source/common/registry/indexes/items_index.tres. Deliberately
## mixed: mat_bone is 64x64 art (the case that used to overflow), sword_bone is
## 16x48 (a tall, non-square downscale), the rest are ordinary gear.
const FIXTURE_ITEMS: Array[int] = [4, 82, 108, 106, 107, 109, 81, 83, 84, 95, 506, 507]

## Below this many mounted icons a panel has not really been exercised, so its
## result is INCONCLUSIVE rather than PASS. Nought is the dangerous number.
const MIN_ICONS: int = 4

## Float slack for the rect comparisons. PixelIcon rounds the icon's global
## position to whole pixels, so an exact containment test can be off by one.
const EPS: float = 1.5

var _failures: int = 0
var _inconclusive: int = 0


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	get_window().size = VIEW
	print("=== PixelIcon size invariants across the core UIs ===")

	var only: String = OS.get_environment("ONLY_UI")
	if only.is_empty() or only == "bank":
		await _check_ui("bank", "Bank", _build_bank)
	if only.is_empty() or only == "mastery":
		await _check_ui("mastery", "Mastery Tree", _build_mastery)
	if only.is_empty() or only == "trade":
		await _check_ui("trade", "Trade", _build_trade)
	if only.is_empty() or only == "inventory":
		await _check_ui("inventory", "Inventory", _build_inventory)
	if only.is_empty() or only == "equipment":
		await _check_ui("equipment", "Equipment", _build_equipment)

	_fit_matrix()

	print("=== %s ===" % (
		"ALL PASS" if _failures == 0 and _inconclusive == 0
		else "%d FAILURE(S), %d INCONCLUSIVE" % [_failures, _inconclusive]
	))
	get_tree().quit(1 if _failures > 0 or _inconclusive > 0 else 0)


## Build one UI, assert every PixelIcon under it, shoot a PNG, tear it down.
func _check_ui(slug: String, label: String, builder: Callable) -> void:
	print("--- %s ---" % label)
	var root: Control = Control.new()
	root.size = VIEW
	add_child(root)

	var ground: ColorRect = ColorRect.new()
	ground.size = VIEW
	ground.color = Color(0.14, 0.13, 0.17)
	root.add_child(ground)

	var expects_icons: bool = await builder.call(root)

	# PixelIcon._fit is DEFERRED and so is each compact panel's own _place_panel.
	# A panel that pins itself bottom-right therefore moves after its icons have
	# already been fitted to where it used to be, and the icons only settle on the
	# NEXT deferred fit that item_rect_changed schedules. Eight frames caught that
	# chain mid-flight and produced screenshots with icons stranded outside the
	# panel; twenty gives every deferred pass room to finish.
	for _i: int in 20:
		await get_tree().process_frame

	_assert_icons(label, root, expects_icons)

	# get_texture().get_image() reads whatever is in the framebuffer RIGHT NOW,
	# which partway through a frame is last frame's composite. Waiting on
	# frame_post_draw is the documented way to read a viewport, and it is what
	# stopped these previews showing icons at positions no live node occupied.
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = OUT_DIR + "ui-check-" + slug + ".png"
	image.save_png(ProjectSettings.globalize_path(path))
	print("  wrote %s" % path)

	# hide() BEFORE queue_free, then let two frames pass. queue_free only removes
	# the node at the end of the current idle frame and the renderer is a frame
	# behind that, so a single await left the previous panel's icons still being
	# drawn over the next one's screenshot — visible as ghost items floating
	# outside any slot in the first run of these previews.
	root.hide()
	root.queue_free()
	for _k: int in 2:
		await get_tree().process_frame


# --- The invariant -------------------------------------------------------------

## Walk every TextureRect PixelIcon mounted (they all carry the `_pixel_fit`
## meta, which is what distinguishes them from decorative TextureRects the scenes
## place themselves) and check it against its host.
func _assert_icons(label: String, root: Node, expects_icons: bool) -> void:
	var icons: Array[TextureRect] = []
	for node: Node in root.find_children("*", "TextureRect", true, false):
		var icon: TextureRect = node as TextureRect
		if icon.has_meta(&"_pixel_fit") and icon.texture != null and icon.visible:
			icons.append(icon)

	if icons.is_empty():
		if expects_icons:
			_inconclusive += 1
			print("  INCONCLUSIVE  no PixelIcon icons were built — nothing was measured")
		else:
			print("  n/a           this UI mounts no PixelIcon icons (by design)")
		return

	if expects_icons and icons.size() < MIN_ICONS:
		_inconclusive += 1
		print("  INCONCLUSIVE  only %d icon(s) built, want >= %d" % [icons.size(), MIN_ICONS])
		return

	var collapsed: int = 0
	var overflowed: int = 0
	var escaped: int = 0
	var biggest_ratio: float = 0.0

	for icon: TextureRect in icons:
		var host: Control = icon.get_parent() as Control
		if host == null:
			continue
		if icon.size.x <= 0.0 or icon.size.y <= 0.0:
			collapsed += 1
			continue
		if icon.size.x > host.size.x + EPS or icon.size.y > host.size.y + EPS:
			overflowed += 1
			print("      OVERFLOW  %s icon %s in host %s" % [
				icon.texture.resource_path.get_file(), icon.size, host.size
			])
		var host_rect: Rect2 = Rect2(host.global_position, host.size).grow(EPS)
		if not host_rect.encloses(Rect2(icon.global_position, icon.size)):
			escaped += 1
		biggest_ratio = maxf(
			biggest_ratio,
			maxf(icon.size.x / maxf(host.size.x, 1.0), icon.size.y / maxf(host.size.y, 1.0))
		)

	_report("%s: %d icons, none collapsed to 0x0" % [label, icons.size()], collapsed == 0)
	_report("%s: none exceed their slot" % label, overflowed == 0)
	_report("%s: none escape their slot rect" % label, escaped == 0)
	print("      largest icon fills %.0f%% of its slot" % [biggest_ratio * 100.0])


# --- Builders ------------------------------------------------------------------
# Each returns whether the UI is EXPECTED to contain PixelIcon icons, so that a
# panel which legitimately has none is not confused with one that failed to fill.

## Bank. Populated through its own _build_slot rather than through a server
## round trip, so the slots are the real 44x44 buttons with real mounted art.
func _build_bank(root: Control) -> bool:
	var menu: Control = (load(BANK_MENU) as PackedScene).instantiate()
	root.add_child(menu)
	menu.show()
	await get_tree().process_frame

	var store: Dictionary = {}
	for index: int in FIXTURE_ITEMS.size():
		store[index + 1] = {"id": FIXTURE_ITEMS[index], "a": 1 + index * 7}

	var grid := GridContainer.new()
	grid.columns = 6
	grid.position = Vector2(180, 150)
	grid.add_theme_constant_override(&"h_separation", 4)
	grid.add_theme_constant_override(&"v_separation", 4)
	root.add_child(grid)
	for uid: int in store:
		grid.add_child(menu.call(&"_build_slot", store, uid, true))
	return true


## Mastery tree. Its tiles come from a LOCAL .tres, so this one needs no fixture
## beyond a progress dictionary shaped the way MasteryService would send it.
func _build_mastery(root: Control) -> bool:
	var menu: Control = (load(MASTERY_MENU) as PackedScene).instantiate()
	root.add_child(menu)
	menu.show()
	await get_tree().process_frame

	var tree: MasteryTreeResource = load(MASTERY_TREE) as MasteryTreeResource
	if tree == null or tree.nodes.is_empty():
		print("  (could not load %s)" % MASTERY_TREE)
		return true

	# Everything owned and max level, so tiles render lit rather than dimmed —
	# the icon is mounted either way, but a lit tile is the readable screenshot.
	var info: Dictionary = {
		"spent": tree.nodes.map(func(n: MasteryNode) -> String: return String(n.id)),
		"loadout": [],
		"level": 99,
		"points": 99,
	}

	var grid := GridContainer.new()
	grid.columns = 8
	grid.position = Vector2(180, 150)
	grid.add_theme_constant_override(&"h_separation", 6)
	grid.add_theme_constant_override(&"v_separation", 6)
	root.add_child(grid)
	for node: MasteryNode in tree.nodes:
		grid.add_child(menu.call(&"_make_tile", node, tree, info, Color(0.6, 0.8, 1.0)))
	return true


## Trade. The panel lives as a bare Control inside hud.tscn (no scene of its
## own), so the script is instanced directly; _make_slot resolves its own items
## out of the content registry and needs no trade session.
func _build_trade(root: Control) -> bool:
	var panel: Control = TRADE_PANEL.new()
	root.add_child(panel)
	await get_tree().process_frame

	var grid := GridContainer.new()
	grid.columns = 6
	grid.position = Vector2(180, 150)
	grid.add_theme_constant_override(&"h_separation", 5)
	grid.add_theme_constant_override(&"v_separation", 5)
	root.add_child(grid)
	for index: int in FIXTURE_ITEMS.size():
		grid.add_child(panel.call(&"_make_slot", FIXTURE_ITEMS[index], 1 + index * 3, true))
	return true


## Inventory. Included because it was on the review list, and the answer is that
## the expand_mode change CANNOT reach it: compact_menu_host draws stacks with
## Button.icon plus expand_icon / icon_max_width, never through PixelIcon. It is
## still instanced and shot so that claim is visible rather than asserted.
func _build_inventory(root: Control) -> bool:
	var host: Control = (load(INVENTORY_HOST) as PackedScene).instantiate()
	# The script swap must happen BEFORE the node enters the tree, so _ready runs
	# from compact_menu_host.gd rather than from the scene's authored script.
	host.set_script(load(INVENTORY_SCRIPT))
	root.add_child(host)
	host.show()
	return false


## Equipment. NOT on the original review list, and it should have been: the panel
## that compact_menu_host.tscn actually authors mounts a PixelIcon per slot and is
## therefore inside the expand_mode blast radius. Its slots are filled the way
## _refresh does it — PixelIcon.set_art on the icons mount() already made — rather
## than by faking an equipment payload.
func _build_equipment(root: Control) -> bool:
	var host: Control = (load(INVENTORY_HOST) as PackedScene).instantiate()
	root.add_child(host)
	host.show()
	await get_tree().process_frame

	var pixels: Dictionary = host.get(&"_slot_pixels")
	if pixels == null or pixels.is_empty():
		return true # no slots built -> INCONCLUSIVE, which is the honest result
	var index: int = 0
	for slot_key: Variant in pixels:
		var item: Item = ContentRegistryHub.load_by_id(
			&"items", FIXTURE_ITEMS[index % FIXTURE_ITEMS.size()]
		) as Item
		index += 1
		if item != null:
			PixelIcon.set_art(pixels[slot_key] as TextureRect, item.item_icon)
	return true


# --- Direct fit matrix ----------------------------------------------------------

## The UIs above are four of the twelve PixelIcon call sites. Rather than stand
## up the other eight — each with its own fixture problem — this drives
## PixelIcon.mount over the (art size x host size) combinations those call sites
## actually use, which is the whole blast radius of the expand_mode change in one
## deterministic pass.
func _fit_matrix() -> void:
	print("--- fit matrix (every host size in the codebase) ---")
	var hosts: Array[Dictionary] = [
		{"name": "loot feed", "box": Vector2(24, 24)},
		{"name": "HUD quickslot (ItemSlots)", "box": Vector2(32, 32)},
		{"name": "compact menu slot", "box": Vector2(36, 36)},
		{"name": "compact equipment slot", "box": Vector2(38, 38)},
		{"name": "bank / mastery slot", "box": Vector2(44, 44)},
		{"name": "trade slot", "box": Vector2(54, 54)},
		{"name": "HUD rail button (inset 4)", "box": Vector2(40, 40)},
	]

	var probe: Control = Control.new()
	add_child(probe)

	var bad: int = 0
	var checked: int = 0
	for entry: Dictionary in hosts:
		var box: Vector2 = entry["box"]
		for item_id: int in FIXTURE_ITEMS:
			var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
			if item == null or item.item_icon == null:
				continue
			var host: Control = Control.new()
			host.custom_minimum_size = box
			host.size = box
			probe.add_child(host)
			var icon: TextureRect = PixelIcon.mount(host, item.item_icon)
			# mount fits deferred; force it now so this stays a single pass.
			(icon.get_meta(&"_pixel_fit") as Callable).call()
			checked += 1
			if (
				icon.size.x <= 0.0 or icon.size.y <= 0.0
				or icon.size.x > box.x + EPS or icon.size.y > box.y + EPS
			):
				bad += 1
				print("      BAD  %s art %s in %s host -> %s" % [
					item.item_icon.resource_path.get_file(),
					item.item_icon.get_size(), box, icon.size
				])
			host.queue_free()

	_report("fit matrix: %d combinations, all inside their host" % checked, bad == 0)
	probe.queue_free()


func _report(what: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print(("  PASS  " if ok else "  FAIL  ") + what)
