extends SceneTree
## Gate for the Brimstone Keeper idle: the sheet is one 10-frame walk row, and
## every clip pointed at all ten, so the NPC strode on the spot. Idle must be a
## short pose loop, and the other clips must keep their full cycles.
##   godot --headless --path . -s tools/check_demon_idle.gd

const SKIN: String = "res://source/common/gameplay/characters/sprite_frames/hell_old_demon.tres"


func _init() -> void:
	var frames: SpriteFrames = load(SKIN) as SpriteFrames
	if frames == null:
		push_error("could not load %s" % SKIN)
		quit(1)
		return
	var failed: bool = false
	for name: StringName in [&"attack", &"death", &"idle", &"run", &"walk"]:
		if not frames.has_animation(name):
			push_error("missing clip %s" % name)
			failed = true
			continue
		var count: int = frames.get_frame_count(name)
		print("%-7s %2d frames  speed %.1f" % [name, count, frames.get_animation_speed(name)])
		if name == &"idle" and count > 3:
			push_error("idle is still the walk cycle (%d frames)" % count)
			failed = true
		if name in [&"run", &"walk"] and count < 10:
			push_error("%s lost frames (%d)" % [name, count])
			failed = true
	print("RESULT ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
