extends SceneTree
## Headless checks for Malacor, the Sun-Eater.
##
## The art was recovered from a recompressed screen capture of an 8-direction
## sheet with ONE static pose per direction (see tools/build_malacor_sprites.py),
## so every clip is synthesised. That makes the usual "does it load" pass far too
## weak: a synthesised clip can be structurally perfect and still float, jitter,
## or shear a wingtip off. These assert the things a screenshot will not show.
##
##   - the enemy index resolves the slug and its hash matches the file on disk
##   - the type loads as a boss with a coherent stat block, and sits ABOVE the
##     existing ladder rather than silently landing mid-tier
##   - the skin exposes every clip the chassis drives, with the frame counts and
##     loop flags the AnimationTree needs (a looping one-shot never releases it)
##   - the synthesised motion obeys the baselines measured off the shipped
##     skins: standing poses pinned to the ground row, the run hop bounded, the
##     death collapse never sinking through the ground plane
##   - no frame touches a side border, which is what a widen/lean that outgrew
##     the frame looks like -- a sheared wingtip is a 1px tell in the art
##   - every cast has a pose to play and is not stretched past reading as motion
##   - the enrage add slug is a real registered enemy
##   - the spell kit is internally consistent and no PRE-EXISTING boss picked
##     anything up from the shared resource
##
##   godot --headless --path . -s tools/verify_malacor.gd
##
## Expect a wall of "Identifier not found: Client" from the client autoloads --
## they do not exist in a -s run, it is pre-existing noise, and this still runs.

const SLUG := &"sun_eater"
const TYPE_PATH := "res://source/common/gameplay/characters/npc/types/bosses/sun_eater.tres"
const INDEX := "res://source/common/registry/indexes/enemy_types_index.tres"
const SKIN_PATH := "res://source/common/gameplay/characters/sprite_frames/malacor.tres"
const CONTROLLER := "res://source/common/gameplay/dungeon/boss_controller.gd"

## Clips the chassis can drive, and the frame count each must have.
const EXPECTED_ANIMS := {
	&"idle": 4, &"run": 6, &"attack": 8, &"death": 6, &"special": 6, &"emerge": 6,
}
## Frame row that sits on the ground, DERIVED rather than assumed.
##
## character.tscn draws the sprite centred with offset (0, -30) and scales it by
## visual_scale, so frame row r lands at local y = (r - 30 - frame/2) *
## visual_scale, and the ground is y ~= 0. That gives 63 for a 64px frame --
## exactly the "feet on the last row" convention every shipped 64px skin uses --
## but 81 for the 100px frame this boss needs to stop looking blocky. Hard-coding
## 63 here would pass a sprite that floats 18px above its own shadow.
##
## It is also why the 100px trpg sheets (feet at rows 58-69) sit off the ground.
static func ground_row(frame_px: int) -> int:
	return 31 + frame_px / 2
## character.tscn runs every mob skin at this playback rate.
const SPRITE_SPEED_SCALE := 1.5
## Past this, a slowed clip stops reading as motion and reads as a frozen sprite.
const MAX_STRETCH := 8.0
## The run hop lifts the whole body. More than this stops reading as a stride and
## starts reading as the sprite detaching from its shadow.
const MAX_RUN_HOP := 2
## He is meant to top the ladder. Vurthek/Ossuran sit at 560 with 30-32k HP; if a
## rebalance ever drops Malacor under this he has quietly become a mid-tier mob
## while still dropping mastery-90 weapons.
const MIN_COMBAT_LEVEL := 666
const MIN_HEALTH := 32000.0
## Bosses that existed before this one -- none may have picked up its kit.
const PRIOR_BOSSES: Array[String] = [
	"res://source/common/gameplay/characters/npc/types/bosses/cinderborn.tres",
	"res://source/common/gameplay/characters/npc/types/bosses/cistern_sovereign.tres",
	"res://source/common/gameplay/characters/npc/types/bosses/sand_king.tres",
	"res://source/common/gameplay/characters/npc/types/world_boss.tres",
	"res://source/common/gameplay/characters/npc/types/mecha_stone_golem.tres",
	"res://source/common/gameplay/characters/npc/types/dungeon_boss.tres",
]

var _fails: Array[String] = []


func _fail(msg: String) -> void:
	_fails.append(msg)
	printerr("FAIL: ", msg)


func _init() -> void:
	_check_index()
	var boss: EnemyTypeResource = load(TYPE_PATH) as EnemyTypeResource
	if boss == null:
		_fail("could not load %s" % TYPE_PATH)
		_finish()
		return
	_check_stats(boss)
	var skin: SpriteFrames = boss.skin
	if skin == null:
		_fail("no skin assigned")
		_finish()
		return
	_check_skin(skin)
	_check_casts(boss, skin)
	_check_kit(boss)
	_check_existing_bosses_untouched()
	_check_body_scale_is_inert()
	_check_articulated(skin)
	_finish()


func _check_index() -> void:
	var index: ContentIndex = load(INDEX) as ContentIndex
	if index == null:
		_fail("could not load %s" % INDEX)
		return
	var entry: Dictionary = {}
	for e: Dictionary in index.entries:
		if e.get(&"slug", &"") == SLUG:
			entry = e
			break
	if entry.is_empty():
		_fail("slug '%s' is not in the enemy index — it can never be spawned" % SLUG)
		return
	if entry[&"path"] != TYPE_PATH:
		_fail("index path %s != %s" % [entry[&"path"], TYPE_PATH])
	var on_disk: String = FileAccess.get_sha256(TYPE_PATH)
	if entry[&"hash"] != on_disk:
		_fail("index hash is stale (%s on disk)" % on_disk)
	if entry[&"id"] >= index.next_id:
		_fail("id %d is not below next_id %d" % [entry[&"id"], index.next_id])
	# A duplicate id silently shadows another enemy at registry build time.
	var seen: Dictionary = {}
	for e: Dictionary in index.entries:
		var id: int = e.get(&"id", -1)
		if seen.has(id):
			_fail("id %d is used by both %s and %s" % [id, seen[id], e.get(&"slug", &"?")])
		seen[id] = e.get(&"slug", &"?")
	print("index: id=%d slug=%s hash ok" % [entry[&"id"], entry[&"slug"]])


func _check_stats(boss: EnemyTypeResource) -> void:
	if not boss.is_boss:
		_fail("is_boss is false — no BossController, so no phases, slams or enrage")
	if boss.enemy_type != SLUG:
		_fail("enemy_type %s != %s" % [boss.enemy_type, SLUG])
	if boss.max_health <= 0.0 or boss.attack_cooldown <= 0.0:
		_fail("degenerate stat block")
	if boss.detection_radius > boss.max_distance_from_spawn:
		_fail("detection_radius %d exceeds leash %d" % [
			boss.detection_radius, boss.max_distance_from_spawn])
	if boss.leashes:
		_fail("leashes is true — a raid boss must commit, not walk home mid-fight")
	if boss.resolved_combat_level() < MIN_COMBAT_LEVEL:
		_fail("combat level %d is below the top of the ladder (%d)" % [
			boss.resolved_combat_level(), MIN_COMBAT_LEVEL])
	if boss.max_health < MIN_HEALTH:
		_fail("%.0f hp is under the existing tier (%.0f)" % [boss.max_health, MIN_HEALTH])
	# skill XP scales with effective HP, so a 46k-HP body derives an absurd
	# payout unless it is authored. This is the field that decouples the two.
	if boss.combat_skill_xp_override <= 0:
		_fail("no combat_skill_xp_override — a boss this tanky would derive its XP")
	if boss.loot.is_empty():
		_fail("no loot table")
	for drop: LootDrop in boss.loot:
		if drop == null or drop.item == null:
			_fail("a loot entry has no item — it will roll and grant nothing")
	# The enrage adds must be a registered slug or the summon silently no-ops.
	var index: ContentIndex = load(INDEX) as ContentIndex
	var add_known := false
	if index != null:
		for e: Dictionary in index.entries:
			if e.get(&"slug", &"") == boss.add_enemy_slug:
				add_known = true
				break
	if not add_known:
		_fail("add_enemy_slug '%s' is not a registered enemy" % boss.add_enemy_slug)
	print("type : %s  lv%d  %.0f hp  scale %.2f  xp %d (skill xp %d)  %d drops" % [
		boss.display_name, boss.resolved_combat_level(), boss.max_health,
		boss.visual_scale, boss.xp_reward, boss.combat_skill_xp(), boss.loot.size(),
	])


## The part that matters for synthesised art. Everything here is a rule measured
## off the shipped skins, not a preference.
func _check_skin(skin: SpriteFrames) -> void:
	var baseline: int = -1
	for anim: StringName in EXPECTED_ANIMS:
		if not skin.has_animation(anim):
			_fail("skin is missing the '%s' animation" % anim)
			continue
		var want: int = EXPECTED_ANIMS[anim]
		var got: int = skin.get_frame_count(anim)
		if got != want:
			_fail("'%s' has %d frames, expected %d" % [anim, got, want])

		var baselines: PackedInt32Array = PackedInt32Array()
		for i: int in got:
			var tex: AtlasTexture = skin.get_frame_texture(anim, i) as AtlasTexture
			if tex == null or tex.atlas == null:
				_fail("'%s' frame %d has no atlas texture" % [anim, i])
				continue
			var r: Rect2 = tex.region
			if r.end.x > tex.atlas.get_width() or r.end.y > tex.atlas.get_height():
				_fail("'%s' frame %d region %s runs off its %dx%d texture" % [
					anim, i, r, tex.atlas.get_width(), tex.atlas.get_height()])
				continue
			if baseline < 0:
				baseline = ground_row(int(r.size.y))
				print("skin : %dpx frames -> ground row %d" % [int(r.size.y), baseline])
			elif ground_row(int(r.size.y)) != baseline:
				_fail("'%s' frame %d is %dpx — clips must share one frame size"
					% [anim, i, int(r.size.y)])
			var img: Image = tex.atlas.get_image()
			if img == null:
				continue
			var lowest := -1
			var left := int(r.size.x)
			var right := -1
			for y: int in int(r.size.y):
				for x: int in int(r.size.x):
					if img.get_pixel(int(r.position.x) + x, int(r.position.y) + y).a > 0.0:
						lowest = maxi(lowest, y)
						left = mini(left, x)
						right = maxi(right, x)
			if lowest < 0:
				_fail("'%s' frame %d is fully transparent" % [anim, i])
				continue
			baselines.append(lowest)
			# A frame flush against a side border has had wingtip cut off by the
			# widen/lean the clip applies. Invisible in a contact sheet.
			if left <= 0 or right >= int(r.size.x) - 1:
				_fail("'%s' frame %d touches a side border (x %d..%d) — wingtip sheared"
					% [anim, i, left, right])

		if baselines.is_empty():
			continue
		if anim in [&"idle", &"attack"]:
			# Standing poses must all sit on the same row or the mob bobs while
			# it is supposed to be planted.
			for i: int in baselines.size():
				if baselines[i] != baseline:
					_fail("'%s' frame %d baseline row %d != %d (sprite will float)"
						% [anim, i, baselines[i], baseline])
		elif anim == &"run":
			for i: int in baselines.size():
				var hop: int = baseline - baselines[i]
				if hop < 0:
					_fail("'run' frame %d sinks below the baseline (row %d)" % [i, baselines[i]])
				elif hop > MAX_RUN_HOP:
					_fail("'run' frame %d hops %dpx (max %d) — reads as detaching from its shadow"
						% [i, hop, MAX_RUN_HOP])
			if baselines[0] != baseline or baselines[baselines.size() - 1] != baseline:
				_fail("'run' must start and end planted, or the loop seam pops")
		elif anim in [&"death", &"emerge", &"special"]:
			# These legitimately leave the standing pose; they just must never
			# sink THROUGH the ground plane.
			for i: int in baselines.size():
				if baselines[i] > baseline:
					_fail("'%s' frame %d sinks below the baseline (row %d)"
						% [anim, i, baselines[i]])

		print("skin : %-8s %d frames  loop=%s  %.0f fps  baselines=%s" % [
			anim, got, skin.get_animation_loop(anim), skin.get_animation_speed(anim), baselines])

	# Loop flags: a looping one-shot never releases the AnimationTree, and a
	# non-looping idle freezes on its last frame.
	for anim: StringName in [&"idle", &"run"]:
		if skin.has_animation(anim) and not skin.get_animation_loop(anim):
			_fail("'%s' must loop" % anim)
	for anim: StringName in [&"attack", &"death", &"special", &"emerge"]:
		if skin.has_animation(anim) and skin.get_animation_loop(anim):
			_fail("'%s' must NOT loop — it is a one-shot" % anim)
	if skin.has_animation(&"run") and skin.get_frame_count(&"run") < 4:
		_fail("'run' has %d frames — too few to read as locomotion"
			% skin.get_frame_count(&"run"))
	# The death collapse has to actually collapse, or "emerge" plays backwards
	# into nothing on spawn.
	if skin.has_animation(&"death") and skin.has_animation(&"emerge"):
		if skin.get_frame_count(&"death") != skin.get_frame_count(&"emerge"):
			_fail("death and emerge differ in length — emerge IS the collapse reversed")


## No dead air: every cast must be ANIMATING for its whole window. This skin
## ships no 'cast_staff', so BossController._pose() falls back to cast_anim for
## the ranged casts -- deliberate (his 'special' IS the flare, and a synthesised
## weapon-thrust would be a near-duplicate of 'attack'), but it means cast_anim
## has to cover every window here, so it is checked against all of them.
func _check_casts(boss: EnemyTypeResource, skin: SpriteFrames) -> void:
	if not skin.has_animation(boss.cast_anim):
		_fail("cast_anim '%s' is not on the skin — casts would play nothing" % boss.cast_anim)
		return
	if skin.has_animation(&"cast_staff"):
		print("anim : skin now ships 'cast_staff'; ranged casts will prefer it")

	var clip: float = float(skin.get_frame_count(boss.cast_anim)) \
		/ (skin.get_animation_speed(boss.cast_anim) * SPRITE_SPEED_SCALE)
	var casts: Array = [
		["slam", boss.slam_windup_s],
		["laser", boss.laser_windup_s],
		["cinder lash", boss.sweep_windup_s + boss.sweep_duration_s],
		["static arc", boss.chain_windup_s],
		["enrage pose", 1.4],
	]
	for row: Array in casts:
		var window: float = row[1]
		if window <= 0.0:
			continue
		var stretch: float = window / clip
		if stretch > MAX_STRETCH:
			_fail("%s stretches '%s' %.1fx (%.2fs clip over %.2fs) — will read as frozen"
				% [row[0], boss.cast_anim, stretch, clip, window])
		else:
			print("anim : %-12s %.2fs window / %.2fs '%s' = %.1fx stretch"
				% [row[0], window, clip, boss.cast_anim, stretch])

	# The meteor volley animates per rock instead of stretching one clip.
	if boss.meteor_count > 0:
		var src: FileAccess = FileAccess.open(CONTROLLER, FileAccess.READ)
		if src == null:
			_fail("could not read %s" % CONTROLLER)
		else:
			var text: String = src.get_as_text()
			src.close()
			if not text.contains("func _drop_meteor"):
				_fail("_drop_meteor is gone — the per-meteor hurl animation went with it")
			else:
				var volley: float = boss.meteor_windup_s \
					+ boss.meteor_stagger_s * float(boss.meteor_count - 1)
				print("anim : ember rain  %.2fs volley as %d hurls every %.2fs"
					% [volley, boss.meteor_count, boss.meteor_stagger_s])


func _check_kit(boss: EnemyTypeResource) -> void:
	if boss.enrage_health_fraction <= 0.0 or boss.enrage_health_fraction >= 1.0:
		_fail("enrage_health_fraction %.2f never fires" % boss.enrage_health_fraction)
	# A phase-2-only spell on a boss that cannot reach phase 2 is dead content.
	for row: Array in [
		["static arc", boss.chain_targets > 0, boss.chain_phase],
		["cinder lash", boss.sweep_arc_deg > 0.0, boss.sweep_phase],
		["ember rain", boss.meteor_count > 0, boss.meteor_phase],
	]:
		if row[1] and int(row[2]) == 2 and boss.enrage_health_fraction <= 0.0:
			_fail("%s is phase-2 only but the boss never enrages" % row[0])
	# Killing Frost draws hard-coded ice. Deliberately off on a solar boss: if it
	# is ever switched on, the arena freezes over mid-fire-phase.
	if boss.frost_safe_radius > 0.0:
		_fail("frost_safe_radius is set — Killing Frost renders ice VFX on a fire boss")
	# The whole point of the enrage is that the fight visibly changes hands.
	if boss.enraged_telegraph_element < 0:
		_fail("enraged_telegraph_element is -1 — phase 2 looks identical to phase 1")
	elif boss.enraged_telegraph_element == boss.telegraph_element:
		_fail("enrage keeps telegraph element %d — no visible phase change"
			% boss.telegraph_element)
	# Enraged cadences must actually be faster, or enrage is a downgrade.
	for row: Array in [
		["slam", boss.slam_interval_s, boss.enraged_slam_interval_s],
		["laser", boss.laser_interval_s, boss.enraged_laser_interval_s],
		["arm shot", boss.arm_shot_interval_s, boss.enraged_arm_shot_interval_s],
		["ember rain", boss.meteor_interval_s, boss.enraged_meteor_interval_s],
		["cinder lash", boss.sweep_interval_s, boss.enraged_sweep_interval_s],
		["static arc", boss.chain_interval_s, boss.enraged_chain_interval_s],
	]:
		var base: float = row[1]
		var fast: float = row[2]
		if base > 0.0 and fast > 0.0 and fast >= base:
			_fail("%s enraged interval %.1fs is not faster than %.1fs" % [row[0], fast, base])
	print("kit  : enrage at %.0f%% hp, telegraph %d -> %d, %d adds of '%s'" % [
		boss.enrage_health_fraction * 100.0, boss.telegraph_element,
		boss.enraged_telegraph_element, boss.add_count, boss.add_enemy_slug])


## The spell fields live on the SHARED EnemyTypeResource, so the thing most
## likely to break is a boss nobody was asked to change.
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
		if not added.is_empty():
			_fail("%s picked up %s" % [path.get_file(), ", ".join(added)])
	print("prior: %d pre-existing bosses still gate the spell kit off" % PRIOR_BOSSES.size())


## HostileNpc.body_scale() replaced visual_scale at four "how big is this mob"
## call sites (aim assist, melee reach, bar lift, bar scale). It is floored at
## visual_scale precisely so it can never change an existing mob — but that is an
## argument, and this is the proof. Every registered enemy EXCEPT this one must
## come out exactly equal to its visual_scale.
##
## Mirrors the formula rather than instantiating bodies: a HostileNpc needs a
## scene tree and the client autoloads, neither of which exists in a -s run.
func _check_body_scale_is_inert() -> void:
	var index: ContentIndex = load(INDEX) as ContentIndex
	if index == null:
		return
	var checked := 0
	var skipped := 0
	var moved: PackedStringArray = PackedStringArray()
	for e: Dictionary in index.entries:
		var slug: StringName = e.get(&"slug", &"")
		var data: EnemyTypeResource = null
		# Six boss types drop *.item.tres weapons whose script chain reaches
		# weapon.gd, which needs the Client autoload; those cannot be loaded here.
		if ResourceLoader.exists(e.get(&"path", "")):
			data = load(e[&"path"]) as EnemyTypeResource
		if data == null or data.skin == null:
			skipped += 1
			continue
		var vs: float = maxf(0.1, data.visual_scale)
		var effective: float = vs
		var frames: SpriteFrames = data.skin
		if frames.has_animation(&"idle") and frames.get_frame_count(&"idle") > 0:
			var tex: AtlasTexture = frames.get_frame_texture(&"idle", 0) as AtlasTexture
			if tex != null and tex.atlas != null:
				var img: Image = tex.atlas.get_image()
				if img != null:
					var used: Rect2i = img.get_region(Rect2i(tex.region)).get_used_rect()
					if used.size.y > 0:
						effective = maxf(vs, float(used.size.y) * vs / 64.0)
		checked += 1
		if slug == SLUG:
			if is_equal_approx(effective, vs):
				_fail("body_scale is inert for %s too — the 144px art gained nothing" % slug)
			else:
				print("scale: %-22s visual_scale %.2f -> body_scale %.2f (the fix)"
					% [slug, vs, effective])
			continue
		if not is_equal_approx(effective, vs):
			moved.append("%s %.2f->%.2f" % [slug, vs, effective])
	if moved.is_empty():
		print("scale: body_scale inert for all %d other enemy types (%d unloadable, skipped)"
			% [checked - 1, skipped])
	else:
		_fail("body_scale changed %d pre-existing enemies: %s"
			% [moved.size(), ", ".join(moved)])


## Does the body ARTICULATE, or is it one picture being deformed?
##
## This is the check the first version of these clips would have failed. With a
## single static source pose the tempting synthesis is to lean/squash the whole
## sprite per frame, which passes every other assertion here — frame counts,
## baselines, loop flags, borders — while the axe never actually moves relative
## to the torso. It reads as a wobbling photograph.
##
## The test that separates them: track the WEAPON TIP relative to the body's own
## centre. Under a whole-body deform the axe is carried along with the torso and
## that offset barely changes; only an articulated arm moves it.
##
## Measured on both versions of this very sheet: the whole-body deform moved the
## axe 1.5px relative to the body across the entire swing, the cutout rig moves
## it 24.7px. A silhouette-overlap test was tried first and does NOT separate
## them — the deform's own widen/lean distorts the outline about as much as a
## real swing does, and both scored ~0.7, so it would have passed the version
## this check exists to reject.
##
## Fraction of frame width the weapon must travel relative to the body.
const MIN_WEAPON_TRAVEL := 0.05


func _check_articulated(skin: SpriteFrames) -> void:
	var clip := &"attack"
	if not skin.has_animation(clip) or skin.get_frame_count(clip) < 2:
		return
	var lo: float = INF
	var hi: float = -INF
	var size: float = 0.0
	for i: int in skin.get_frame_count(clip):
		var tex: AtlasTexture = skin.get_frame_texture(clip, i) as AtlasTexture
		if tex == null or tex.atlas == null:
			return
		var img: Image = tex.atlas.get_image()
		if img == null:
			return
		var r: Rect2 = tex.region
		size = r.size.x
		var sum_x: float = 0.0
		var count: int = 0
		var tip: int = int(r.size.x)
		var half: int = int(r.size.y) / 2
		for y: int in int(r.size.y):
			for x: int in int(r.size.x):
				if img.get_pixel(int(r.position.x) + x, int(r.position.y) + y).a <= 0.25:
					continue
				sum_x += float(x)
				count += 1
				# The axe hangs low, so the lower half isolates it from the wings.
				if y >= half:
					tip = mini(tip, x)
		if count == 0:
			return
		var rel: float = float(tip) - sum_x / float(count)
		lo = minf(lo, rel)
		hi = maxf(hi, rel)
	var travel: float = hi - lo
	var need: float = size * MIN_WEAPON_TRAVEL
	if travel < need:
		_fail(("'attack' is not articulated — the weapon moves %.1fpx relative to the "
			+ "body (need %.1f). The whole sprite is being deformed instead of the arm "
			+ "swinging.") % [travel, need])
	else:
		print("anim : 'attack' articulates — weapon travels %.1fpx relative to the body"
			% travel)



func _finish() -> void:
	if _fails.is_empty():
		print("VERIFY_PASS")
		quit(0)
	else:
		printerr("VERIFY_FAIL (%d)" % _fails.size())
		quit(1)
