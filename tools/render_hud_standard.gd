extends Node
## Screenshot of the four HUD overlay surfaces after the standardisation pass:
## the top-left button rail, the loot feed, the quest tracker and the party
## roster, each built by its REAL script so this cannot drift from shipping code.
##
## Runs as a SCENE, not a `-s` tool, and windowed (headless has no rasteriser):
##   godot --path . --mode=client res://tools/render_hud_standard.tscn
##
## `-s` starts a bare SceneTree with no autoloads; every script below reaches for
## ClientState / Client / InstanceClient, so under `-s` they fail to COMPILE and
## there is nothing to shoot. --mode=client is what keeps the client-only
## autoloads (Toaster, LootFeed) from queue_free()ing themselves in _ready.
##
## There is no server here, so each panel is driven by pushing a fixture straight
## into its render entry point rather than by waiting on a request.

const OUT: String = "res://previews/hud-standard.png"
## The same frame with HudLayout unlocked, so the edit chrome can be reviewed
## without having to run the game and press L.
const OUT_EDIT: String = "res://previews/hud-resize-mode.png"
const VIEW: Vector2i = Vector2i(960, 540)

## PNGs are saved at the native 960x540 canvas, NOT upscaled.
##
## Image.resize() on a viewport image is not trustworthy here: it invented ghost
## copies of item art at coordinates no live node occupied (verified by dumping
## every Control in the region - nothing was there, and the un-resized shot of
## the same frame was clean). Converting to RGBA8 first did not help. A preview
## whose artifacts have to be explained away is worse than a small one, so these
## ship at 1:1 and are zoomed in an image viewer.


const QUEST_TRACKER: GDScript = preload("res://source/client/ui/hud/quest_tracker.gd")
const PARTY_HUD: GDScript = preload("res://source/client/ui/hud/party_hud.gd")


func _ready() -> void:
	call_deferred(&"_go")


## Whoever runs this tool has their own saved HUD sizes, and the resizers restore
## them on attach — so without stashing them the preview would show that person's
## layout rather than the shipped defaults it is supposed to document. Put back
## in _restore_layout before quitting.
var _saved_layout: Dictionary = {}


func _go() -> void:
	_saved_layout = (ClientState.settings.data.get(
		HudLayout.SETTING_SECTION, {}
	) as Dictionary).duplicate(true)
	HudLayout.reset()

	get_window().size = VIEW
	var root: Control = Control.new()
	root.size = VIEW
	add_child(root)

	# A bright, busy ground. The whole point of the overlay-card standard is that
	# it stays legible over the WORLD, so a flat dark backdrop would flatter it.
	var ground: ColorRect = ColorRect.new()
	ground.size = VIEW
	ground.color = Color(0.30, 0.42, 0.20)
	root.add_child(ground)
	for i: int in range(0, VIEW.x, 32):
		for j: int in range(0, VIEW.y, 32):
			if (i / 32 + j / 32) % 2 == 0:
				continue
			var tile: ColorRect = ColorRect.new()
			tile.position = Vector2(i, j)
			tile.size = Vector2(32, 32)
			tile.color = Color(0.36, 0.50, 0.24)
			root.add_child(tile)

	_rail(root)
	_loot(root)
	_party(root)
	await _quest(root)

	# Containers settle over several frames (PixelIcon._fit is deferred, and the
	# quest tracker re-measures once its wrapped labels know their width), so give
	# the layout real time before the shot rather than a single frame.
	for _i: int in 8:
		await get_tree().process_frame

	HudLayout.set_locked(true)
	await get_tree().process_frame
	var image: Image = get_viewport().get_texture().get_image()
	_report(root)
	image.save_png(ProjectSettings.globalize_path(OUT))
	print("wrote ", OUT, " ", image.get_width(), "x", image.get_height())

	# Second pass: edit mode. Same scene, same sizes — only HudLayout.locked
	# differs, which is the whole point of the comparison.
	HudLayout.set_locked(false)
	for _j: int in 3:
		await get_tree().process_frame
	var edit: Image = get_viewport().get_texture().get_image()
	edit.save_png(ProjectSettings.globalize_path(OUT_EDIT))
	print("wrote ", OUT_EDIT)
	HudLayout.set_locked(true)
	_restore_layout()
	get_tree().quit()


func _restore_layout() -> void:
	ClientState.settings.data[HudLayout.SETTING_SECTION] = _saved_layout
	ClientState.settings.save()


## Print the measured rect of every surface, so a regression shows up as numbers
## in CI output and not only as something that looks off in a PNG.
func _report(root: Control) -> void:
	print("--- measured (960x540 client space) ---")
	for node: Node in root.get_children():
		if node is PanelContainer or node is VBoxContainer:
			var c: Control = node as Control
			print("  %-14s pos %s  size %s" % [node.get_class(), c.position, c.size])
	var column: Node = LootFeed.get_child(0)
	if column is Control:
		print("  LootFeed       pos %s  size %s" % [
			(column as Control).global_position, (column as Control).size
		])
		for row: Node in column.get_children():
			# PanelContainer only: the lane also holds its HudResizer.
			if row is PanelContainer:
				print("      row size %s" % [(row as Control).size])
				for host: Node in (row.get_child(0) as Node).get_children():
					if host is Control and host.get_child_count() > 0:
						var art: Control = host.get_child(0) as Control
						print("        host size %s -> icon size %s pos %s" % [
							(host as Control).size, art.size, art.global_position
						])


## Element 1 — the rail, rebuilt with the same calls hud.gd now makes.
func _rail(root: Control) -> void:
	var rail: VBoxContainer = VBoxContainer.new()
	rail.position = Vector2(10, 10)
	rail.add_theme_constant_override(&"separation", 8)
	root.add_child(rail)
	var icons: Array[String] = [
		"res://assets/sprites/ui/menu_icons_shadow/32px/message.png",
		"res://assets/sprites/ui/menu_icons_shadow/32px/three_dots_vertical.png",
	]
	for path: String in icons:
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(40, 40)
		button.size_flags_horizontal = 0
		button.size_flags_vertical = 0
		button.icon = load(path) as Texture2D
		rail.add_child(button)
		PixelUI.hud_icon_button(button, 4)
		PixelIcon.from_button(button, 4.0)


## Element 2 — real LootFeed rows. add_item() resolves through the items
## registry; ids that miss fall back to the name passed in, which is exactly the
## path a content mid-refresh takes, so it is a fair render either way.
func _loot(_root: Control) -> void:
	# Real ids out of items_index.tres, so the 24px icon box is exercised with the
	# actual art rather than with the null-texture path.
	LootFeed.add_item(4, 4, "Bone")          # bone
	LootFeed.add_item(82, 1, "Bone Sword")   # sword_bone.item
	LootFeed.add_item(108, 2, "Forest Hide") # hide_forest


## Element 3 — the real QuestTracker, pinned into the right rail exactly as
## Hud._ready + Hud._place_right_rail do it, then handed a fixture quest.
func _quest(root: Control) -> void:
	var tracker: PanelContainer = QUEST_TRACKER.new()
	# hud.tscn authors grow_horizontal = 0 (BEGIN) — the tracker is pinned to the
	# screen edge and grows LEFT. Set before the node enters the tree so its
	# resizer derives the same free edge the real scene produces; leaving it at
	# the default put the grab handle on the pinned edge in this preview.
	tracker.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(tracker)
	tracker.anchor_left = 1.0
	tracker.anchor_right = 1.0
	tracker.offset_left = -224.0
	tracker.offset_right = -8.0
	tracker.offset_top = 128.0
	tracker.custom_minimum_size = Vector2(216, 0)
	tracker.call(&"_display", {
		"name": "The Forgemaster's Errand",
		"complete": false,
		"completion": 0,
		"objectives": [
			{"desc": "Speak with Forgemaster Helka \u00b7 Fire Forge, at the entrance",
			 "count": 0, "required": 1, "countable": true},
			{"desc": "Collect Ember Ingot", "count": 3, "required": 5, "countable": true},
		],
	})
	tracker.show()
	await get_tree().process_frame
	tracker.offset_bottom = tracker.offset_top + maxf(tracker.get_combined_minimum_size().y, 28.0)


## Element 4 — the real PartyHud, handed a fixture roster.
func _party(root: Control) -> void:
	var party: PanelContainer = PARTY_HUD.new()
	root.add_child(party)
	party.call(&"_on_roster", {
		"leader": 1,
		"names": [
			{"id": 1, "name": "Kaelen", "leader": true},
			{"id": 2, "name": "Brynn", "leader": false},
			{"id": 3, "name": "Sorrel", "leader": false},
		],
	})
