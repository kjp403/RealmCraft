class_name AimAssist
## Sticky aim for free-aim attacks: nudges the fired direction onto a hostile the
## player is ALREADY fighting, so a swing that was a few degrees off still lands.
## Pure client presentation of intent — the server takes the aim vector it's sent
## either way (see action.perform), so this changes nothing about authority.
##
## The hard rule is [method _is_eligible]: assist may only ever pick a hostile that
## is already committed to the fight (chasing you, or your explicit lock). It must
## NEVER acquire a passive mob. Whole zones are built on chase_on_area = false —
## picking your fight by aiming carefully IS the gameplay there (Goblin Woodland
## packs sit 55-80 px apart), and an assist that started fights on your behalf
## would quietly turn one goblin into three.


## Half-angle of the assist cone. Deliberately narrow: this corrects a slightly
## sloppy swing, it does not aim for you.
const CONE_HALF_ANGLE_DEG: float = 25.0
## Nothing past this is a candidate, whatever the angle.
const MAX_RANGE: float = 260.0
## How much a candidate at max range is penalised, expressed in the same units as
## angular deviation (radians). Angle dominates; distance only separates targets
## that are similarly well-aligned.
const DISTANCE_WEIGHT: float = 0.15
## Score multiplier for the target we assisted onto last. Hysteresis — without it
## an add crossing your line yanks aim off the thing you were hitting.
const STICKY_BIAS: float = 0.6
## How long that bias survives after the last assisted hit.
const STICKY_MS: int = 800


var _last_target: HostileNpc = null
var _last_target_until_ms: int = 0


## The direction the attack should actually fire in. Returns [param raw] unchanged
## when nothing eligible sits inside the cone — which is the common case and the
## safe default.
func resolve(origin: Vector2, raw: Vector2) -> Vector2:
	if raw == Vector2.ZERO:
		return raw
	var best: HostileNpc = _best_target(origin, raw)
	if best == null:
		return raw
	var to_target: Vector2 = best.global_position - origin
	if to_target == Vector2.ZERO:
		return raw
	_last_target = best
	_last_target_until_ms = Time.get_ticks_msec() + STICKY_MS
	return to_target.normalized()


func _best_target(origin: Vector2, raw: Vector2) -> HostileNpc:
	var container: ReplicatedPropsContainer = _container()
	if container == null:
		return null
	var cone: float = deg_to_rad(CONE_HALF_ANGLE_DEG)
	var best: HostileNpc = null
	var best_score: float = INF
	for npc: HostileNpc in _candidates(container):
		if not _is_eligible(npc):
			continue
		var to_npc: Vector2 = npc.global_position - origin
		var dist: float = to_npc.length()
		if dist <= 0.0 or dist > MAX_RANGE:
			continue
		var deviation: float = absf(raw.angle_to(to_npc))
		if deviation > cone:
			continue
		# A big body presents a wider target, so the same angular miss should read
		# as a smaller error against a boss than against a runt.
		var scale: float = 1.0
		if npc.enemy_data != null:
			scale = maxf(1.0, npc.enemy_data.visual_scale)
		var score: float = (deviation / scale) + (dist / MAX_RANGE) * DISTANCE_WEIGHT
		if npc == _last_target and Time.get_ticks_msec() < _last_target_until_ms:
			score *= STICKY_BIAS
		if score < best_score:
			best_score = score
			best = npc
	return best


## Assist may only follow a fight already in progress — see the class docs. An
## explicit lock counts even before the mob reacts, because the player named that
## target themselves.
func _is_eligible(npc: HostileNpc) -> bool:
	if npc == null or not is_instance_valid(npc) or npc.is_dead:
		return false
	if npc.enemy_state == HostileNpc.EnemyState.DEAD \
			or npc.enemy_state == HostileNpc.EnemyState.REVIVING:
		return false
	if npc.stats_component != null and npc.stats_component.get_stat(Stat.HEALTH) <= 0.0:
		return false
	if npc.get_instance_id() == Character.combat_target_instance_id:
		return true
	return npc.enemy_state == HostileNpc.EnemyState.CHASE


## Hostiles live both as scene children and as dynamically spawned nodes (boss adds,
## summons) — the same two buckets [CombatTargetController] walks.
func _candidates(container: ReplicatedPropsContainer) -> Array[HostileNpc]:
	var out: Array[HostileNpc] = []
	for node: Node in container.get_children():
		var npc: HostileNpc = node as HostileNpc
		if npc != null:
			out.append(npc)
	for child_id: Variant in container.dynamic_nodes.keys():
		var npc2: HostileNpc = container.dynamic_nodes[child_id] as HostileNpc
		if npc2 != null:
			out.append(npc2)
	return out


func _container() -> ReplicatedPropsContainer:
	if InstanceClient.current == null or InstanceClient.current.instance_map == null:
		return null
	var map: Map = InstanceClient.current.instance_map as Map
	return null if map == null else map.replicated_props_container
