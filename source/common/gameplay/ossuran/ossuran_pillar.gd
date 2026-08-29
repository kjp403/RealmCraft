class_name OssuranPillar
extends Node
## The BRAIN of one of the three phase-2 pillars. The pillar itself is a plain
## [HostileNpc] body (it has HP, it takes hits, it dies, it replicates) — this
## node rides on top and gives it its attack, exactly the way [BossController]
## drives the boss. Attached as a child on spawn by [OssuranArena]; it frees
## itself anywhere but the world server.
##
## Each pillar answers one of the three combat styles, so the phase teaches the
## damage triangle while the group is running it:
##   * [constant Kind.EMBER]  red   — erupts under a player's feet, MELEE damage.
##   * [constant Kind.THORN]  green — hurls earth up at range, ARCHERY damage.
##   * [constant Kind.HEX]    purple— tracks a target with a beam, MAGIC damage.
##
## They are deliberately not on the same clock: each kind has its own interval
## and its own opening delay, so three pillars alive at once produce a staggered
## rhythm to dodge rather than one synchronised triple-hit that is either free or
## unsurvivable.

enum Kind {
	EMBER,  ## red — melee-type eruption
	THORN,  ## green — archery-type volley
	HEX,    ## purple — magic-type tracking beam
}

## Element index passed to the client telegraph, per kind. Ints because that is
## what crosses the wire (see [method HostileNpc.rp_elem_telegraph]).
const KIND_ELEMENT: Dictionary = {
	Kind.EMBER: 0,  # ElementalTelegraph.Element.FIRE
	Kind.THORN: 3,  # ElementalTelegraph.Element.EARTH
	Kind.HEX: 2,    # ElementalTelegraph.Element.STORM (purple)
}

## Per-kind tuning: windup, damage, geometry and cadence. Data rather than three
## near-identical methods, so retuning the phase is one table edit.
const TUNING: Dictionary = {
	Kind.EMBER: {
		"windup_s": 1.15, "damage": 52.0, "radius": 76.0,
		"interval_s": 4.6, "open_delay_s": 1.4, "targets": 1,
	},
	Kind.THORN: {
		"windup_s": 1.35, "damage": 44.0, "radius": 58.0,
		"interval_s": 3.8, "open_delay_s": 2.6, "targets": 2,
	},
	Kind.HEX: {
		"windup_s": 1.5, "damage": 58.0, "radius": 30.0,
		"interval_s": 5.4, "open_delay_s": 3.9, "targets": 1,
	},
}

## Half-width of the HEX beam. A player within this of the pillar→target segment
## is clipped, so the dodge is "get off the line", not "outrun the endpoint".
const BEAM_WIDTH: float = 30.0
## How long the beam is drawn for.
const BEAM_DRAW_S: float = 0.35

## The body this brain drives. Set by the arena before add_child.
var pillar: HostileNpc = null
var kind: Kind = Kind.EMBER

var _next_ms: int = 0
var _casting: bool = false


func _ready() -> void:
	if not GameMode.is_world_server():
		queue_free()
		return
	var spec: Dictionary = TUNING[kind]
	_next_ms = Time.get_ticks_msec() + int(float(spec["open_delay_s"]) * 1000.0)
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	if _casting or pillar == null or not is_instance_valid(pillar) or pillar.is_dead:
		return
	if Time.get_ticks_msec() < _next_ms:
		return
	var spec: Dictionary = TUNING[kind]
	_next_ms = Time.get_ticks_msec() + int(float(spec["interval_s"]) * 1000.0)
	match kind:
		Kind.EMBER:
			_cast_eruption(spec)
		Kind.THORN:
			_cast_volley(spec)
		Kind.HEX:
			_cast_beam(spec)


## RED — fire erupts under one player. Telegraphed on the ground where it will
## land, so the counter is simply to walk out of the circle.
func _cast_eruption(spec: Dictionary) -> void:
	var targets: Array[Player] = _pick_targets(1)
	if targets.is_empty():
		return
	_casting = true
	var at: Vector2 = targets[0].global_position
	var radius: float = float(spec["radius"])
	var windup: float = float(spec["windup_s"])
	pillar.replicate_visual(
		&"rp_elem_telegraph", [at, radius, windup, KIND_ELEMENT[kind], 0]
	)
	await get_tree().create_timer(windup).timeout
	if not _alive():
		_casting = false
		return
	pillar.replicate_visual(&"rp_slam_impact", [at, radius])
	_damage_circle(at, radius, float(spec["damage"]), CombatHit.DAMAGE_PHYSICAL)
	_casting = false


## GREEN — earth is torn up and thrown at up to two players at once. Smaller
## circles than the eruption but more of them, so it punishes clumping.
func _cast_volley(spec: Dictionary) -> void:
	var targets: Array[Player] = _pick_targets(int(spec["targets"]))
	if targets.is_empty():
		return
	_casting = true
	var radius: float = float(spec["radius"])
	var windup: float = float(spec["windup_s"])
	var marks: Array[Vector2] = []
	for player: Player in targets:
		var at: Vector2 = player.global_position
		marks.append(at)
		pillar.replicate_visual(
			&"rp_elem_telegraph", [at, radius, windup, KIND_ELEMENT[kind], 0]
		)
	await get_tree().create_timer(windup).timeout
	if not _alive():
		_casting = false
		return
	for at: Vector2 in marks:
		pillar.replicate_visual(&"rp_slam_impact", [at, radius])
		_damage_circle(at, radius, float(spec["damage"]), CombatHit.DAMAGE_RANGED)
	_casting = false


## PURPLE — a tracking beam. The telegraph sits on the TARGET so they know they
## are the one being aimed at; the beam then fires along the line the pillar had
## at the moment of release, which is what makes sidestepping work.
func _cast_beam(spec: Dictionary) -> void:
	var targets: Array[Player] = _pick_targets(1)
	if targets.is_empty():
		return
	_casting = true
	var mark: Player = targets[0]
	var windup: float = float(spec["windup_s"])
	pillar.replicate_visual(
		&"rp_elem_telegraph",
		[mark.global_position, float(spec["radius"]), windup, KIND_ELEMENT[kind], 0]
	)
	await get_tree().create_timer(windup).timeout
	if not _alive():
		_casting = false
		return
	# Re-read the target's position at RELEASE (not at windup) so the beam is
	# aimed where they committed to, then extend past them: the line keeps going,
	# so standing behind the target is not a safe spot.
	var from: Vector2 = pillar.global_position
	var toward: Vector2 = from
	if is_instance_valid(mark) and not mark.is_dead:
		toward = mark.global_position
	var direction: Vector2 = (toward - from)
	if direction.length_squared() < 1.0:
		direction = Vector2.RIGHT
	var to: Vector2 = from + direction.normalized() * maxf(320.0, from.distance_to(toward) + 90.0)
	pillar.replicate_visual(&"rp_laser_beam", [from, to, BEAM_DRAW_S])
	_damage_segment(from, to, float(spec["damage"]))
	_casting = false


## Damage every live player within [param radius] of [param at].
func _damage_circle(at: Vector2, radius: float, damage: float, type: StringName) -> void:
	for player: Player in _live_players():
		if player.global_position.distance_to(at) <= radius:
			player.take_damage(damage, pillar, type)


## Damage every live player within [constant BEAM_WIDTH] of segment a→b.
func _damage_segment(a: Vector2, b: Vector2, damage: float) -> void:
	for player: Player in _live_players():
		if _dist_to_segment(player.global_position, a, b) <= BEAM_WIDTH:
			player.take_damage(damage, pillar, CombatHit.DAMAGE_MAGIC)


## Up to [param count] live players, nearest first. Nearest-first (rather than
## random) keeps the pillars pressuring whoever is actually engaging them, so a
## group cannot park one player far away to soak every cast.
func _pick_targets(count: int) -> Array[Player]:
	var players: Array[Player] = _live_players()
	if players.is_empty() or pillar == null or not is_instance_valid(pillar):
		return []
	var origin: Vector2 = pillar.global_position
	players.sort_custom(
		func(a: Player, b: Player) -> bool:
			return origin.distance_squared_to(a.global_position) \
				< origin.distance_squared_to(b.global_position)
	)
	return players.slice(0, maxi(1, count))


## Distance from [param point] to the closest point on segment [param a]→[param b].
func _dist_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq <= 0.0001:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(ab) / len_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)


## Whether it is still valid to land a cast that was started before an await.
func _alive() -> bool:
	return (
		pillar != null
		and is_instance_valid(pillar)
		and not pillar.is_dead
		and is_inside_tree()
	)


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


func _instance() -> Node:
	if pillar == null or pillar.container == null:
		return null
	var map: Node = pillar.container.get_parent()
	var owner_node: Node = map.get_parent() if map != null else null
	return owner_node if _is_server_instance(owner_node) else null


## True when [param node] is a live ServerInstance — see the note on the same
## helper in OssuranArena. Off-server the map's parent is not an instance, and
## every players_by_peer_id loop below would throw on it.
static func _is_server_instance(node: Node) -> bool:
	return node != null and node.get(&"players_by_peer_id") is Dictionary
