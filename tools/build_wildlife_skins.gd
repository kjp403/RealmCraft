extends SceneTree
## Build combat SpriteFrames for Wild Wolf + Woodland Rat (top-down quadrupeds).
##   godot --headless --path . -s tools/build_wildlife_skins.gd

const OUT := "res://source/common/gameplay/characters/sprite_frames/"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_build_wolf()
	_build_woodland_rat()
	print("WILDLIFE_SKINS_PASS")
	quit(0)


func _build_wolf() -> void:
	# Top-down strips (same art as ambient desert wolf).
	var frames := _frames_from_strips(
		"res://assets/sprites/characters/critters/wolf/wolf_idle_strip.png", 64, 64, 4,
		"res://assets/sprites/characters/critters/wolf/wolf_walk_strip.png", 64, 64, 8,
		"res://assets/sprites/characters/critters/wolf/wolf-death.png", 64, 64, 8, 0
	)
	frames.set_meta(&"slug", &"wolf")
	var err := ResourceSaver.save(frames, OUT + "wolf.tres")
	assert(err == OK, "save wolf.tres failed")
	print("wrote ", OUT + "wolf.tres")


func _build_woodland_rat() -> void:
	# rat_base art is a bipedal were-rat — use small top-down badger as scurrying vermin.
	var frames := _frames_from_strips(
		"res://assets/sprites/characters/critters/badger/badger_idle_strip.png", 42, 32, 8,
		"res://assets/sprites/characters/critters/badger/badger_walk_strip.png", 42, 32, 9,
		"res://assets/sprites/characters/critters/badger/badger_walk_strip.png", 42, 32, 4, 5
	)
	frames.set_meta(&"slug", &"woodland_rat")
	var err := ResourceSaver.save(frames, OUT + "woodland_rat.tres")
	assert(err == OK, "save woodland_rat.tres failed")
	print("wrote ", OUT + "woodland_rat.tres")


func _frames_from_strips(
	idle_path: String, idle_fw: int, idle_fh: int, idle_n: int,
	run_path: String, run_fw: int, run_fh: int, run_n: int,
	death_path: String, death_fw: int, death_fh: int, death_n: int, death_start: int
) -> SpriteFrames:
	var idle_tex: Texture2D = load(idle_path)
	var run_tex: Texture2D = load(run_path)
	var death_tex: Texture2D = load(death_path)
	assert(idle_tex != null and run_tex != null and death_tex != null)
	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	_add_strip(frames, &"idle", idle_tex, idle_fw, idle_fh, idle_n, 0, 8.0)
	_add_strip(frames, &"run", run_tex, run_fw, run_fh, run_n, 0, 10.0)
	_add_strip(frames, &"walk", run_tex, run_fw, run_fh, run_n, 0, 10.0)
	_add_strip(frames, &"death", death_tex, death_fw, death_fh, death_n, death_start, 8.0)
	return frames


func _add_strip(
	frames: SpriteFrames, anim: StringName, tex: Texture2D,
	fw: int, fh: int, n: int, start: int, speed: float
) -> void:
	frames.add_animation(anim)
	frames.set_animation_speed(anim, speed)
	frames.set_animation_loop(anim, anim != &"death")
	var cols: int = maxi(1, int(tex.get_width() / fw))
	for i in n:
		var idx := start + i
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2((idx % cols) * fw, int(idx / cols) * fh, fw, fh)
		frames.add_frame(anim, at)
