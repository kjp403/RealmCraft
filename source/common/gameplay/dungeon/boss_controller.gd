class_name BossController
extends Node
## The BRAIN of a dungeon boss. The boss itself stays a plain HostileNpc (the BODY:
## moves, basic-attacks, takes damage, dies); this node watches the body's HP and
## orchestrates the fight on top — phase transition, a telegraphed slam, optional
## laser / arm-cannon pressure, and an enrage that summons adds + speeds the body up.
## Every move is composed from primitives that ALREADY exist (AttackTelegraph via the
## body's rp_lunge_telegraph, CastTelegraph via rp_cast_telegraph, container.spawn_dynamic
## for summons, plain Projectile for arm shots), so none of it bloats HostileNpc.
##
## RoomNode attaches one to a boss marker's mob on spawn. Server-only: it frees
## itself anywhere else (and since it's added AFTER the dynamic spawn, clients never
## receive it). Tuning is data-driven from the body's EnemyTypeResource (the vars
## below are fallbacks that mirror the resource defaults — see _load_config).

## Extra seconds the body stays planted AFTER a slam lands — sells the weight and
## stops the boss snapping straight back into a chase.
const SLAM_RECOVER_S: float = 0.25
const LASER_RECOVER_S: float = 0.2
const ARM_RECOVER_S: float = 0.15

## Enrage when the body drops to this fraction of max HP.
var enrage_at_health_fraction: float = 0.5
## Slam danger-zone: radius (px), the windup players have to leave it, and the hit.
var slam_radius: float = 110.0
var slam_windup_s: float = 1.1
var slam_damage: float = 45.0
## Seconds between slams — phase 1, then the faster enraged cadence.
var slam_interval_s: float = 6.0
var enraged_slam_interval_s: float = 3.5
## Optional laser corridor (0 range = off). Forces a SIDESTEP dodge.
var laser_range: float = 0.0
var laser_width: float = 28.0
var laser_windup_s: float = 1.15
var laser_damage: float = 55.0
var laser_interval_s: float = 8.0
var enraged_laser_interval_s: float = 5.0
## Optional arm-cannon bolt (0 interval = off). A slow projectile to weave through.
var arm_shot_interval_s: float = 0.0
var arm_shot_damage: float = 40.0
var arm_shot_speed: float = 220.0
var arm_shot_lifetime_s: float = 1.4
var enraged_arm_shot_interval_s: float = 0.0
## Adds summoned the moment the boss enrages.
var add_enemy_slug: StringName = &"rat_base"
var add_count: int = 2
var add_spread_px: float = 48.0
## Move-speed multiplier applied on enrage (the body chases harder).
var enrage_speed_mult: float = 1.3

## SpriteFrames swapped in on enrage (see EnemyTypeResource.phase2_skin).
var phase2_skin: String = ""
## Skin clip for a generic cast wind-up (see EnemyTypeResource.cast_anim).
var cast_anim: StringName = &"special"
## Telegraph tint (ElementalTelegraph.Element as int) before / after enrage.
var telegraph_element: int = 0
var enraged_telegraph_element: int = -1
## EMBER RAIN — staggered meteor volley.
var meteor_count: int = 0
var meteor_radius: float = 56.0
var meteor_damage: float = 60.0
var meteor_windup_s: float = 1.5
var meteor_stagger_s: float = 0.45
var meteor_spread_px: float = 190.0
var meteor_interval_s: float = 11.0
var enraged_meteor_interval_s: float = 0.0
var meteor_phase: int = 0
## CINDER LASH — sweeping beam.
var sweep_arc_deg: float = 0.0
var sweep_range: float = 300.0
var sweep_width: float = 34.0
var sweep_windup_s: float = 1.2
var sweep_duration_s: float = 1.1
var sweep_damage: float = 70.0
var sweep_interval_s: float = 12.0
var enraged_sweep_interval_s: float = 0.0
var sweep_phase: int = 0
## KILLING FROST — inverted safe-zone.
var frost_safe_radius: float = 0.0
var frost_windup_s: float = 2.6
var frost_damage: float = 110.0
var frost_offset_px: float = 150.0
var frost_interval_s: float = 16.0
var enraged_frost_interval_s: float = 0.0
var frost_phase: int = 0
## STATIC ARC — chain lightning.
var chain_targets: int = 0
var chain_range: float = 170.0
var chain_damage: float = 45.0
var chain_windup_s: float = 0.9
var chain_interval_s: float = 9.0
var enraged_chain_interval_s: float = 0.0
var chain_phase: int = 0

## How long a meteor visually falls before it lands (the tail of its wind-up).
const METEOR_FALL_S: float = 0.42
## Damage tick while the Cinder Lash sweeps — fine enough that nobody the beam
## crosses is skipped, coarse enough not to flood the instance with checks.
const SWEEP_TICK_S: float = 0.07
## How long the enrage transform pose is held. Long enough to read as a phase
## change rather than a twitch, short enough not to gate the first phase-2 move.
const ENRAGE_POSE_S: float = 1.4

## The body this brain drives. Set by the spawner before add_child.
var boss: HostileNpc

var _enraged: bool = false
var _casting: bool = false
var _engaged: bool = false
## The move table, built in _load_config. One entry per ENABLED mechanic:
##   id, fn, base/rage interval (s), phase gate (0 both / 1 pre / 2 post enrage),
##   floor (minimum seconds after a pull before it may fire), next (ready time ms).
## Replaces the three hand-rolled _next_*_ms counters — the kit is now open-ended,
## so adding a spell is one append here instead of another counter + match arm.
var _moves: Array[Dictionary] = []
## Round-robin cursor so several ready moves don't all fire on the same frame —
## keeps the dodge pressure readable instead of dumping the whole kit at once.
var _next_move: int = 0


func _ready() -> void:
	if not multiplayer.is_server() or boss == null:
		queue_free()
		return
	_load_config()
	# Prime cooldowns now, but re-arm on first engage — Hollow golems sit from
	# instance charge with no target, so spawn-primed timers expire before pull.
	_arm_pull_grace()
	# Victory sting on death. Fight music cues on first engage (covers Hollow /
	# late joiners). Admin abort (boss removed WITHOUT dying) is "end" via EventService.
	boss.died.connect(_on_boss_died_music)


## Push every cooldown out by a fresh grace window so a pull always opens with a
## chase, never a stack of ready casts. Uses maxf — maxi truncates 9.5 → 9.
func _arm_pull_grace() -> void:
	var now: int = Time.get_ticks_msec()
	for move: Dictionary in _moves:
		move["next"] = now + int(maxf(move["base"], move["floor"]) * 1000.0)


## Server → clients: a boss-event music cue (fight / victory / end) for everyone in
## [param instance]. Static so EventService can fire "end" on an admin abort too.
static func push_boss_music(instance: Node, state: String) -> void:
	if instance == null or WorldServer.curr == null:
		return
	for peer_id: int in instance.players_by_peer_id:
		WorldServer.curr.data_push.rpc_id(peer_id, &"boss.music", {"state": state})


func _on_boss_died_music(_killer: Character) -> void:
	push_boss_music(_instance(), "victory")
	# Mecha golem respawns: drop phase-2 state + speed buff so the next fight
	# gets its enrage, adds, and cadence back.
	_enraged = false
	_engaged = false
	_casting = false
	if is_instance_valid(boss) and boss.enemy_data != null:
		boss.move_speed = boss.enemy_data.move_speed


## Pull tuning from the body's EnemyTypeResource so each boss is configured in
## data. The var defaults mirror the resource defaults, so a boss whose .tres
## leaves the Boss group untouched behaves exactly as before.
func _load_config() -> void:
	var d: EnemyTypeResource = boss.enemy_data
	if d == null:
		return
	enrage_at_health_fraction = d.enrage_health_fraction
	slam_radius = d.slam_radius
	slam_windup_s = d.slam_windup_s
	slam_damage = d.slam_damage
	slam_interval_s = d.slam_interval_s
	enraged_slam_interval_s = d.enraged_slam_interval_s
	laser_range = d.laser_range
	laser_width = d.laser_width
	laser_windup_s = d.laser_windup_s
	laser_damage = d.laser_damage
	laser_interval_s = d.laser_interval_s
	enraged_laser_interval_s = d.enraged_laser_interval_s
	arm_shot_interval_s = d.arm_shot_interval_s
	arm_shot_damage = d.arm_shot_damage
	arm_shot_speed = d.arm_shot_speed
	arm_shot_lifetime_s = d.arm_shot_lifetime_s
	enraged_arm_shot_interval_s = (
		d.enraged_arm_shot_interval_s if d.enraged_arm_shot_interval_s > 0.0
		else d.arm_shot_interval_s * 0.65
	)
	add_enemy_slug = d.add_enemy_slug
	add_count = d.add_count
	add_spread_px = d.add_spread_px
	enrage_speed_mult = d.enrage_speed_mult
	cast_anim = d.cast_anim
	phase2_skin = d.phase2_skin
	telegraph_element = d.telegraph_element
	enraged_telegraph_element = d.enraged_telegraph_element
	meteor_count = d.meteor_count
	meteor_radius = d.meteor_radius
	meteor_damage = d.meteor_damage
	meteor_windup_s = d.meteor_windup_s
	meteor_stagger_s = d.meteor_stagger_s
	meteor_spread_px = d.meteor_spread_px
	meteor_interval_s = d.meteor_interval_s
	enraged_meteor_interval_s = d.enraged_meteor_interval_s
	meteor_phase = d.meteor_phase
	sweep_arc_deg = d.sweep_arc_deg
	sweep_range = d.sweep_range
	sweep_width = d.sweep_width
	sweep_windup_s = d.sweep_windup_s
	sweep_duration_s = d.sweep_duration_s
	sweep_damage = d.sweep_damage
	sweep_interval_s = d.sweep_interval_s
	enraged_sweep_interval_s = d.enraged_sweep_interval_s
	sweep_phase = d.sweep_phase
	frost_safe_radius = d.frost_safe_radius
	frost_windup_s = d.frost_windup_s
	frost_damage = d.frost_damage
	frost_offset_px = d.frost_offset_px
	frost_interval_s = d.frost_interval_s
	enraged_frost_interval_s = d.enraged_frost_interval_s
	frost_phase = d.frost_phase
	chain_targets = d.chain_targets
	chain_range = d.chain_range
	chain_damage = d.chain_damage
	chain_windup_s = d.chain_windup_s
	chain_interval_s = d.chain_interval_s
	enraged_chain_interval_s = d.enraged_chain_interval_s
	chain_phase = d.chain_phase
	_build_moves()


## One row per ENABLED mechanic. A spell whose gate is 0 never enters the table,
## so a boss that defines none behaves exactly like the original slam/laser/arm
## controller. "rage" of 0 means "no separate enraged cadence, reuse base".
func _build_moves() -> void:
	_moves.clear()
	_add_move(&"slam", _slam, slam_interval_s, enraged_slam_interval_s, 0, 4.0)
	if laser_range > 0.0:
		_add_move(&"laser", _laser, laser_interval_s, enraged_laser_interval_s, 0, 5.5)
	if arm_shot_interval_s > 0.0:
		_add_move(&"arm", _arm_shot, arm_shot_interval_s, enraged_arm_shot_interval_s, 0, 3.5)
	if meteor_count > 0:
		_add_move(&"meteor", _meteor_rain, meteor_interval_s, enraged_meteor_interval_s,
			meteor_phase, 6.0)
	if sweep_arc_deg > 0.0:
		_add_move(&"sweep", _cinder_lash, sweep_interval_s, enraged_sweep_interval_s,
			sweep_phase, 7.0)
	if frost_safe_radius > 0.0:
		_add_move(&"frost", _killing_frost, frost_interval_s, enraged_frost_interval_s,
			frost_phase, 8.0)
	if chain_targets > 0:
		_add_move(&"chain", _static_arc, chain_interval_s, enraged_chain_interval_s,
			chain_phase, 5.0)


func _add_move(
		id: StringName, fn: Callable, base: float, rage: float, phase: int, floor_s: float
	) -> void:
	_moves.append({
		"id": id, "fn": fn, "base": base,
		"rage": rage if rage > 0.0 else base,
		"phase": phase, "floor": floor_s, "next": 0,
	})


## Pose clip for a specific school of spell, when the skin ships one. A skin
## without it falls back to the boss's generic cast clip, so every pre-existing
## boss keeps exactly the animation it had — the new poses are opt-in art.
func _pose(preferred: StringName) -> StringName:
	var skin: SpriteFrames = boss.enemy_data.skin if boss.enemy_data != null else null
	if skin != null and skin.has_animation(preferred):
		return preferred
	return cast_anim


## Element the telegraphs should draw in right now.
func _element() -> int:
	if _enraged and enraged_telegraph_element >= 0:
		return enraged_telegraph_element
	return telegraph_element


## Re-arm one move after it resolves.
func _rearm(id: StringName) -> void:
	for move: Dictionary in _moves:
		if move["id"] == id:
			move["next"] = Time.get_ticks_msec() + int(
				(move["rage"] if _enraged else move["base"]) * 1000.0)
			return


## Every living player in the boss's instance — the damage set for every AoE here.
func _live_players() -> Array[Player]:
	var out: Array[Player] = []
	var instance: Node = _instance()
	if instance == null:
		return out
	for peer_id: int in instance.players_by_peer_id:
		var player: Player = instance.players_by_peer_id[peer_id]
		if player != null and is_instance_valid(player) and not player.is_dead:
			out.append(player)
	return out


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(boss) or boss.is_dead:
		return
	if not _enraged and _health_fraction() <= enrage_at_health_fraction:
		_enrage()
	# Only cast while someone is actually engaging — no flailing at an empty room.
	if boss.targeted_player == null:
		_engaged = false
		return
	if not _engaged:
		_engaged = true
		_arm_pull_grace()
		push_boss_music(_instance(), "fight")
	if _casting:
		return
	if _moves.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	# Prefer the next move in rotation when several are ready — forces a mix of
	# dodge shapes (step out / sidestep / weave / run in) instead of slam spam.
	for i: int in _moves.size():
		var idx: int = (_next_move + i) % _moves.size()
		var move: Dictionary = _moves[idx]
		if not _phase_allows(move["phase"]):
			continue
		if now < int(move["next"]):
			continue
		_next_move = (idx + 1) % _moves.size()
		(move["fn"] as Callable).call()
		return


## Phase gate: 0 = always, 1 = only before enrage, 2 = only after.
func _phase_allows(phase: int) -> bool:
	match phase:
		1: return not _enraged
		2: return _enraged
		_: return true


func _health_fraction() -> float:
	var max_h: float = boss.stats_component.get_stat(Stat.HEALTH_MAX)
	if max_h <= 0.0:
		return 1.0
	return boss.stats_component.get_stat(Stat.HEALTH) / max_h


## Telegraph a danger ring at the boss, give players the windup to step out, then
## hit everyone still inside it. Reuses rp_lunge_telegraph — with the target point
## AT the boss, its AttackTelegraph draws a CIRCLE (line_to == 0), world-pinned.
func _slam() -> void:
	_casting = true
	var center: Vector2 = boss.global_position
	boss._face_target()
	# Commit the body: hold position through the wind-up + a short recovery so it
	# doesn't stroll out of its own danger ring while the slam resolves.
	boss.action_root_until_ms = Time.get_ticks_msec() + int((slam_windup_s + SLAM_RECOVER_S) * 1000.0)
	boss.replicate_visual(&"rp_play_skin_anim", [cast_anim, slam_windup_s])
	# Filling telegraph (converging ring + clock wedge) — players read WHEN it
	# lands, and the element tint says WHOSE move it is.
	boss.replicate_visual(&"rp_elem_telegraph",
		[center, slam_radius, slam_windup_s, _element(), 0])
	await get_tree().create_timer(slam_windup_s).timeout
	if not is_instance_valid(boss) or boss.is_dead:
		_casting = false
		return
	# Impact: the ground burst + damage everyone still standing in the ring.
	boss.replicate_visual(&"rp_slam_impact", [center, slam_radius])
	var instance: Node = _instance()
	if instance != null:
		for peer_id: int in instance.players_by_peer_id:
			var player: Player = instance.players_by_peer_id[peer_id]
			if player != null and not player.is_dead \
					and center.distance_to(player.global_position) <= slam_radius:
				player.take_damage(slam_damage, boss)
	_rearm(&"slam")
	_casting = false


## Locked-aim laser corridor: telegraph a strip toward the target, then blast
## anyone still on the line. Sidestep is the only clean dodge (backing up stays
## inside the corridor — same lesson as LungeBehavior).
func _laser() -> void:
	_casting = true
	var target: Player = boss.targeted_player
	if target == null or not is_instance_valid(target):
		_casting = false
		return
	boss._face_target()
	# Face first, THEN read the muzzle: it mirrors with the body, so sampling it
	# before the turn would aim the beam out of the boss's back.
	var pose: StringName = _pose(&"cast_staff")
	var origin: Vector2 = boss.muzzle_position(pose == &"cast_staff")
	var dir: Vector2 = origin.direction_to(target.global_position)
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var end: Vector2 = origin + dir * laser_range
	boss.action_root_until_ms = Time.get_ticks_msec() + int((laser_windup_s + LASER_RECOVER_S) * 1000.0)
	boss.replicate_visual(&"rp_play_skin_anim", [pose, laser_windup_s])
	boss.replicate_visual(&"rp_hand_charge",
		[_element(), laser_windup_s, pose == &"cast_staff"])
	boss.replicate_visual(&"rp_lunge_telegraph",
		[end, laser_width, laser_windup_s + 0.15, origin, _element()])
	await get_tree().create_timer(laser_windup_s).timeout
	if not is_instance_valid(boss) or boss.is_dead:
		_casting = false
		return
	boss.replicate_visual(&"rp_laser_beam", [origin, end, 0.4])
	var instance: Node = _instance()
	if instance != null:
		for peer_id: int in instance.players_by_peer_id:
			var player: Player = instance.players_by_peer_id[peer_id]
			if player == null or player.is_dead:
				continue
			if _dist_to_segment(player.global_position, origin, end) <= laser_width:
				player.take_damage(laser_damage, boss)
	_rearm(&"laser")
	_casting = false


## Slow arm-cannon bolt aimed at the current target — weave sideways to dodge.
func _arm_shot() -> void:
	_casting = true
	var target: Player = boss.targeted_player
	if target == null or not is_instance_valid(target):
		_casting = false
		return
	var dir: Vector2 = boss.global_position.direction_to(target.global_position)
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	boss._face_target()
	boss.action_root_until_ms = Time.get_ticks_msec() + int(ARM_RECOVER_S * 1000.0)
	boss.replicate_visual(&"rp_play_skin_anim", [&"attack"])
	boss.fire_arm_projectile(dir, arm_shot_speed, arm_shot_lifetime_s, arm_shot_damage)
	_rearm(&"arm")
	_casting = false


# ---------------------------------------------------------------------------
# Spell kit. Every one of these follows the same contract as _slam: root the
# body, telegraph on every client, await the wind-up, then resolve damage on the
# SERVER against the same geometry the telegraph drew. Clients never decide a
# hit — they only draw what is about to happen.
# ---------------------------------------------------------------------------

## EMBER RAIN — a staggered volley. Each meteor telegraphs independently, so the
## ground fills with overlapping circles and standing still stops being viable
## partway through. Deliberately not one big circle: the interest is in having to
## pick a NEW spot several times while the boss is still chasing you.
func _meteor_rain() -> void:
	_casting = true
	boss._face_target()
	var volley_s: float = meteor_windup_s + meteor_stagger_s * float(maxi(meteor_count - 1, 0))
	boss.action_root_until_ms = Time.get_ticks_msec() + int((volley_s + 0.25) * 1000.0)
	for _i: int in meteor_count:
		if not is_instance_valid(boss) or boss.is_dead:
			break
		_drop_meteor(_meteor_spot())
		await get_tree().create_timer(meteor_stagger_s).timeout
	# Hold the cast lock until the LAST meteor has landed, so the next move never
	# starts under a sky that is still full of falling rock.
	await get_tree().create_timer(meteor_windup_s).timeout
	_rearm(&"meteor")
	_casting = false


## Where one meteor lands: on a random living player, scattered by up to most of
## the blast radius so it threatens without being an unavoidable hit, and clamped
## so a volley stays in the arena around the boss.
func _meteor_spot() -> Vector2:
	var origin: Vector2 = boss.global_position
	var players: Array[Player] = _live_players()
	var at: Vector2
	if players.is_empty():
		at = origin + Vector2.from_angle(randf() * TAU) * randf_range(40.0, meteor_spread_px)
	else:
		var mark: Player = players[randi() % players.size()]
		at = mark.global_position \
			+ Vector2.from_angle(randf() * TAU) * randf_range(0.0, meteor_radius * 0.8)
	var offset: Vector2 = at - origin
	if offset.length() > meteor_spread_px:
		at = origin + offset.normalized() * meteor_spread_px
	return at


## One meteor: circle now, comet through the last stretch, blast on landing.
## Fire-and-forget — the volley loop does not await it, so meteors overlap.
func _drop_meteor(at: Vector2) -> void:
	# One hurl gesture per rock, so the body is animating for the whole volley
	# rather than throwing once and standing still through the other three.
	boss.replicate_visual(&"rp_play_skin_anim", [&"attack"])
	boss.replicate_visual(&"rp_elem_telegraph", [at, meteor_radius, meteor_windup_s, 0, 0])
	await get_tree().create_timer(maxf(meteor_windup_s - METEOR_FALL_S, 0.0)).timeout
	if not is_instance_valid(boss) or boss.is_dead:
		return
	boss.replicate_visual(&"rp_meteor_fall", [at, METEOR_FALL_S, meteor_radius])
	await get_tree().create_timer(METEOR_FALL_S).timeout
	if not is_instance_valid(boss) or boss.is_dead:
		return
	for player: Player in _live_players():
		if at.distance_to(player.global_position) <= meteor_radius:
			player.take_damage(meteor_damage, boss)


## CINDER LASH — a beam that travels through an arc. The fixed laser corridor is
## beaten by one sidestep; this punishes standing anywhere in the swept wedge, so
## the answer is to cross the beam early or get behind where it starts. The sweep
## direction is coin-flipped per cast so the safe side cannot be memorised.
func _cinder_lash() -> void:
	_casting = true
	var target: Player = boss.targeted_player
	if target == null or not is_instance_valid(target):
		_casting = false
		return
	boss._face_target()
	var pose: StringName = _pose(&"cast_staff")
	var origin: Vector2 = boss.muzzle_position(pose == &"cast_staff")
	var aim: float = origin.direction_to(target.global_position).angle()
	var half: float = deg_to_rad(sweep_arc_deg) * 0.5
	var spin: float = 1.0 if randf() < 0.5 else -1.0
	var a0: float = aim - half * spin
	var a1: float = aim + half * spin
	boss.action_root_until_ms = Time.get_ticks_msec() \
		+ int((sweep_windup_s + sweep_duration_s + 0.2) * 1000.0)
	boss.replicate_visual(&"rp_play_skin_anim",
		[pose, sweep_windup_s + sweep_duration_s])
	boss.replicate_visual(&"rp_hand_charge",
		[_element(), sweep_windup_s, pose == &"cast_staff"])
	# Telegraph the STARTING line so the travel direction is readable before the
	# beam moves, not once it is already on top of you.
	boss.replicate_visual(&"rp_lunge_telegraph",
		[origin + Vector2.from_angle(a0) * sweep_range, sweep_width, sweep_windup_s, origin,
			_element()])
	await get_tree().create_timer(sweep_windup_s).timeout
	if not is_instance_valid(boss) or boss.is_dead:
		_casting = false
		return
	boss.replicate_visual(&"rp_sweep_beam", [origin, a0, a1, sweep_range, sweep_duration_s])
	# Walk the arc in ticks. a0/a1 are continuous (both derived from aim), so a
	# plain lerp is correct — lerp_angle takes the short way round and would
	# reverse a wide sweep.
	var burned: Dictionary = {}
	var steps: int = maxi(1, int(sweep_duration_s / SWEEP_TICK_S))
	for s: int in steps + 1:
		var angle: float = lerpf(a0, a1, float(s) / float(steps))
		var tip: Vector2 = origin + Vector2.from_angle(angle) * sweep_range
		for player: Player in _live_players():
			if burned.has(player.get_instance_id()):
				continue
			if _dist_to_segment(player.global_position, origin, tip) <= sweep_width:
				player.take_damage(sweep_damage, boss)
				burned[player.get_instance_id()] = true
		await get_tree().create_timer(SWEEP_TICK_S).timeout
		if not is_instance_valid(boss) or boss.is_dead:
			break
	_rearm(&"sweep")
	_casting = false


## KILLING FROST — the inversion. Every other telegraph in this game means "leave
## this circle"; this marks the only safe ground on the field. It lands AWAY from
## the boss on purpose: surviving costs melee uptime and the group has to break
## off together. This is the move the fight gets remembered for.
func _killing_frost() -> void:
	_casting = true
	var origin: Vector2 = boss.global_position
	var safe_at: Vector2 = origin + Vector2.from_angle(randf() * TAU) * frost_offset_px
	boss.action_root_until_ms = Time.get_ticks_msec() + int((frost_windup_s + 0.3) * 1000.0)
	boss.replicate_visual(&"rp_play_skin_anim", [&"special", frost_windup_s])
	# element 1 = frost, mode 1 = SAFE (the ring is the place to BE).
	boss.replicate_visual(&"rp_elem_telegraph",
		[safe_at, frost_safe_radius, frost_windup_s, 1, 1])
	_callout("Killing Frost — get to the circle!")
	await get_tree().create_timer(frost_windup_s).timeout
	if not is_instance_valid(boss) or boss.is_dead:
		_casting = false
		return
	boss.replicate_visual(&"rp_ice_spikes", [safe_at, frost_safe_radius, 7])
	boss.replicate_visual(&"rp_frost_nova", [origin, frost_safe_radius * 0.9])
	for player: Player in _live_players():
		if safe_at.distance_to(player.global_position) > frost_safe_radius:
			player.take_damage(frost_damage, boss)
	_rearm(&"frost")
	_casting = false


## STATIC ARC — jumps from the boss to its mark, then to whoever stands nearest
## that mark, and onward. Each link hits harder than the last, so a stacked melee
## pile eats the worst of it: the counterplay is spacing, not dodging.
func _static_arc() -> void:
	_casting = true
	var first: Player = boss.targeted_player
	if first == null or not is_instance_valid(first) or first.is_dead:
		_casting = false
		return
	boss._face_target()
	boss.action_root_until_ms = Time.get_ticks_msec() + int((chain_windup_s + 0.15) * 1000.0)
	var pose: StringName = _pose(&"cast_staff")
	boss.replicate_visual(&"rp_play_skin_anim", [pose, chain_windup_s])
	# Lightning gathers on the staff head for the whole wind-up — always storm-
	# tinted whatever the phase colour is, because this move IS the lightning.
	boss.replicate_visual(&"rp_hand_charge", [2, chain_windup_s, pose == &"cast_staff"])
	# element 2 = storm. A small ring on the mark: the warning is "you are it".
	boss.replicate_visual(&"rp_elem_telegraph",
		[first.global_position, 46.0, chain_windup_s, 2, 0])
	await get_tree().create_timer(chain_windup_s).timeout
	if not is_instance_valid(boss) or boss.is_dead:
		_casting = false
		return
	var pool: Array[Player] = _live_players()
	var path: PackedVector2Array = PackedVector2Array([boss.muzzle_position(pose == &"cast_staff")])
	var struck: Array[Player] = []
	var current: Player = first if pool.has(first) else null
	while current != null and struck.size() < chain_targets:
		struck.append(current)
		pool.erase(current)
		path.append(current.global_position)
		var nearest: Player = null
		var best: float = chain_range
		for other: Player in pool:
			var d: float = current.global_position.distance_to(other.global_position)
			if d <= best:
				best = d
				nearest = other
		current = nearest
	if path.size() >= 2:
		boss.replicate_visual(&"rp_chain_lightning", [path])
	for i: int in struck.size():
		struck[i].take_damage(chain_damage * (1.0 + 0.35 * float(i)), boss)
	_rearm(&"chain")
	_casting = false


## Server → clients: a one-line mechanic callout for everyone in the fight. The
## difference between a mechanic players learn and one they just die to is being
## told what it wants the first time they meet it.
func _callout(text: String) -> void:
	var instance: Node = _instance()
	if instance == null or WorldServer.curr == null:
		return
	for peer_id: int in instance.players_by_peer_id:
		WorldServer.curr.data_push.rpc_id(peer_id, &"boss.callout", {"text": text})


## Distance from [param point] to the closest point on segment [param a]→[param b].
func _dist_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq <= 0.0001:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(ab) / len_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)


## Phase 2: speed the body up, summon adds, and pull the next slam in so the shift
## reads as a real escalation.
func _enrage() -> void:
	_enraged = true
	boss.move_speed = int(boss.move_speed * enrage_speed_mult)
	for move: Dictionary in _moves:
		move["next"] = Time.get_ticks_msec() + int((move["rage"] as float) * 1000.0)
	_announce_enrage()
	_summon_adds.call_deferred() # spawn_dynamic toggles collision — defer out of the physics step


## Phase 2 is loud: a ground burst on the body + a danger banner & camera shake to
## everyone in the room, so the escalation reads instead of "suddenly more enemies
## and a faster boss" with no visible cause.
func _announce_enrage() -> void:
	var instance: Node = _instance()
	if instance == null:
		return
	# Play the transform clip if the skin has one, so the body VISIBLY changes
	# hands rather than just gaining a speed buff and a banner.
	# The body itself changes, not just its numbers: swap the skin FIRST so the
	# transform clip plays on the new art and the boss is already frozen when the
	# pose lands. Restored on respawn by rp_spawn_effect.
	if not phase2_skin.is_empty():
		boss.replicate_visual(&"rp_swap_skin", [phase2_skin])
	boss.replicate_visual(&"rp_play_skin_anim", [&"special", ENRAGE_POSE_S])
	# Detonate in the element the boss is turning INTO — a frost phase opens with
	# a frost nova, everything else keeps the ground burst.
	if _element() == 1:
		boss.replicate_visual(&"rp_frost_nova", [boss.global_position, slam_radius * 1.1])
	else:
		boss.replicate_visual(&"rp_slam_impact", [boss.global_position, slam_radius * 0.8])
	for peer_id: int in instance.players_by_peer_id:
		WorldServer.curr.data_push.rpc_id(peer_id, &"boss.enrage", {"name": boss.display_name})


func _summon_adds() -> void:
	if not is_instance_valid(boss) or boss.container == null:
		return
	var container: ReplicatedPropsContainer = boss.container
	for i: int in add_count:
		var angle: float = TAU * float(i) / float(maxi(add_count, 1))
		var spot: Vector2 = boss.global_position + Vector2.RIGHT.rotated(angle) * add_spread_px
		var add: Node = container.spawn_dynamic(
			ReplicatedPropsContainer.SCENE_HOSTILE_NPC,
			container.to_local(spot),
			{"enemy_type_slug": add_enemy_slug}
		)
		if add == null:
			continue
		RoomNode.make_dungeon_mob(add, false)
		var npc: HostileNpc = add as HostileNpc
		if npc == null:
			continue
		# World trash archetypes (yeti, demon adds, …) ship chase_on_area=false so
		# they don't jump skillers. Enrage summons must fight immediately — stamp
		# aggro + a spawn burst, and beef them a touch so they aren't free food.
		npc.apply_difficulty(1.75, 1.35)
		npc._process_synchronization()
		npc.action_root_until_ms = Time.get_ticks_msec() + int(HostileNpc.SPAWN_FREEZE_S * 1000.0)
		npc.replicate_visual(&"rp_spawn_effect", [])
		npc.engage_nearest_player()


## boss → ReplicatedPropsContainer → Map → ServerInstance.
func _instance() -> Node:
	if boss == null or boss.container == null:
		return null
	var map: Node = boss.container.get_parent()
	return map.get_parent() if map != null else null
