extends Node
## QA shots of the sewer biome's two rebuilt features: the zone boundary on each
## side, and a plank crossing over the impassable sludge.
##   godot --path . --mode=client res://tools/render_sewer_boundary.tscn

const SEWERS: String = "res://source/common/gameplay/maps/maps/sewers/sewers.tscn"
const GUTTER: String = "res://source/common/gameplay/maps/maps/sewers/gutterworks.tscn"

## name, map, camera position in pixels. The boundary shots sit on the outer edge
## of the zone; the bridge shots sit on a generated crossing.
const SHOTS: Array = [
	["sewer-edge-north", SEWERS, Vector2(2240, 260)],
	["sewer-edge-south", SEWERS, Vector2(2240, 3060)],
	["sewer-edge-west", SEWERS, Vector2(260, 1680)],
	["sewer-bridge", SEWERS, Vector2(1344, 928)],
	["gutter-bridge", GUTTER, Vector2(1300, 1640)],
]


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	for shot in SHOTS:
		await _shot(String(shot[0]), String(shot[1]), shot[2])
	print("SEWER_BOUNDARY_RENDER_DONE")
	get_tree().quit(0)


func _shot(name: String, map: String, at: Vector2) -> void:
	var sv := SubViewport.new()
	sv.size = Vector2i(960, 640)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	sv.disable_3d = true
	get_tree().root.add_child(sv)
	sv.add_child((load(map) as PackedScene).instantiate())
	var cam := Camera2D.new()
	cam.position = at
	sv.add_child(cam)
	cam.make_current()
	for _i: int in 16:
		await get_tree().process_frame
	var out: String = ProjectSettings.globalize_path("res://previews").path_join(name + ".png")
	sv.get_texture().get_image().save_png(out)
	print("SAVED ", out)
	sv.queue_free()
