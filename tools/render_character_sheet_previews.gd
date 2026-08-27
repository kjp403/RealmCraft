extends Node
## Screenshot the REAL Character → Stats tab at the shipping 960x540 client size,
## with a hand-built stat block and attribute spread so both panels render the
## way a mid-game player sees them.
##
## Runs as a SCENE, not a `-s` tool, and windowed (headless has no rasteriser):
##   godot --path . --mode=client res://tools/render_character_sheet_previews.tscn
##
## `-s` starts a bare SceneTree with no autoloads, and both panels reference
## ClientState / Client — under `-s` they fail to COMPILE, so there is nothing to
## screenshot. The panels normally pull their data from the server; there is no
## server here, so the fixture is pushed straight into them instead.

const MENU_SCENE: String = "res://source/client/ui/menus/character/character_menu.tscn"
const OUT_DIR: String = "res://previews"
const W: int = 960
const H: int = 540

var _sv: SubViewport
var _menu: Control
var _out_abs: String
var _stats: StatsComponent.Stats


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

	var ground := ColorRect.new()
	ground.size = Vector2(W, H)
	ground.color = Color(0.24, 0.30, 0.22)
	_sv.add_child(ground)

	var scene: PackedScene = load(MENU_SCENE) as PackedScene
	if scene == null:
		push_error("Could not load %s" % MENU_SCENE)
		get_tree().quit(1)
		return
	_menu = scene.instantiate() as Control
	_sv.add_child(_menu)

	await get_tree().process_frame
	await get_tree().process_frame

	# A believable level-44 archer: base + level HP, a bow's worth of AD, some
	# gear resists, and 24 unspent points on top of a partial build.
	var attributes: Dictionary = {
		"vitality": 8, "strength": 14, "defense": 5,
		"intelligence": 0, "spirit": 3, "agility": 6,
	}
	_feed_stats(attributes)
	_feed_attributes(attributes, 24)

	await _settle()
	_save(_sv.get_texture().get_image(), "character-sheet.png")

	# Second shot: the reason the breakdown exists — swap a chest piece for a
	# hybrid one and watch every row it touches move at once.
	_stats.set(Stat.ARMOR, _stats.values[Stat.ARMOR] - 4.0)
	_stats.set(Stat.MR, _stats.values[Stat.MR] + 12.0)
	_stats.set(Stat.HEALTH_MAX, _stats.values[Stat.HEALTH_MAX] + 15.0)
	_stats.set(Stat.AD, _stats.values[Stat.AD] + 6.0)
	await _settle()
	_save(_sv.get_texture().get_image(), "character-sheet-gear-swap.png")

	# Third shot: scrolled to Offense, where the "what do I hit a target with N
	# armor for" line lives.
	var scroll: ScrollContainer = _menu.find_child(
		"StatsScroll", true, false) as ScrollContainer
	if scroll != null:
		scroll.scroll_vertical = 240
	await _settle()
	_save(_sv.get_texture().get_image(), "character-sheet-offense.png")
	get_tree().quit(0)


## Compose the same way the server does: BASE_STATS + per-level HP + attributes,
## with a gear delta on top, so the numbers on screen are numbers the game can
## actually produce.
func _feed_stats(attributes: Dictionary) -> void:
	var values: Dictionary[StringName, float]
	values.assign(PlayerResource.BASE_STATS)
	values[Stat.HEALTH_MAX] += PlayerResource.HEALTH_PER_LEVEL * 43.0
	for stat_name: StringName in AttributeMap.attr_to_stats(attributes):
		values[stat_name] = values.get(stat_name, 0.0) + AttributeMap.attr_to_stats(attributes)[stat_name]
	# Equipment.
	values[Stat.AD] = values.get(Stat.AD, 0.0) + 42.0
	values[Stat.ARMOR] = values.get(Stat.ARMOR, 0.0) + 26.0
	values[Stat.MR] = values.get(Stat.MR, 0.0) + 10.0
	values[Stat.LIFESTEAL] = 4.0
	values[Stat.HEALTH] = values[Stat.HEALTH_MAX] - 37.0

	var stats: StatsComponent.Stats = StatsComponent.Stats.new()
	for stat_name: StringName in values:
		stats.values[stat_name] = values[stat_name]
	var panel: Node = _menu.find_child("StatsPanel", true, false)
	panel.watch_stats(stats)
	# The Base/Gear/Points split normally comes from the server; there isn't one
	# here, so hand the panel the same spread the attribute rows are using.
	panel._attributes = attributes
	panel.redraw()
	_stats = stats


func _feed_attributes(attributes: Dictionary, points: int) -> void:
	var panel: Node = _menu.find_child("Attributes", true, false)
	panel._on_attribute_received({"attr": attributes, "points": points})


func _settle() -> void:
	for _i: int in 8:
		await get_tree().process_frame


func _save(image: Image, file_name: String, scale: int = 2) -> void:
	if scale > 1:
		image.resize(image.get_width() * scale, image.get_height() * scale, Image.INTERPOLATE_NEAREST)
	var dest: String = _out_abs.path_join(file_name)
	image.save_png(dest)
	print("SAVED ", dest, " size=", image.get_size())
