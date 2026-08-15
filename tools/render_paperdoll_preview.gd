extends SceneTree
## Render a contact sheet of the character creator + gear progression to PNG.
##
##     godot --path . -s tools/render_paperdoll_preview.gd
##
## NOT --headless: this renders real frames. Output goes to
## user://paperdoll_preview.png and the absolute path is printed.
##
## Uses [PaperDollPreview] rather than the in-world [PaperDoll] on purpose: with no
## multiplayer peer, `multiplayer.is_server()` is TRUE, so the in-world rig would
## correctly refuse to draw anything client-side and this tool would silently
## produce an empty sheet.

const CELL: int = 128
const COLS: int = 6
const ROWS: int = 3
const OUT_PATH: String = "user://paperdoll_preview.png"

var _root: Node2D


## SceneTree entry point. NOT _init(): at construction time `root` does not exist
## yet, so building the scene there silently produces nothing and the tool hangs
## waiting for a quit that never comes.
func _initialize() -> void:
	_build()
	_capture()


func _build() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.09)
	bg.size = Vector2(CELL * COLS, CELL * ROWS)
	root.add_child(bg)

	# A dressed character to show off: forester tunic, spiked hair.
	var outfit: int = maxi(0, PaperDollData.OUTFITS.find(&"fstr"))
	var hair: int = maxi(0, PaperDollData.HAIR_STYLES.find(&"spk2"))
	var dressed: int = Player.pack_appearance(1, hair, 4, outfit)

	var cells: Array[Dictionary] = []
	# Row 1: the same character walking in all four directions, then two more bodies.
	for facing: int in 4:
		cells.append({"a": dressed, "facing": facing, "gear": {}})
	cells.append({"a": Player.pack_appearance(5, 2, 9, outfit),
		"facing": PaperDollData.Facing.DOWN, "gear": {}})
	cells.append({"a": Player.pack_appearance(8, 4, 1, outfit),
		"facing": PaperDollData.Facing.DOWN, "gear": {}})

	# Row 2: outfit variety (skip the underwear entries - they are the default, not a look).
	for code: StringName in [&"fstr", &"alch", &"bksm", &"angl", &"pfpn", &"pfdr"]:
		cells.append({
			"a": Player.pack_appearance(2, hair, 6, maxi(0, PaperDollData.OUTFITS.find(code))),
			"facing": PaperDollData.Facing.DOWN, "gear": {},
		})

	# Row 3: REAL equipped items, loaded from the game's own .tres and resolved
	# through the same appearance_item() the world uses - armour on the body,
	# weapon in the hand.
	for pair: Array in [
		["res://source/common/gameplay/items/gears/metal/iron_chest.tres",
		 "res://source/common/gameplay/items/weapons/sword/sword_iron.item.tres"],
		["res://source/common/gameplay/items/gears/metal/mithril_chest.tres",
		 "res://source/common/gameplay/items/weapons/sword/sword_mithril.item.tres"],
		["res://source/common/gameplay/items/gears/leather/shadow_vest.tres",
		 "res://source/common/gameplay/items/weapons/bow/iron_bow.item.tres"],
		["res://source/common/gameplay/items/gears/cloth/voidsilk_robe.tres",
		 "res://source/common/gameplay/items/weapons/hammer/hammer_iron.item.tres"],
		["res://source/common/gameplay/items/gears/metal/dragon_chest.tres", ""],
		["res://source/common/gameplay/items/gears/leather/leather_jacket.tres", ""],
	]:
		var gear_look: Array = [&"", &""]
		var armour: GearItem = load(pair[0]) as GearItem
		if armour != null:
			gear_look = armour.appearance_item()
		var weapon_look: Array = [&"", &""]
		if pair[1] != "" and ResourceLoader.exists(pair[1]):
			var weapon: WeaponItem = load(pair[1]) as WeaponItem
			if weapon != null:
				weapon_look = weapon.appearance_item()
		cells.append({"a": dressed, "facing": PaperDollData.Facing.DOWN,
			"gear": {&"torso": gear_look, &"weapon": weapon_look}})

	for i: int in mini(cells.size(), COLS * ROWS):
		var preview: PaperDollPreview = PaperDollPreview.new()
		preview.position = Vector2((i % COLS) * CELL, (i / COLS) * CELL)
		preview.size = Vector2(CELL, CELL)
		preview.zoom = 3
		preview.walking = true
		root.add_child(preview)
		preview.set("facing", int(cells[i]["facing"]))
		preview.set_appearance.call_deferred(int(cells[i]["a"]))
		for slot: StringName in (cells[i]["gear"] as Dictionary):
			var look2: Array = (cells[i]["gear"] as Dictionary)[slot]
			preview.set_gear.call_deferred(slot, look2[0], look2[1])


func _capture() -> void:
	# Let the previews build, load their sheets and advance a few animation frames.
	for i: int in 20:
		await process_frame
	var image: Image = root.get_viewport().get_texture().get_image()
	var region: Rect2i = Rect2i(0, 0, mini(CELL * COLS, image.get_width()),
		mini(CELL * ROWS, image.get_height()))
	var error: int = image.get_region(region).save_png(OUT_PATH)
	if error != OK:
		print("RENDER_FAIL: could not save ", OUT_PATH)
	else:
		print("RENDER_OK: ", ProjectSettings.globalize_path(OUT_PATH))
	quit(0 if error == OK else 1)
