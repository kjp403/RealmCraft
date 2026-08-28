extends Node
## Proof that both "which slot?" pickers offer the NEW slots: the mastery tree's
## ability picker must list R, and the bag's hotkey picker must list keys 4 and 5.
##
## Runs as a SCENE, windowed (headless has no rasteriser):
##   godot --path . --mode=client res://tools/render_slot_pickers_preview.tscn
##
## Entries are built by the same loops the real call sites use, over the same
## constants (MasteryTreeMenu.SLOT_KEYS / ItemSlots.SLOT_COUNT), so a regression
## that shortens either list shows up here.

const MASTERY_MENU: GDScript = preload("res://source/client/ui/menus/mastery_tree/mastery_tree_menu.gd")
const ITEM_SLOTS: GDScript = preload("res://source/client/ui/hud/item_slots.gd")
const OUT: String = "res://previews/hud-slot-pickers.png"


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var ground: ColorRect = ColorRect.new()
	ground.color = Color(0.16, 0.11, 0.08)
	ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(ground)

	var ability: PackedStringArray = PackedStringArray()
	for i: int in MASTERY_MENU.SLOT_KEYS.size():
		ability.append("Slot %d (%s)  ·  empty" % [i + 1, MASTERY_MENU.SLOT_KEYS[i]])
	var left: Control = _host(Vector2(0.0, 0.0), Vector2(0.5, 1.0))
	_dock(SlotPickerOverlay.open(left, "Place Multishot III on which slot?", ability, _noop))

	var quick: PackedStringArray = PackedStringArray()
	for i: int in ITEM_SLOTS.SLOT_COUNT:
		quick.append("Slot %d (key %d)  —  empty" % [i + 1, i + 1])
	var right: Control = _host(Vector2(0.5, 0.0), Vector2(1.0, 1.0))
	_dock(SlotPickerOverlay.open(right, "Place Lobster on which quick slot?", quick, _noop))

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT))
	print("wrote ", OUT, "  ability slots=", ability.size(), "  quick slots=", quick.size())
	get_tree().quit()


func _noop(_slot: int) -> void:
	pass


## In game the overlay is top_level so a narrow docked host cannot clip it — which
## also means two of them would sit on top of each other here. Dropping top_level
## re-parents each card into its own half of the shot. Preview-only: it changes
## where the card is drawn, not what it lists.
func _dock(overlay: Control) -> void:
	overlay.top_level = false
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## One half of the screen per picker.
func _host(anchor_min: Vector2, anchor_max: Vector2) -> Control:
	var host: Control = Control.new()
	host.clip_contents = true
	host.anchor_left = anchor_min.x
	host.anchor_top = anchor_min.y
	host.anchor_right = anchor_max.x
	host.anchor_bottom = anchor_max.y
	host.offset_left = 0.0
	host.offset_top = 0.0
	host.offset_right = 0.0
	host.offset_bottom = 0.0
	add_child(host)
	return host
