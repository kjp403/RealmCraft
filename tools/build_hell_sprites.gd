extends SceneTree
## Build SpriteFrames + EnemyTypeResources for the Brimstone Vault roster.
## Covered sheets only. Run after import:
##   godot --headless --path . --import
##   godot --headless --path . -s tools/build_hell_sprites.gd
##   godot --headless --path . -s tools/update_enemy_types_index.gd

const SKINS := "res://source/common/gameplay/characters/sprite_frames/"
const TYPES := "res://source/common/gameplay/characters/npc/types/hell/"
const CHAR := "res://assets/sprites/characters/hell/"

const LOOT := preload("res://source/common/gameplay/combat/loot_drop.gd")


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TYPES))

	_skin_grid("hell_damned", CHAR + "male_damned.png", 64, 64, [
		{"anim": "idle", "row": 0, "n": 5, "speed": 6.0, "loop": true},
		{"anim": "run", "row": 1, "n": 8, "speed": 10.0, "loop": true},
		{"anim": "attack", "row": 2, "n": 6, "speed": 10.0, "loop": false},
		{"anim": "death", "row": 3, "n": 7, "speed": 8.0, "loop": false},
	])
	_skin_grid("hell_twisted", CHAR + "twisted_damned.png", 64, 64, [
		{"anim": "idle", "row": 0, "n": 5, "speed": 6.0, "loop": true},
		{"anim": "run", "row": 1, "n": 8, "speed": 9.0, "loop": true},
		{"anim": "attack", "row": 2, "n": 6, "speed": 10.0, "loop": false},
		{"anim": "death", "row": 3, "n": 7, "speed": 8.0, "loop": false},
	])
	_skin_grid("hell_burning", CHAR + "burning_damned.png", 64, 64, [
		{"anim": "idle", "row": 0, "n": 5, "speed": 7.0, "loop": true},
		{"anim": "run", "row": 1, "n": 8, "speed": 11.0, "loop": true},
		{"anim": "attack", "row": 2, "n": 6, "speed": 11.0, "loop": false},
		{"anim": "death", "row": 3, "n": 7, "speed": 8.0, "loop": false},
	])
	_skin_grid("hell_bloated", CHAR + "bloated_damned.png", 64, 64, [
		{"anim": "idle", "row": 0, "n": 5, "speed": 5.0, "loop": true},
		{"anim": "run", "row": 1, "n": 8, "speed": 7.0, "loop": true},
		{"anim": "attack", "row": 2, "n": 6, "speed": 9.0, "loop": false},
		{"anim": "death", "row": 2, "n": 6, "speed": 8.0, "loop": false},
	])
	_skin_grid("hell_imp", CHAR + "imp.png", 64, 64, [
		{"anim": "idle", "row": 0, "n": 10, "speed": 8.0, "loop": true},
		{"anim": "run", "row": 2, "n": 8, "speed": 12.0, "loop": true},
		{"anim": "attack", "row": 4, "n": 6, "speed": 12.0, "loop": false},
		{"anim": "death", "row": 3, "n": 5, "speed": 8.0, "loop": false},
	])
	_skin_grid("hell_vault_queen", CHAR + "large_skull.png", 128, 128, [
		{"anim": "idle", "row": 0, "n": 10, "speed": 7.0, "loop": true},
		{"anim": "attack", "row": 1, "n": 20, "speed": 12.0, "loop": false},
		{"anim": "death", "row": 3, "n": 10, "speed": 8.0, "loop": false},
	])
	_skin_grid("hell_eye", CHAR + "demon_eye.png", 64, 64, [
		{"anim": "idle", "row": 0, "n": 7, "speed": 8.0, "loop": true},
		{"anim": "run", "row": 1, "n": 7, "speed": 10.0, "loop": true},
		{"anim": "attack", "row": 1, "n": 7, "speed": 10.0, "loop": false},
		{"anim": "death", "row": 1, "n": 7, "speed": 8.0, "loop": false},
	])
	_skin_grid("hell_skull_wisp", CHAR + "burning_skull.png", 64, 64, [
		{"anim": "idle", "row": 0, "n": 7, "speed": 8.0, "loop": true},
		{"anim": "run", "row": 1, "n": 7, "speed": 10.0, "loop": true},
		{"anim": "attack", "row": 1, "n": 7, "speed": 10.0, "loop": false},
		{"anim": "death", "row": 1, "n": 7, "speed": 8.0, "loop": false},
	])
	_skin_strip("hell_giant", CHAR + "hell_giant.png", 112, 128, 10, 6.0)
	_skin_strip("hell_old_demon", CHAR + "old_demon.png", 56, 64, 10, 6.0)

	_type("hell_imp", "Ash Imp", {
		"combat_level": 46, "max_health": 70.0, "attack_damage": 15.0, "attack_cooldown": 1.15,
		"armor": 22.0, "move_speed": 92, "distance_to_attack": 18, "detection_radius": 170,
		"visual_scale": 0.85, "is_lone": false,
	})
	_type("hell_damned", "Damned", {
		"combat_level": 52, "max_health": 130.0, "attack_damage": 20.0, "attack_cooldown": 1.35,
		"armor": 32.0, "move_speed": 58, "distance_to_attack": 22, "detection_radius": 160,
	})
	_type("hell_twisted", "Twisted Damned", {
		"combat_level": 56, "max_health": 165.0, "attack_damage": 24.0, "attack_cooldown": 1.45,
		"armor": 40.0, "mr": 8.0, "move_speed": 50, "distance_to_attack": 24, "detection_radius": 160,
		"visual_scale": 1.1,
	})
	_type("hell_burning", "Cinder Damned", {
		"combat_level": 54, "max_health": 120.0, "attack_damage": 26.0, "attack_cooldown": 1.2,
		"armor": 30.0, "move_speed": 70, "distance_to_attack": 22, "detection_radius": 175,
	})
	_type("hell_bloated", "Bloated Damned", {
		"combat_level": 64, "max_health": 260.0, "attack_damage": 32.0, "attack_cooldown": 1.7,
		"armor": 52.0, "mr": 10.0, "move_speed": 36, "distance_to_attack": 32, "detection_radius": 180,
		"visual_scale": 1.2,
	})
	_type("hell_eye", "Demon Eye", {
		"combat_level": 50, "max_health": 90.0, "attack_damage": 20.0, "attack_cooldown": 1.05,
		"armor": 18.0, "move_speed": 80, "distance_to_attack": 20, "detection_radius": 220,
		"visual_scale": 0.9, "is_lone": true,
	})
	_type("hell_skull_wisp", "Burning Skull", {
		"combat_level": 52, "max_health": 100.0, "attack_damage": 22.0, "attack_cooldown": 1.2,
		"armor": 24.0, "move_speed": 78, "distance_to_attack": 20, "detection_radius": 180,
	})
	_type("hell_giant", "Hell Giant", {
		"combat_level": 80, "max_health": 550.0, "attack_damage": 44.0, "attack_cooldown": 1.35,
		"armor": 68.0, "mr": 42.0, "move_speed": 50, "distance_to_attack": 48, "detection_radius": 240,
		"visual_scale": 1.35,
	})
	_boss()

	_append_sprites()
	print("HELL_SPRITES_PASS")
	quit(0)


func _skin_grid(slug: String, tex_path: String, fw: int, fh: int, rows: Array) -> void:
	var tex: Texture2D = load(tex_path) as Texture2D
	assert(tex != null, "missing %s" % tex_path)
	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	var cols: int = maxi(1, int(tex.get_width() / fw))
	for spec: Dictionary in rows:
		var anim := StringName(str(spec["anim"]))
		if frames.has_animation(anim):
			frames.remove_animation(anim)
		frames.add_animation(anim)
		frames.set_animation_speed(anim, float(spec["speed"]))
		frames.set_animation_loop(anim, bool(spec["loop"]))
		var row: int = int(spec["row"])
		var n: int = int(spec["n"])
		for i in n:
			var idx: int = row * cols + i
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2((idx % cols) * fw, int(idx / cols) * fh, fw, fh)
			frames.add_frame(anim, at)
	if frames.has_animation(&"run") == false and frames.has_animation(&"idle"):
		_clone(frames, &"idle", &"run")
	if frames.has_animation(&"walk") == false and frames.has_animation(&"run"):
		_clone(frames, &"run", &"walk")
	if frames.has_animation(&"special") == false and frames.has_animation(&"attack"):
		_clone(frames, &"attack", &"special")
	elif frames.has_animation(&"special") == false and frames.has_animation(&"idle"):
		_clone(frames, &"idle", &"special")
	frames.set_meta(&"slug", StringName(slug))
	var err := ResourceSaver.save(frames, SKINS + slug + ".tres")
	assert(err == OK, "save skin %s" % slug)
	print("skin ", slug)


func _skin_strip(slug: String, tex_path: String, fw: int, fh: int, n: int, speed: float) -> void:
	var tex: Texture2D = load(tex_path) as Texture2D
	assert(tex != null, "missing %s" % tex_path)
	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	frames.add_animation(&"idle")
	frames.set_animation_speed(&"idle", speed)
	frames.set_animation_loop(&"idle", true)
	for i in n:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * fw, 0, fw, fh)
		frames.add_frame(&"idle", at)
	_clone(frames, &"idle", &"run")
	_clone(frames, &"idle", &"walk")
	_clone(frames, &"idle", &"attack")
	_clone(frames, &"idle", &"death")
	_clone(frames, &"idle", &"special")
	frames.set_animation_loop(&"death", false)
	frames.set_animation_loop(&"special", false)
	frames.set_meta(&"slug", StringName(slug))
	var err := ResourceSaver.save(frames, SKINS + slug + ".tres")
	assert(err == OK, "save skin %s" % slug)
	print("skin ", slug)


func _clone(frames: SpriteFrames, from_anim: StringName, to_anim: StringName) -> void:
	if frames.has_animation(to_anim):
		frames.remove_animation(to_anim)
	frames.add_animation(to_anim)
	frames.set_animation_loop(to_anim, frames.get_animation_loop(from_anim))
	frames.set_animation_speed(to_anim, frames.get_animation_speed(from_anim))
	for i in frames.get_frame_count(from_anim):
		frames.add_frame(to_anim, frames.get_frame_texture(from_anim, i), frames.get_frame_duration(from_anim, i))


func _type(slug: String, display: String, stats: Dictionary) -> void:
	var etype := EnemyTypeResource.new()
	etype.enemy_type = StringName(slug)
	etype.display_name = display
	etype.skin = load(SKINS + slug + ".tres") as SpriteFrames
	etype.leashes = false
	etype.chase_on_area = true
	etype.respawns = false
	etype.xp_reward = 0
	etype.wander_radius = 28.0
	etype.max_distance_from_spawn = 420
	for key: Variant in stats.keys():
		etype.set(str(key), stats[key])
	_attach_kit(slug, etype)
	etype.set_meta(&"slug", StringName(slug))
	var err := ResourceSaver.save(etype, TYPES + slug + ".tres")
	assert(err == OK, "save type %s" % slug)
	print("type ", slug)


func _attach_kit(slug: String, etype: EnemyTypeResource) -> void:
	match slug:
		"hell_imp":
			etype.behaviors = [_lunge(140.0, 20.0, 5.5)]
		"hell_twisted":
			etype.behaviors = [_lunge(150.0, 24.0, 6.0)]
		"hell_eye":
			etype.behaviors = [_lunge(160.0, 18.0, 4.8)]
		"hell_skull_wisp":
			etype.behaviors = [_lunge(150.0, 18.0, 5.0)]
		"hell_giant":
			etype.behaviors = [_lunge(180.0, 32.0, 6.5, 0.7)]
		"hell_burning":
			etype.behaviors = [_burst(52.0, 3.5, 0.15)]
		"hell_bloated":
			etype.behaviors = [_burst(64.0, 4.0, 0.15)]
		_:
			pass


func _lunge(reach: float, radius: float, cooldown: float, windup: float = 0.55) -> LungeBehavior:
	var b := LungeBehavior.new()
	b.lunge_range = reach
	b.lunge_radius = radius
	b.lunge_cooldown = cooldown
	b.lunge_windup_s = windup
	return b


func _burst(radius: float, duration_s: float, ad_ratio: float) -> DeathBurstBehavior:
	var b := DeathBurstBehavior.new()
	b.radius = radius
	b.duration_s = duration_s
	b.tick_interval_s = 0.5
	b.ad_ratio_per_tick = ad_ratio
	return b


func _boss() -> void:
	var etype := EnemyTypeResource.new()
	etype.enemy_type = &"hell_vault_queen"
	etype.display_name = "The Vault Queen"
	etype.skin = load(SKINS + "hell_vault_queen.tres") as SpriteFrames
	etype.visual_scale = 1.45
	etype.is_boss = true
	etype.combat_level = 100
	etype.max_health = 900.0
	etype.attack_damage = 95.0
	etype.attack_cooldown = 1.15
	etype.armor = 155.0
	etype.mr = 150.0
	etype.move_speed = 58
	etype.distance_to_attack = 56
	etype.max_distance_from_spawn = 360
	etype.leashes = false
	etype.detection_radius = 280
	etype.chase_on_area = true
	etype.xp_reward = 24000
	etype.combat_skill_xp_override = 40000
	etype.respawns = false
	etype.enrage_health_fraction = 0.55
	etype.slam_radius = 170.0
	etype.slam_windup_s = 0.95
	etype.slam_damage = 480.0
	etype.slam_on_target = true
	etype.slam_interval_s = 5.0
	etype.enraged_slam_interval_s = 2.7
	etype.add_enemy_slug = &"hell_imp"
	etype.add_count = 8
	etype.add_spread_px = 72.0
	etype.enrage_speed_mult = 1.45
	etype.cast_anim = &"attack"
	etype.telegraph_element = 0
	etype.meteor_count = 8
	etype.meteor_radius = 58.0
	etype.meteor_damage = 280.0
	etype.meteor_windup_s = 1.05
	etype.meteor_stagger_s = 0.26
	etype.meteor_spread_px = 230.0
	etype.meteor_interval_s = 6.0
	etype.enraged_meteor_interval_s = 3.6
	etype.meteor_phase = 0
	etype.sweep_arc_deg = 130.0
	etype.sweep_range = 320.0
	etype.sweep_width = 40.0
	etype.sweep_windup_s = 0.95
	etype.sweep_duration_s = 1.05
	etype.sweep_damage = 320.0
	etype.sweep_interval_s = 9.0
	etype.enraged_sweep_interval_s = 5.5
	etype.sweep_phase = 0
	etype.chain_targets = 4
	etype.chain_range = 200.0
	etype.chain_damage = 260.0
	etype.chain_windup_s = 0.7
	etype.chain_interval_s = 7.5
	etype.enraged_chain_interval_s = 4.5
	etype.chain_phase = 2
	etype.sear_wound_duration_s = 8.0
	etype.sear_wound_damage = 300.0
	etype.sear_wound_radius = 96.0
	etype.sear_wound_interval_s = 11.0
	etype.enraged_sear_wound_interval_s = 7.0
	etype.sear_wound_windup_s = 0.8
	etype.soft_enrage_s = 150.0
	etype.soft_enrage_ramp = 0.45
	etype.loot = _boss_loot()
	etype.set_meta(&"slug", &"hell_vault_queen")
	var err := ResourceSaver.save(etype, TYPES + "hell_vault_queen.tres")
	assert(err == OK, "save boss")
	print("type hell_vault_queen")


func _boss_loot() -> Array[LootDrop]:
	var out: Array[LootDrop] = []
	out.append(_drop("res://source/common/gameplay/items/currencies/gold.tres", 2200, 4200, 1.0))
	out.append(_drop("res://source/common/gameplay/items/materials/metals/wyrmguard_ore.tres", 5, 10, 1.0))
	out.append(_drop("res://source/common/gameplay/items/materials/metals/godsteel_ore.tres", 1, 3, 0.45))
	out.append(_drop("res://source/common/gameplay/items/consumables/dungeon_key.tres", 1, 1, 0.4))
	out.append(_drop("res://source/common/gameplay/items/weapons/sword/sword_wyrmguard.item.tres", 1, 1, 0.03))
	out.append(_drop("res://source/common/gameplay/items/weapons/sword/sword_godsteel.item.tres", 1, 1, 0.01))
	return out


func _drop(item_path: String, lo: int, hi: int, chance: float) -> LootDrop:
	var d: LootDrop = LOOT.new()
	d.item = load(item_path)
	d.min_amount = lo
	d.max_amount = hi
	d.chance = chance
	return d


func _append_sprites() -> void:
	var index: ContentIndex = load("res://source/common/registry/indexes/sprites_index.tres") as ContentIndex
	var existing: Dictionary = {}
	for entry: Dictionary in index.entries:
		existing[entry[&"slug"]] = true
	var dir := DirAccess.open(ProjectSettings.globalize_path(SKINS))
	assert(dir != null)
	dir.list_dir_begin()
	var name := dir.get_next()
	var added := 0
	while name != "":
		if name.begins_with("hell_") and name.ends_with(".tres"):
			var slug := StringName(name.get_basename())
			if not existing.has(slug):
				var path := SKINS + name
				var resource: Resource = load(path)
				if resource != null:
					var id: int = index.next_id
					index.next_id += 1
					resource.set_meta(&"slug", slug)
					resource.set_meta(&"id", id)
					ResourceSaver.save(resource, path)
					index.entries.append({
						&"id": id,
						&"slug": slug,
						&"path": path,
						&"hash": FileAccess.get_sha256(path),
					})
					added += 1
		name = dir.get_next()
	dir.list_dir_end()
	index.version = int(Time.get_unix_time_from_system())
	ResourceSaver.save(index, "res://source/common/registry/indexes/sprites_index.tres")
	print("sprites index added=", added)
