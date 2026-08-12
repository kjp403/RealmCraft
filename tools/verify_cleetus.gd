extends SceneTree
## Headless checks for the Cleetus boss prototype (assets recovered from the
## 'New Boss' sheet screenshot — see the extraction notes in the commit):
##   - the enemy index resolves the slug and its hash matches the file on disk
##   - the type loads as a boss EnemyTypeResource with a usable stat block
##   - the skin exposes every animation the mob chassis drives, each strip's
##     frame count matches the atlas regions, and no region runs off its texture
##   - standing poses are baselined like the other skins (lowest opaque row =
##     63), which is what stops a big sprite floating above its shadow; the
##     death collapse may lift off it but must not sink through it
##   - the enrage add slug is a real registered enemy
##   - every VFX sheet and rp_ hook the spell kit reaches for at cast time
##     actually exists (both fail SILENTLY in a live fight otherwise: the client
##     draws nothing while the server still deals the damage)
##   - Killing Frost's wind-up is long enough for the worst-placed player to
##     reach the safe circle, and the enrage actually changes the telegraph tint
##   - no PRE-EXISTING boss picked up a spell from the shared resource/controller
##
##   godot --headless --path . -s tools/verify_cleetus.gd
##
## The telegraph language itself is reviewed as pictures, not assertions:
##   godot --path . -s tools/render_boss_telegraphs.gd   (windowed, not headless)

const SLUG := &"ossuran"
const TYPE_PATH := "res://source/common/gameplay/characters/npc/types/bosses/cleetus.tres"
const INDEX := "res://source/common/registry/indexes/enemy_types_index.tres"
## Animations the chassis can drive, and the frame count each must have.
const EXPECTED_ANIMS := {
	&"idle": 2, &"run": 6, &"attack": 13, &"death": 6, &"special": 6, &"frost_idle": 2,
	&"emerge": 6, &"cast_staff": 4,
}
## The phase-2 form must expose the SAME clip names as the base skin — that is
## the whole reason the swap needs no AnimationTree change.
const FROST_SKIN := "res://source/common/gameplay/characters/sprite_frames/cleetus_frost.tres"
## character.tscn parks every skin's feet on the last row of the frame.
const BASELINE_ROW := 63
const VFX_DIR := "res://source/common/gameplay/combat/vfx/"
const HOSTILE_NPC := "res://source/common/gameplay/characters/npc/hostile_npc.gd"
const CONTROLLER := "res://source/common/gameplay/dungeon/boss_controller.gd"
## character.tscn runs every mob skin at this playback rate.
const SPRITE_SPEED_SCALE := 1.5
## Past this, a slowed clip stops reading as motion and reads as a frozen sprite.
const MAX_STRETCH := 8.0
## Fairness model for a run-to-safety mechanic: how far off the boss a melee
## player realistically stands, and a deliberately SLOW player speed so the
## check passes only if the mechanic is survivable for the worst-placed one.
const MELEE_STANDOFF_PX := 120.0
const SLOW_PLAYER_PX_PER_S := 90.0
## Sheets the new spell visuals load at cast time.
const VFX_USED: Array[String] = [
	"fireball_comet", "fire_explosion", "frost_burst", "frost_spikes",
	"arc_bolt", "static_ring", "lash_beam",
]
## Bosses that existed before the spell kit — none may have picked one up.
const PRIOR_BOSSES: Array[String] = [
	"res://source/common/gameplay/characters/npc/types/bosses/cinderborn.tres",
	"res://source/common/gameplay/characters/npc/types/bosses/cistern_sovereign.tres",
	"res://source/common/gameplay/characters/npc/types/bosses/sand_king.tres",
	"res://source/common/gameplay/characters/npc/types/world_boss.tres",
	"res://source/common/gameplay/characters/npc/types/mecha_stone_golem.tres",
	"res://source/common/gameplay/characters/npc/types/dungeon_boss.tres",
]
## Visual hooks BossController replicates onto the body.
const RP_HOOKS: Array[String] = [
	"rp_elem_telegraph", "rp_meteor_fall", "rp_frost_nova",
	"rp_ice_spikes", "rp_chain_lightning", "rp_sweep_beam",
]

var _fails: Array[String] = []


func _fail(msg: String) -> void:
	_fails.append(msg)
	printerr("FAIL: ", msg)


func _init() -> void:
	var index: ContentIndex = load(INDEX)
	var entry: Dictionary = {}
	for e: Dictionary in index.entries:
		if e.get(&"slug", &"") == SLUG:
			entry = e
			break
	if entry.is_empty():
		_fail("slug '%s' is not in the enemy index" % SLUG)
	else:
		if entry[&"path"] != TYPE_PATH:
			_fail("index path %s != %s" % [entry[&"path"], TYPE_PATH])
		var on_disk: String = FileAccess.get_sha256(TYPE_PATH)
		if entry[&"hash"] != on_disk:
			_fail("index hash is stale (%s on disk)" % on_disk)
		if entry[&"id"] >= index.next_id:
			_fail("id %d is not below next_id %d" % [entry[&"id"], index.next_id])
		print("index: id=%d slug=%s hash ok" % [entry[&"id"], entry[&"slug"]])

	var boss: EnemyTypeResource = load(TYPE_PATH)
	if boss == null:
		_fail("could not load %s" % TYPE_PATH)
		_finish()
		return
	if not boss.is_boss:
		_fail("is_boss is false — no BossController, so no slams or enrage")
	if boss.enemy_type != SLUG:
		_fail("enemy_type %s != %s" % [boss.enemy_type, SLUG])
	if boss.max_health <= 0.0 or boss.attack_cooldown <= 0.0:
		_fail("degenerate stat block")
	if boss.detection_radius > boss.max_distance_from_spawn:
		_fail("detection_radius %d exceeds leash %d" % [boss.detection_radius, boss.max_distance_from_spawn])
	print("type : %s  lv%d  %.0f hp  scale %.2f  xp %d (skill xp %d)" % [
		boss.display_name, boss.resolved_combat_level(), boss.max_health,
		boss.visual_scale, boss.xp_reward, boss.combat_skill_xp(),
	])

	# The enrage adds must be a registered slug or the summon silently no-ops.
	var add_known := false
	for e: Dictionary in index.entries:
		if e.get(&"slug", &"") == boss.add_enemy_slug:
			add_known = true
			break
	if not add_known:
		_fail("add_enemy_slug '%s' is not a registered enemy" % boss.add_enemy_slug)

	var skin: SpriteFrames = boss.skin
	if skin == null:
		_fail("no skin assigned")
		_finish()
		return
	for anim: StringName in EXPECTED_ANIMS:
		if not skin.has_animation(anim):
			_fail("skin is missing the '%s' animation" % anim)
			continue
		var want: int = EXPECTED_ANIMS[anim]
		var got: int = skin.get_frame_count(anim)
		if got != want:
			_fail("'%s' has %d frames, expected %d" % [anim, got, want])
		for i: int in got:
			var tex: AtlasTexture = skin.get_frame_texture(anim, i) as AtlasTexture
			if tex == null or tex.atlas == null:
				_fail("'%s' frame %d has no atlas texture" % [anim, i])
				continue
			var r: Rect2 = tex.region
			if r.end.x > tex.atlas.get_width() or r.end.y > tex.atlas.get_height():
				_fail("'%s' frame %d region %s runs off its %dx%d texture"
					% [anim, i, r, tex.atlas.get_width(), tex.atlas.get_height()])
				continue
			var img: Image = tex.atlas.get_image()
			if img == null:
				continue
			var lowest := -1
			for y: int in range(int(r.size.y) - 1, -1, -1):
				for x: int in int(r.size.x):
					if img.get_pixel(int(r.position.x) + x, int(r.position.y) + y).a > 0.0:
						lowest = y
						break
				if lowest >= 0:
					break
			if lowest < 0:
				_fail("'%s' frame %d is fully transparent" % [anim, i])
			elif anim in [&"idle", &"attack"] and lowest != BASELINE_ROW:
				# Standing poses must all sit on the same row or the mob bobs.
				_fail("'%s' frame %d baseline row %d != %d (sprite will float)"
					% [anim, i, lowest, BASELINE_ROW])
			elif anim == &"death" and lowest > BASELINE_ROW:
				# The collapse legitimately lifts off the baseline as the body
				# folds up; it just must never sink THROUGH the ground plane.
				_fail("'%s' frame %d sinks below the baseline (row %d)" % [anim, i, lowest])
		print("skin : %-10s %2d frames  loop=%s  %.0f fps" % [
			anim, got, skin.get_animation_loop(anim), skin.get_animation_speed(anim)])

	_check_phase_skin(boss, skin)
	_check_spell_kit(boss)
	_check_animation_coverage(boss, skin)
	_check_existing_bosses_untouched()
	_finish()


## No dead air: every cast must be ANIMATING for its whole window. The clips are
## far shorter than the casts (a 0.5s transform under a 3.0s Killing Frost), so
## BossController passes a fill length to rp_play_skin_anim and the clip is slowed
## to cover the window. This asserts each of those fills is still wired — dropping
## one is invisible in code review and very visible in game, as a boss standing
## still through its own spell.
func _check_animation_coverage(boss: EnemyTypeResource, skin: SpriteFrames) -> void:
	var src: FileAccess = FileAccess.open(CONTROLLER, FileAccess.READ)
	if src == null:
		_fail("could not read %s" % CONTROLLER)
		return
	var text: String = src.get_as_text()
	src.close()

	# Loop flags: a looping one-shot never releases the AnimationTree, and a
	# non-looping idle freezes on its last frame.
	for anim: StringName in [&"idle", &"run", &"frost_idle"]:
		if skin.has_animation(anim) and not skin.get_animation_loop(anim):
			_fail("'%s' must loop" % anim)
	for anim: StringName in [&"attack", &"death", &"special"]:
		if skin.has_animation(anim) and skin.get_animation_loop(anim):
			_fail("'%s' must NOT loop — it is a one-shot" % anim)
	if skin.has_animation(&"run") and skin.get_frame_count(&"run") < 4:
		_fail("'run' has %d frames — too few to read as locomotion"
			% skin.get_frame_count(&"run"))

	if not skin.has_animation(boss.cast_anim):
		_fail("cast_anim '%s' is not on the skin — casts would play nothing"
			% boss.cast_anim)
	# The freeze-over belongs to the ice moments only; using it as the generic
	# cast clip had the boss icing up to throw fire.
	if boss.frost_safe_radius > 0.0 and boss.cast_anim == &"special":
		_fail("cast_anim is 'special' (the freeze) on a boss with a fire phase")
	var casts: Array = [
		["slam", boss.slam_windup_s, boss.cast_anim, '[cast_anim, slam_windup_s]'],
		["cinder lash", boss.sweep_windup_s + boss.sweep_duration_s, &"cast_staff",
			'[pose, sweep_windup_s + sweep_duration_s]'],
		["laser", boss.laser_windup_s, &"cast_staff", '[pose, laser_windup_s]'],
		["killing frost", boss.frost_windup_s, &"special", '[&"special", frost_windup_s]'],
		["static arc", boss.chain_windup_s, &"cast_staff", '[pose, chain_windup_s]'],
		["enrage pose", 1.4, &"special", '[&"special", ENRAGE_POSE_S]'],
	]
	for row: Array in casts:
		var window: float = row[1]
		if window <= 0.0:
			continue
		if not text.contains(row[3]):
			_fail("%s no longer passes a fill to rp_play_skin_anim (wanted %s)"
				% [row[0], row[3]])
			continue
		var anim: StringName = row[2]
		if not skin.has_animation(anim):
			continue
		var clip: float = float(skin.get_frame_count(anim)) \
			/ (skin.get_animation_speed(anim) * SPRITE_SPEED_SCALE)
		var stretch: float = window / clip
		# A clip slowed past this stops reading as motion and starts reading as a
		# frozen sprite — the very bug the fill was added to remove.
		if stretch > MAX_STRETCH:
			_fail("%s stretches '%s' %.1fx (%.2fs clip over %.2fs) — will read as frozen"
				% [row[0], anim, stretch, clip, window])
		else:
			print("anim : %-14s %.2fs window / %.2fs '%s' = %.1fx stretch, 0.00s idle"
				% [row[0], window, clip, anim, stretch])

	# Beams and the lightning chain are anchored to the raised fist. If a cast
	# site drops back to the body centre the VFX detaches from the pose AND the
	# damage line shifts, because both sides read the same muzzle.
	# Three ranged casts, each of which must resolve its origin from the pose it
	# actually plays. A bare muzzle_position() means it reverted to the fist, and
	# the spell would leave his hip instead of the staff he is holding out.
	var staff_calls: int = text.count('boss.muzzle_position(pose == &"cast_staff")')
	if staff_calls != 3:
		_fail("%d/3 ranged casts resolve their origin from the staff pose" % staff_calls)
	if text.contains("boss.muzzle_position()"):
		_fail("a cast still fires from the fist (bare muzzle_position())")
	if not text.contains('_pose(&"cast_staff")'):
		_fail("no cast asks for the staff pose")
	# The mecha_laser sheet charges for most of its length and only becomes a beam
	# near the end. Handing SpriteEffect a short "duration" frees it before those
	# frames draw, which is how the beam went missing entirely.
	var bodytext: FileAccess = FileAccess.open(HOSTILE_NPC, FileAccess.READ)
	if bodytext != null:
		var bs: String = bodytext.get_as_text()
		bodytext.close()
		var laser_fn: String = bs.split("func rp_laser_beam")[-1].split("
func ")[0]
		if laser_fn.contains('"duration"'):
			_fail("rp_laser_beam passes a duration again — the beam frames get cut off")
		else:
			print("anim : laser VFX plays its full clip (beam frames land)")
	if not text.contains('rp_hand_charge'):
		_fail("no hand charge on any cast — the wind-up has no tell in the fist")

	# The meteor volley is covered a different way: one hurl per rock rather than
	# one stretched clip, so the body re-triggers instead of slowing to a crawl.
	if boss.meteor_count > 0:
		if not text.contains("func _drop_meteor"):
			_fail("_drop_meteor is gone — the per-meteor hurl animation went with it")
		elif not text.split("func _drop_meteor")[1].split("func ")[0] \
				.contains('rp_play_skin_anim", [&"attack"]'):
			_fail("meteor volley no longer animates per rock — the body will idle mid-volley")
		else:
			var volley: float = boss.meteor_windup_s \
				+ boss.meteor_stagger_s * float(boss.meteor_count - 1)
			print("anim : %-14s %.2fs volley animated as %d hurls every %.2fs"
				% ["ember rain", volley, boss.meteor_count, boss.meteor_stagger_s])

	# Death has to be able to cut a cast short, or the corpse holds its spell pose.
	var body: FileAccess = FileAccess.open(HOSTILE_NPC, FileAccess.READ)
	if body != null:
		var btext: String = body.get_as_text()
		body.close()
		if not btext.contains("func _cancel_skin_action"):
			_fail("no _cancel_skin_action() — dying mid-cast leaves the AnimationTree off")
		elif not btext.contains("\tif _skin_action_playing:\n\t\t_cancel_skin_action()"):
			_fail("_set_anim no longer cancels a one-shot on DEATH — corpse will hold its cast pose")
		else:
			print("anim : death interrupt wired (cancels a stretched cast on the spot)")


## The spell fields were added to the SHARED EnemyTypeResource and the shared
## BossController, so the thing most likely to break is a boss nobody was asked
## to change. Every pre-existing boss must still gate every new spell OFF, which
## keeps its move table exactly the slam (+laser/+arm) it had before.
func _check_existing_bosses_untouched() -> void:
	for path: String in PRIOR_BOSSES:
		if not ResourceLoader.exists(path):
			_fail("prior boss missing: %s" % path)
			continue
		var b: EnemyTypeResource = load(path) as EnemyTypeResource
		if b == null:
			_fail("prior boss will not load: %s" % path)
			continue
		var added: PackedStringArray = PackedStringArray()
		if b.meteor_count > 0:
			added.append("meteor")
		if b.sweep_arc_deg > 0.0:
			added.append("sweep")
		if b.frost_safe_radius > 0.0:
			added.append("frost")
		if b.chain_targets > 0:
			added.append("chain")
		# cast_anim gates what a slam/laser plays; rp_play_skin_anim falls back to
		# "attack" when the skin has no such clip. Report the ones that resolve to
		# nothing at all — a PRE-EXISTING content gap (those skins ship only
		# idle/run/death), not something this change introduced, and not something
		# code can fix without art.
		if b.skin != null and not b.skin.has_animation(b.cast_anim):
			if b.skin.has_animation(&"attack"):
				print("note : %s has no '%s' — casts fall back to 'attack'"
					% [path.get_file(), b.cast_anim])
			else:
				print("note : %s skin has no cast clip at all (idle/run/death only) —"
					% path.get_file())
				print("       its slam plays no animation. Pre-existing; needs art.")
		if added.size() > 0:
			_fail("%s unexpectedly gained spells: %s" % [path.get_file(), ", ".join(added)])
		else:
			print("prior: %-26s unchanged (slam%s%s)" % [
				b.enemy_type,
				" +laser" if b.laser_range > 0.0 else "",
				" +arm" if b.arm_shot_interval_s > 0.0 else ""])


## The spell kit is only as real as the pieces it reaches for at cast time: a
## missing VFX sheet or a renamed rp_ hook fails SILENTLY in a live fight (the
## client no-ops, the server still deals damage), which is the worst way to find
## out. Assert them up front instead.
func _check_spell_kit(boss: EnemyTypeResource) -> void:
	for name: String in VFX_USED:
		var path: String = VFX_DIR + name + ".tres"
		if not ResourceLoader.exists(path):
			_fail("VFX '%s' is missing (%s)" % [name, path])
			continue
		var frames: SpriteFrames = load(path) as SpriteFrames
		if frames == null or not frames.has_animation(&"default"):
			_fail("VFX '%s' has no 'default' animation — SpriteEffect will not play it" % name)

	# Every visual the controller replicates must exist on the body, or the cast
	# resolves damage with nothing drawn. Read the SOURCE rather than
	# get_script_method_list(): a `-s` tool run has no client autoloads, so
	# hostile_npc.gd does not finish compiling here and would report no methods
	# at all — a false pass/fail either way.
	var src: FileAccess = FileAccess.open(HOSTILE_NPC, FileAccess.READ)
	if src == null:
		_fail("could not read %s" % HOSTILE_NPC)
	else:
		var text: String = src.get_as_text()
		src.close()
		for hook: String in RP_HOOKS:
			if not text.contains("func %s(" % hook):
				_fail("HostileNpc has no %s() — BossController replicates it" % hook)

	# Enabled mechanics, and the phase each is gated to.
	var kit: Array = [
		["ember rain", boss.meteor_count > 0, boss.meteor_phase, boss.meteor_interval_s,
			"%d meteors, %.0f dmg, %.1fs windup" % [boss.meteor_count, boss.meteor_damage, boss.meteor_windup_s]],
		["cinder lash", boss.sweep_arc_deg > 0.0, boss.sweep_phase, boss.sweep_interval_s,
			"%.0f deg arc, %.0f dmg over %.1fs" % [boss.sweep_arc_deg, boss.sweep_damage, boss.sweep_duration_s]],
		["killing frost", boss.frost_safe_radius > 0.0, boss.frost_phase, boss.frost_interval_s,
			"safe r=%.0f at %.0fpx, %.0f dmg, %.1fs to reach it" % [boss.frost_safe_radius, boss.frost_offset_px, boss.frost_damage, boss.frost_windup_s]],
		["static arc", boss.chain_targets > 0, boss.chain_phase, boss.chain_interval_s,
			"%d links, %.0f dmg base" % [boss.chain_targets, boss.chain_damage]],
		["laser", boss.laser_range > 0.0, 0, boss.laser_interval_s,
			"%.0fpx beam, %.0f dmg, fired from the fist" % [boss.laser_range, boss.laser_damage]],
	]
	var enabled: int = 0
	for row: Array in kit:
		if not bool(row[1]):
			continue
		enabled += 1
		var phase: int = row[2]
		if float(row[3]) <= 0.0:
			_fail("%s is enabled but its interval is 0 — it would fire every frame" % row[0])
		print("spell: %-14s phase %s  every %4.1fs   %s" % [
			row[0], "both" if phase == 0 else str(phase), float(row[3]), row[4]])
	if enabled == 0:
		_fail("no boss spells enabled — this is the plain slam/laser kit again")

	# A phase-2-only move on a boss that can never enrage is dead content.
	if boss.enrage_health_fraction <= 0.0:
		for row: Array in kit:
			if bool(row[1]) and int(row[2]) == 2:
				_fail("%s is phase-2 only but the boss never enrages" % row[0])

	# Killing Frost is only fair if the wind-up covers the run. Worst case is a
	# player parked on the FAR side of the boss sprinting to the NEAR edge of the
	# safe circle — not to its centre, and not to its far edge.
	if boss.frost_safe_radius > 0.0:
		var run_px: float = MELEE_STANDOFF_PX + boss.frost_offset_px - boss.frost_safe_radius
		var need: float = run_px / SLOW_PLAYER_PX_PER_S
		if boss.frost_windup_s < need:
			_fail("Killing Frost windup %.1fs is too short: %.0fpx run needs %.1fs"
				% [boss.frost_windup_s, run_px, need])
		else:
			print("check: killing frost windup %.1fs covers a %.0fpx run (%.1fs) — %.1fs spare"
				% [boss.frost_windup_s, run_px, need, boss.frost_windup_s - need])
	if boss.enraged_telegraph_element == boss.telegraph_element:
		_fail("enrage does not change the telegraph element — the phase flip will not read")


func _finish() -> void:
	if _fails.is_empty():
		print("VERIFY_PASS")
	else:
		print("VERIFY_FAIL (%d)" % _fails.size())
	quit(0 if _fails.is_empty() else 1)


## A phase-2 skin swap is only safe if the replacement answers to every clip name
## the base skin does: the AnimationTree keeps travelling to idle/run/death by
## name after the swap, so a missing clip is a body that freezes mid-fight.
func _check_phase_skin(boss: EnemyTypeResource, base: SpriteFrames) -> void:
	if boss.phase2_skin.is_empty():
		_fail("no phase2_skin — the boss enrages without visibly changing")
		return
	if not ResourceLoader.exists(boss.phase2_skin):
		_fail("phase2_skin missing: %s" % boss.phase2_skin)
		return
	var cold: SpriteFrames = load(boss.phase2_skin) as SpriteFrames
	if cold == null:
		_fail("phase2_skin will not load as SpriteFrames")
		return
	for anim: StringName in base.get_animation_names():
		if not cold.has_animation(anim):
			_fail("phase2 skin has no '%s' — body freezes after enrage" % anim)
		elif cold.get_frame_count(anim) != base.get_frame_count(anim):
			_fail("phase2 '%s' has %d frames vs %d on the base skin"
				% [anim, cold.get_frame_count(anim), base.get_frame_count(anim)])
	# The swap must actually change something, or it is dead weight.
	var differs := 0
	for anim: StringName in [&"idle", &"run", &"attack", &"cast_staff"]:
		if base.has_animation(anim) and cold.has_animation(anim) 				and base.get_frame_texture(anim, 0) != cold.get_frame_texture(anim, 0):
			differs += 1
	if differs == 0:
		_fail("phase2 skin is visually identical to the base skin")
	else:
		print("phase: phase2 skin swaps %d clip(s), all %d names present"
			% [differs, base.get_animation_names().size()])
	# rp_spawn_effect must put the base skin back or a respawn stays frozen.
	var body: FileAccess = FileAccess.open(HOSTILE_NPC, FileAccess.READ)
	if body != null:
		var bt: String = body.get_as_text()
		body.close()
		if not bt.contains('rp_swap_skin("")'):
			_fail("respawn does not restore the base skin — boss comes back frosted")
		if not bt.contains('has_animation(&"emerge")'):
			_fail("spawn no longer plays the emerge clip")
