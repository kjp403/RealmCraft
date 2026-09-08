extends Node
## Renders one overview PNG per biome with its AUTHORED peddler spots marked, so
## a human can confirm placement by LOOKING rather than by reading coordinates.
##
## That review is the entire point of authored spots. The prober can prove a
## square is reachable, painted and clear of aggressive mobs and still choose one
## that reads badly — jammed against a map rim, behind a building, in the middle
## of a corridor everyone runs through. Only eyes catch that.
##
## Markers: green = proposed spot, blue = home spawn, red = aggressive mob.
##
## Run: godot --path . --mode=client res://tools/render_peddler_spots.tscn

const BIOMES_DIR: String = "res://source/common/gameplay/maps/instance/instance_collection/biomes/"
const OUT_DIR: String = "res://previews/peddler"
const W: int = 960
const H: int = 540
const SPOT_COLOR: Color = Color(0.35, 1.0, 0.45)
const HOME_COLOR: Color = Color(0.35, 0.7, 1.0)
const MOB_COLOR: Color = Color(1.0, 0.35, 0.35)
const PeddlerProposal = preload("res://tools/peddler_proposal.gd")

var _out_abs: String


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	_out_abs = ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(_out_abs)
	for file_name: String in ResourceLoader.list_directory(BIOMES_DIR):
		if file_name.ends_with(".tres"):
			await _shoot(BIOMES_DIR + file_name)
	get_tree().quit(0)


func _shoot(res_path: String) -> void:
	var biome: InstanceResource = ResourceLoader.load(res_path) as InstanceResource
	if biome == null or PeddlerSites.is_excluded(biome.instance_name):
		return
	var packed: PackedScene = load(biome.map_path) as PackedScene
	if packed == null:
		return

	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(W, H)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.disable_3d = true
	get_tree().root.add_child(viewport)
	var stage: Node2D = Node2D.new()
	viewport.add_child(stage)

	var map: Node = packed.instantiate()
	stage.add_child(map)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if map is not Map:
		viewport.queue_free()
		return
	var m: Map = map as Map

	# Read every map coordinate BEFORE the stage is scaled and offset below.
	# global_position is relative to the viewport, so a position read afterwards
	# already has the stage transform in it and applying to_screen would apply it
	# twice — which drew all 39 fire_forge mobs as a neat grid in the corner.
	# The AUTHORED markers, not a fresh proposal: this picture is meant to show
	# what ships. A proposal re-derived here would quietly stop matching the scene
	# the moment anyone nudged a marker, which is the whole thing being reviewed.
	var spots: PackedVector2Array = PeddlerSites.authored_spots(m)
	var home: Vector2 = m.get_spawn_position(0)
	var mobs: Array = PeddlerProposal.aggressive_mobs(m)

	# Fit the map's authored camera box into the viewport. It is the closest thing
	# a map has to "the part players see"; a map without one falls back to its
	# painted rect.
	var bounds: Rect2 = _bounds(m)
	var zoom: float = minf(float(W) / bounds.size.x, float(H) / bounds.size.y)
	stage.scale = Vector2(zoom, zoom)
	stage.position = -bounds.position * zoom + Vector2(
		(W - bounds.size.x * zoom) * 0.5, (H - bounds.size.y * zoom) * 0.5
	)

	# Markers go on the VIEWPORT, not the map, at a fixed screen size. Parented to
	# the map they inherit its scale, and a 22px dot on a map drawn at 0.08 zoom is
	# under two pixels — invisible, which defeats the whole point of the picture.
	var overlay: Control = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(overlay)
	var to_screen: Callable = func(at: Vector2) -> Vector2:
		return at * zoom + stage.position
	for mob: Dictionary in mobs:
		_dot(overlay, to_screen.call(mob["at"]), MOB_COLOR, 5.0)
	_dot(overlay, to_screen.call(home), HOME_COLOR, 11.0)
	for i: int in spots.size():
		_dot(overlay, to_screen.call(spots[i]), SPOT_COLOR, 15.0, str(i + 1))

	for _i: int in 8:
		await get_tree().process_frame
	var image: Image = viewport.get_texture().get_image()
	var dest: String = _out_abs.path_join("%s.png" % biome.instance_name)
	image.save_png(dest)
	print("SAVED %-22s %d spot(s)  zoom %.2f" % [biome.instance_name, spots.size(), zoom])
	viewport.queue_free()
	await get_tree().process_frame


## A marker in SCREEN coordinates: a white plate under a coloured square, so it
## stays visible over grass, stone and water alike.
func _dot(overlay: Control, at: Vector2, color: Color, size: float, label: String = "") -> void:
	var plate: ColorRect = ColorRect.new()
	plate.color = Color(1, 1, 1, 0.9)
	plate.size = Vector2(size + 4.0, size + 4.0)
	plate.position = at - plate.size * 0.5
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(plate)
	var pip: ColorRect = ColorRect.new()
	pip.color = color
	pip.size = Vector2(size, size)
	pip.position = at - pip.size * 0.5
	pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(pip)
	if label.is_empty():
		return
	var tag: Label = Label.new()
	tag.text = label
	tag.position = at + Vector2(size * 0.5 + 3.0, -9.0)
	tag.add_theme_color_override(&"font_color", Color(1, 1, 1))
	tag.add_theme_color_override(&"font_outline_color", Color(0, 0, 0))
	tag.add_theme_constant_override(&"outline_size", 4)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(tag)


func _bounds(map: Map) -> Rect2:
	var box := Rect2(
		Vector2(map.camera_limit_left, map.camera_limit_top),
		Vector2(
			map.camera_limit_right - map.camera_limit_left,
			map.camera_limit_bottom - map.camera_limit_top
		)
	)
	if box.size.x > 0.0 and box.size.y > 0.0 and box.size.x < 100000.0:
		return box
	var painted: Rect2 = PeddlerSites.playable_rect(map)
	return painted if painted.has_area() else Rect2(Vector2.ZERO, Vector2(W, H))
