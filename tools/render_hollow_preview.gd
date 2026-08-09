extends SceneTree
## Render Hollow arena + MechaGolem idle frame for visual gate.


func _initialize() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var peer := OfflineMultiplayerPeer.new()
	root.multiplayer.multiplayer_peer = peer

	var packed: PackedScene = load("res://source/common/gameplay/maps/maps/the_hollow/the_hollow.tscn")
	var sv := SubViewport.new()
	sv.size = Vector2i(960, 720)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	sv.transparent_bg = false
	sv.world_2d = World2D.new()
	root.add_child(sv)

	var map: Node2D = packed.instantiate() as Node2D
	sv.add_child(map)

	var cam := Camera2D.new()
	cam.position = Vector2(472, 360)
	cam.make_current()
	map.add_child(cam)

	# Force golem visual even if HostileNPC script graph is unhappy under -s.
	var golem: Node = map.get_node_or_null("ReplicatedPropsContainer/MechaGolem")
	var skin: SpriteFrames = load("res://source/common/gameplay/characters/sprite_frames/mecha_stone_golem.tres")
	if golem != null and skin != null:
		var spr := AnimatedSprite2D.new()
		spr.name = "PreviewSkin"
		spr.sprite_frames = skin
		spr.animation = &"idle"
		spr.scale = Vector2(1.9, 1.9)
		spr.position = Vector2.ZERO
		spr.play()
		golem.add_child(spr)
		print("preview_golem_attached frames=", skin.get_frame_count("idle"))

	for _i: int in 12:
		await process_frame

	DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/screenshots")
	var image: Image = sv.get_texture().get_image()
	image.save_png("/opt/cursor/artifacts/screenshots/hollow-golem-preview.png")
	print("SAVED hollow-golem-preview.png size=", image.get_size(), " golem=", golem != null)
	quit(0)
