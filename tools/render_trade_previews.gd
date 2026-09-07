extends Node
## Screenshot the REAL trade window (TradePanel) at the shipping 960x540 client
## size, with a hand-built session so both offers are full.
##
## Runs as a SCENE, not a `-s` tool, and windowed (headless has no rasteriser):
##   godot --path . --mode=client res://tools/render_trade_previews.tscn
##
## WHY IT EXISTS: the offer grid is built in code, so the only way to know that
## TradeService.MAX_OFFER_ITEMS squares actually FIT — rather than pushing the
## gold row and Confirm button off the bottom — is to render a full one.
##
## The fixture is pushed straight into _render() and _recompute_owned(), bypassing
## the trade.* round trip: there is no world server in a preview run, so the live
## path would hang on its first await.

const HUD_SCENE: String = "res://source/client/ui/hud/hud.tscn"
const OUT_DIR: String = "res://previews"
const W: int = 960
const H: int = 540
const ME: int = 4009

var _sv: SubViewport
var _panel: Control
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
	_sv.disable_3d = true
	get_tree().root.add_child(_sv)

	# Stand-in for the world behind the overlay, so the panel's dim backdrop reads
	# the way it does over a real map instead of over pure black.
	var ground: ColorRect = ColorRect.new()
	ground.size = Vector2(W, H)
	ground.color = Color(0.16, 0.20, 0.15)
	_sv.add_child(ground)

	# The panel has no scene of its own — it is a node inside the HUD.
	var hud: Node = (load(HUD_SCENE) as PackedScene).instantiate()
	_panel = hud.get_node("TradePanel") as Control
	hud.remove_child(_panel)
	hud.queue_free()
	_sv.add_child(_panel)

	await get_tree().process_frame
	await get_tree().process_frame

	ClientState.player_id = ME
	_panel._trade_id = 1
	_panel.show()
	_panel._recompute_owned(_bag())
	_panel._render(_session())

	await _shot("trade-full-offer.png")
	_panel._open_picker()
	await _shot("trade-picker.png")

	get_tree().quit(0)


func _id(slug: StringName) -> int:
	return ContentRegistryHub.id_from_slug(&"items", slug)


## A bag deep enough to fill every offer square and still have things left in the
## picker, including bulk stacks that span many bag squares.
func _bag() -> Dictionary:
	var bag: Dictionary = {}
	for entry: Array in [
		[&"gold", 41_250], [&"iron_ore", 137], [&"coal_ore", 84], [&"oak_log", 41],
		[&"iron_bar", 23], [&"healing_herb", 17], [&"cooked_lobster", 12],
		[&"bronze_arrowheads", 640], [&"bone", 88], [&"vial_of_water", 55],
		[&"steel_bar", 9], [&"willow_log", 30], [&"health_potion", 14],
		[&"sword_runite.item", 1],
	]:
		var item_id: int = _id(entry[0] as StringName)
		if item_id > 0:
			bag[Inventory.next_uid(bag)] = {"id": item_id, "a": int(entry[1]), "bag": 0}
	# Cooked shrimp caps at 10 a bag square, so 90 of them is NINE squares. The
	# offer must still read "90" — quantity in a trade is what you OWN, not what
	# one square holds.
	var shrimp: int = _id(&"cooked_shrimp")
	if shrimp > 0:
		for _square: int in 9:
			bag[Inventory.next_uid(bag)] = {"id": shrimp, "a": 10, "bag": 0}
	return bag


## Both seats at MAX_OFFER_ITEMS — the worst case for the grid's height.
func _session() -> Dictionary:
	var mine: Array = []
	for entry: Array in [
		[&"cooked_shrimp", 90], [&"bronze_arrowheads", 640], [&"iron_ore", 137],
		[&"coal_ore", 84], [&"oak_log", 41], [&"iron_bar", 23],
		[&"healing_herb", 17], [&"cooked_lobster", 12], [&"bone", 88],
		[&"vial_of_water", 55], [&"steel_bar", 9], [&"willow_log", 30],
	]:
		var item_id: int = _id(entry[0] as StringName)
		if item_id > 0:
			mine.append({"id": item_id, "amount": int(entry[1])})
	var theirs: Array = []
	for entry: Array in [
		[&"sword_runite.item", 1], [&"health_potion", 14], [&"steel_bar", 40],
		[&"willow_log", 250], [&"bone", 500], [&"healing_herb", 60],
	]:
		var item_id: int = _id(entry[0] as StringName)
		if item_id > 0:
			theirs.append({"id": item_id, "amount": int(entry[1])})
	return {
		"locked": false,
		"countdown": 0,
		"seats": [
			{"id": ME, "name": "Kayla", "items": mine, "gold": 12_500, "accepted": false},
			{"id": 5150, "name": "Corvin", "items": theirs, "gold": 90_000, "accepted": true},
		],
	}


func _shot(file_name: String) -> void:
	for _i: int in 10:
		await get_tree().process_frame
	var image: Image = _sv.get_texture().get_image()
	image.resize(image.get_width() * 2, image.get_height() * 2, Image.INTERPOLATE_NEAREST)
	var dest: String = _out_abs.path_join(file_name)
	image.save_png(dest)
	print("SAVED %s size=%s" % [dest, image.get_size()])
