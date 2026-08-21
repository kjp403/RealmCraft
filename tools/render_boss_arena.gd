extends Node
## Screenshot the whole Boss Hunt arena so the room size, the spawn point and
## the exit can be seen at once.
##   godot --path . --mode=client res://tools/render_boss_arena.tscn

const MAP: String = "res://source/common/gameplay/maps/maps/boss_hunt/boss_hunt_arena.tscn"


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var sv := SubViewport.new()
	sv.size = Vector2i(960, 640)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	sv.disable_3d = true
	get_tree().root.add_child(sv)
	sv.add_child((load(MAP) as PackedScene).instantiate())
	for _i: int in 12:
		await get_tree().process_frame
	var out: String = ProjectSettings.globalize_path("res://previews").path_join("boss-arena.png")
	sv.get_texture().get_image().save_png(out)
	print("SAVED ", out)
	get_tree().quit(0)
