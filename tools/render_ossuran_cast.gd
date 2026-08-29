extends Node
## Screenshot the encounter's CAST standing in the arena: Ossuran on his spawn,
## the three pillars on their pedestals, kindled and frozen.
##
##   godot --path . --mode=client res://tools/render_ossuran_cast.tscn
##
## Must run WINDOWED, not --headless: the dummy renderer draws no tilemaps and
## runs no shaders, so a headless capture is a blank room.
##
## The bodies are staged as plain AnimatedSprite2D built from each enemy type's
## own `skin` and `visual_scale`, NOT spawned as live HostileNpc. Spawning real
## bodies needs a ReplicatedPropsContainer, a server instance and a player list,
## none of which exist in a preview harness — and none of which change what the
## art looks like. Everything that decides how these read on screen (which
## SpriteFrames, which clip, what scale, where the feet land) is taken from the
## same resources the live spawn reads, so this is the cast at the size and place
## the fight puts them.

const MAP: String = "res://source/common/gameplay/maps/maps/ossuran/ossuran_arena.tscn"
const OUT_DIR: String = "res://previews/ossuran"
const TYPES: String = "res://source/common/gameplay/characters/npc/types/ossuran/"
const BOSS_TYPE: String = "res://source/common/gameplay/characters/npc/types/bosses/cleetus.tres"

## character.tscn parks every mob skin's feet on the last row of its 64px frame,
## so the sprite is lifted half a frame to stand ON the marker rather than
## hovering with the marker at its waist.
const FEET_OFFSET: Vector2 = Vector2(0, -32)


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await _render("cast_kindled", false)
	await _render("cast_frozen", true)
	get_tree().quit(0)


func _render(shot: String, frozen: bool) -> void:
	var sv := SubViewport.new()
	sv.size = Vector2i(768, 544)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	sv.disable_3d = true
	get_tree().root.add_child(sv)

	var map: Node = (load(MAP) as PackedScene).instantiate()
	sv.add_child(map)
	var cam := Camera2D.new()
	cam.position = Vector2(384, 272)
	sv.add_child(cam)
	cam.make_current()

	var encounter: Node = map.get_node_or_null(^"Encounter")
	var stage := Node2D.new()
	stage.y_sort_enabled = true
	map.add_child(stage)

	# Ossuran. The frozen shot uses his phase2_skin, which is the same swap
	# BossController performs live when he enrages.
	var boss: EnemyTypeResource = load(BOSS_TYPE)
	if boss != null:
		var skin: SpriteFrames = boss.skin
		if frozen and not boss.phase2_skin.is_empty():
			var cold: SpriteFrames = load(boss.phase2_skin)
			if cold != null:
				skin = cold
		_place(stage, skin, _marker(encounter, ^"BossSpawn"), boss.visual_scale, frozen)

	# The three pillars, in the order OssuranArena spawns them.
	var markers: Node = encounter.get_node_or_null(^"PillarMarkers") if encounter != null else null
	var slugs: Array[String] = [
		"ossuran_pillar_ember", "ossuran_pillar_thorn", "ossuran_pillar_hex",
	]
	if markers != null:
		var kids: Array[Node] = markers.get_children()
		for i: int in mini(kids.size(), slugs.size()):
			var type: EnemyTypeResource = load("%s%s.tres" % [TYPES, slugs[i]])
			if type == null:
				continue
			_place(stage, type.skin, (kids[i] as Marker2D).global_position,
				type.visual_scale, false)

	if frozen:
		for path: NodePath in [^"Tiles/Ground", ^"Tiles/Deco"]:
			var layer: TileMapLayer = map.get_node_or_null(path) as TileMapLayer
			if layer == null:
				continue
			var mat: ShaderMaterial = layer.material as ShaderMaterial
			if mat != null:
				mat.set_shader_parameter(
					EnvironmentTransitionManager.PROGRESS_UNIFORM, 1.0
				)
	else:
		# Kindled shot: show both pads mid-ritual so the scars and lights read.
		for pad_name: String in ["EmberPad", "StormPad"]:
			var pad: Node = encounter.get_node_or_null(NodePath(pad_name))
			if pad == null:
				continue
			for child: String in ["Fill", "Decal"]:
				var part: CanvasItem = pad.get_node_or_null(NodePath(child))
				if part == null:
					continue
				var m: ShaderMaterial = part.material as ShaderMaterial
				if m != null:
					m.set_shader_parameter(&"charge", 1.0)
					m.set_shader_parameter(&"active", 1.0)
				part.visible = true

	for _i: int in 16:
		await get_tree().process_frame
	var out: String = ProjectSettings.globalize_path(OUT_DIR).path_join("%s.png" % shot)
	sv.get_texture().get_image().save_png(out)
	print("SAVED ", out)
	sv.queue_free()
	await get_tree().process_frame


func _marker(encounter: Node, name: NodePath) -> Vector2:
	var node: Marker2D = encounter.get_node_or_null(name) as Marker2D if encounter != null else null
	return node.global_position if node != null else Vector2(384, 180)


func _place(
	parent: Node2D, frames: SpriteFrames, at: Vector2, body_scale: float, frozen: bool
) -> void:
	if frames == null:
		return
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	# Prefer the resting pose; fall back to whatever the skin actually has, since
	# the pillar skins are cut from the stone golem and carry a different set.
	for clip: StringName in [&"frost_idle" if frozen else &"idle", &"idle", &"run"]:
		if frames.has_animation(clip):
			sprite.animation = clip
			break
	sprite.offset = FEET_OFFSET
	sprite.scale = Vector2.ONE * body_scale
	sprite.position = at
	parent.add_child(sprite)
