extends SceneTree
## Build SpriteFrames for biome decorative props + ambient critters.
##   godot --headless --path . -s tools/build_biome_props.gd

const OUT_DECO := "res://source/common/gameplay/props/sprite_frames/"
const OUT_CRIT := "res://source/common/gameplay/characters/sprite_frames/"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DECO))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_CRIT))

	_strip_frames(
		"res://assets/sprites/environment/rf_catacombs/torch_strip.png",
		OUT_DECO + "deco_torch.tres",
		16, 16, 4, 0.12
	)
	_strip_frames(
		"res://assets/sprites/environment/rf_catacombs/candleA_strip.png",
		OUT_DECO + "deco_candle_a.tres",
		7, 16, 4, 0.14
	)
	_strip_frames(
		"res://assets/sprites/environment/rf_catacombs/candleB_strip.png",
		OUT_DECO + "deco_candle_b.tres",
		13, 16, 4, 0.14
	)
	_strip_frames(
		"res://assets/sprites/environment/rf_catacombs/spike_strip.png",
		OUT_DECO + "deco_spike.tres",
		13, 14, 5, 0.1
	)

	# SE idle only — full strip includes graze/turn that reads as "glitching" at distance.
	# Frame widths MUST match content pitch (stag cells are 32px, not 48).
	_critter(
		"stag",
		"res://assets/sprites/characters/critters/stag/critter_stag_SE_idle.png",
		32, 41, 4,
		"res://assets/sprites/characters/critters/stag/critter_stag_SE_walk.png",
		32, 41, 8,
		0.9
	)
	_critter(
		"badger",
		"res://assets/sprites/characters/critters/badger/badger_idle_strip.png",
		42, 32, 8,
		"res://assets/sprites/characters/critters/badger/badger_walk_strip.png",
		42, 32, 9,
		1.0
	)
	_critter(
		"boar",
		"res://assets/sprites/characters/critters/boar/boar_idle_strip.png",
		41, 25, 7,
		"res://assets/sprites/characters/critters/boar/boar_walk_strip.png",
		46, 32, 11,
		1.1
	)
	_critter(
		"wolf",
		"res://assets/sprites/characters/critters/wolf/wolf_idle_strip.png",
		64, 64, 4,
		"res://assets/sprites/characters/critters/wolf/wolf_walk_strip.png",
		64, 64, 8,
		1.0
	)

	print("BIOME_PROPS_PASS")
	quit(0)


func _strip_frames(tex_path: String, out_path: String, fw: int, fh: int, n: int, speed: float) -> void:
	var tex: Texture2D = load(tex_path)
	assert(tex != null, "missing %s" % tex_path)
	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	frames.add_animation(&"default")
	frames.set_animation_speed(&"default", 1.0 / speed)
	frames.set_animation_loop(&"default", true)
	for i in n:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * fw, 0, fw, fh)
		frames.add_frame(&"default", at)
	var err := ResourceSaver.save(frames, out_path)
	assert(err == OK, "save failed %s" % out_path)
	print("wrote ", out_path)


func _critter(
	slug: String,
	idle_path: String, idle_fw: int, idle_fh: int, idle_n: int,
	walk_path: String, walk_fw: int, walk_fh: int, walk_n: int,
	_scale_hint: float,
	idle_start: int = 0,
	walk_start: int = 0
) -> void:
	var idle_tex: Texture2D = load(idle_path)
	var walk_tex: Texture2D = load(walk_path)
	assert(idle_tex != null and walk_tex != null, "missing critter tex %s" % slug)
	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	frames.add_animation(&"idle")
	frames.set_animation_speed(&"idle", 8.0)
	frames.set_animation_loop(&"idle", true)
	for i in idle_n:
		var at := AtlasTexture.new()
		at.atlas = idle_tex
		at.region = Rect2((idle_start + i) * idle_fw, 0, idle_fw, idle_fh)
		frames.add_frame(&"idle", at)
	frames.add_animation(&"walk")
	frames.set_animation_speed(&"walk", 10.0)
	frames.set_animation_loop(&"walk", true)
	for i in walk_n:
		var at2 := AtlasTexture.new()
		at2.atlas = walk_tex
		at2.region = Rect2((walk_start + i) * walk_fw, 0, walk_fw, walk_fh)
		frames.add_frame(&"walk", at2)
	var out := OUT_CRIT + "critter_%s.tres" % slug
	var err := ResourceSaver.save(frames, out)
	assert(err == OK, "save failed %s" % out)
	print("wrote ", out, " idle=", idle_n, " walk=", walk_n)
