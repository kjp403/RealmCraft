class_name MeleeArc
extends Area2D
## Short-lived hitbox spawned (server-only) by melee weapons. Damages overlapping
## targets via CombatHit — same flag / PvP / sparring / friendly-fire rules as
## the bow arrow, so combat stays consistent across weapons.
##
## The arc is a STATIC box at the swing position; it does NOT follow the player
## (a swing is a brief moment in front of you). The visible swing is the weapon's
## own animation, not this node.
##
## Detection goes through CombatHit.overlapping_bodies (a deterministic physics
## shape query) on the first physics step, plus body_entered for anything that
## walks in during its life. The shape query is what lets a swing hit a STILL
## target (a territory flag, a motionless mob) that enter-events miss.
##
## [member max_targets] caps how many combatants a single swing can DAMAGE
## (0 = unlimited AoE). Basics use 1 so a pack standing on top of each other
## doesn't all get cleaved / pulled by one swing — closest target wins.
##
## [member follow_source] turns the arc into a SUSTAINED field instead: it rides
## the caster and re-runs the shape query every physics frame for its whole
## lifetime. Whirlwind needs that — a one-frame snapshot taken while the wielder
## is walking (it's a mobile channel) missed anything that drifted in a frame
## later, which is what made the spin feel like it whiffed. [member _hit_bodies]
## still dedupes, so one arc = at most one hit per target regardless.

## A target at/below this fraction of max HP counts as "low" for the wielder's
## Executioner mastery passive (DAMAGE_VS_LOW_HP amp).
const LOW_HP_THRESHOLD: float = 0.35

@export var lifetime: float = 0.18
## Ride the source and keep scanning for the arc's whole lifetime (see above).
## False = the default one-shot snapshot at the swing position.
@export var follow_source: bool = false

var source: Character
## The direction the swing was aimed in. Set by the spawning ability; used to pick
## the best-ALIGNED target when [member max_targets] caps the swing (see
## [method _sorted_by_alignment]). Zero falls back to distance-only ordering.
var aim_direction: Vector2 = Vector2.ZERO
var damage: float = 10.0
## On-hit slow (Crippling Strike): flat move_speed reduction applied as a
## timed negative buff to each Player struck. 0 = no slow. Set by the ability.
var slow_amount: float = 0.0
var slow_duration_s: float = 0.0
## Physical by default (melee). A spell nova (NovaAbility) sets MAGIC so it scales the
## caster's MR-mitigated path instead of armor.
var damage_type: StringName = CombatHit.DAMAGE_PHYSICAL
## Blood Feast drain: each LANDED hit heals + restores mana to the SOURCE (the caster
## feeds on the pack). 0 = none. mana_per_hit only pays out on a real hit, so whiffing
## into air refunds nothing.
var heal_per_hit: float = 0.0
var mana_per_hit: float = 0.0
## 0 = hit every valid overlap (AoE novas / slams / whirlwinds). 1 = single-target
## basics. Only counts CombatHit.Result.DAMAGED landings toward the cap.
var max_targets: int = 0

var _hit_bodies: Array[Node] = []
var _scanned: bool = false
var _targets_damaged: int = 0


func _ready() -> void:
	# Damage targets only. The WORLD bit that CombatHit.TARGET_MASK carries is
	# there for PROJECTILES (which stop on walls); a melee arc discards every
	# non-DAMAGED result, so wall tiles were pure noise — and each overlapping
	# tile shape burned one of intersect_shape's limited result slots, which is
	# how a wide AoE (whirlwind, bladestorm) standing near a wall could come
	# back with no mobs at all.
	collision_mask = PhysicsLayers.HURTBOX | PhysicsLayers.FLAG
	if not GameMode.is_world_server():
		set_physics_process(false)
	else:
		body_entered.connect(_on_body_entered)
		area_entered.connect(_on_body_entered) # catch walk-in HurtBox areas too

	var t: Timer = Timer.new()
	t.wait_time = lifetime
	t.one_shot = true
	t.timeout.connect(queue_free)
	add_child(t)
	t.start()


func _physics_process(_delta: float) -> void:
	if follow_source:
		# A sustained field: stay centred on the wielder and re-scan every frame.
		if not is_instance_valid(source):
			queue_free()
			return
		global_position = source.global_position
	else:
		set_physics_process(false)
		if _scanned:
			return
	_scanned = true
	var bodies: Array[Node2D] = CombatHit.overlapping_bodies(self)
	# Prefer the best-aimed-at combatant when capped — otherwise pack stacks feel random.
	if max_targets > 0 and bodies.size() > 1:
		bodies = _sorted_by_alignment(bodies)
	for body: Node2D in bodies:
		_on_body_entered(body)
		if max_targets > 0 and _targets_damaged >= max_targets:
			break


func _on_body_entered(body: Node2D) -> void:
	if max_targets > 0 and _targets_damaged >= max_targets:
		return
	if body == source:
		return
	if _hit_bodies.has(body):
		return
	_hit_bodies.append(body)
	# `body` may be a HurtBox area — resolve to its owner Character for HP / type checks.
	var struck: Node = (body as HurtBox).character if body is HurtBox else body
	var dealt: float = damage * _execute_multiplier(struck)
	var result: CombatHit.Result = CombatHit.try_damage(source if source is Character else null, body, dealt, damage_type)
	if result != CombatHit.Result.DAMAGED:
		return
	_targets_damaged += 1
	# Slow rides a LANDED hit on a Player only (the first negative status buff, via
	# the same BuffService potions use).
	if slow_amount > 0.0 and slow_duration_s > 0.0 and struck is Player:
		BuffService.apply(struck as Player, Stat.MOVE_SPEED, -slow_amount, slow_duration_s)
	# Blood Feast: drain the struck enemy — heal + mana to the source, per landed hit.
	if is_instance_valid(source):
		if heal_per_hit > 0.0:
			var hmax: float = source.stats_component.get_stat(Stat.HEALTH_MAX)
			source.stats_component.set_stat(Stat.HEALTH, minf(hmax, source.stats_component.get_stat(Stat.HEALTH) + heal_per_hit))
		if mana_per_hit > 0.0:
			var mmax: float = source.stats_component.get_stat(Stat.MANA_MAX)
			source.stats_component.set_stat(Stat.MANA, minf(mmax, source.stats_component.get_stat(Stat.MANA) + mana_per_hit))


## Best-ALIGNED first so a single-target swing picks the mob you actually aimed at,
## not whichever collider the physics query happened to return first. Distance alone
## used to decide this, which was fine while the hitbox was too small to hold two
## bodies — once the arc widens, "closest" starts picking the neighbour standing a
## few pixels nearer than your target. Angle to the swing direction leads; distance
## only separates targets at a similar angle.
func _sorted_by_alignment(bodies: Array[Node2D]) -> Array[Node2D]:
	var origin: Vector2 = source.global_position if is_instance_valid(source) else global_position
	var scored: Array = []
	for body: Node2D in bodies:
		var node: Node2D = body
		if body is HurtBox and (body as HurtBox).character is Node2D:
			node = (body as HurtBox).character as Node2D
		var offset: Vector2 = node.global_position - origin
		var deviation: float = 0.0
		if aim_direction != Vector2.ZERO and offset != Vector2.ZERO:
			deviation = absf(aim_direction.angle_to(offset))
		scored.append({"body": body, "a": deviation, "d": offset.length()})
	scored.sort_custom(_alignment_is_better)
	var out: Array[Node2D] = []
	for entry: Dictionary in scored:
		out.append(entry["body"] as Node2D)
	return out


## Angle first, distance as the tie-break. The tolerance keeps two bodies at
## near-identical angles from flipping order on floating-point noise — inside it,
## the closer one wins, which is the old behaviour and the right call for a stack.
func _alignment_is_better(a: Dictionary, b: Dictionary) -> bool:
	const ANGLE_TIE_RAD: float = 0.20
	if absf(float(a["a"]) - float(b["a"])) <= ANGLE_TIE_RAD:
		return float(a["d"]) < float(b["d"])
	return float(a["a"]) < float(b["a"])


## Executioner mastery passive: the wielder's DAMAGE_VS_LOW_HP stat (%) amplifies
## damage to targets at/below [constant LOW_HP_THRESHOLD] of max HP. Returns 1.0
## (no change) for anyone without the passive — the stat is 0 by default — so this
## is a cheap no-op on every other hit in the game.
func _execute_multiplier(struck: Node) -> float:
	if not is_instance_valid(source):
		return 1.0
	var amp: float = source.stats_component.get_stat(Stat.DAMAGE_VS_LOW_HP)
	if amp <= 0.0 or struck is not Character:
		return 1.0
	var target: Character = struck as Character
	var max_hp: float = target.stats_component.get_stat(Stat.HEALTH_MAX)
	if max_hp <= 0.0:
		return 1.0
	if target.stats_component.get_stat(Stat.HEALTH) / max_hp <= LOW_HP_THRESHOLD:
		return 1.0 + amp / 100.0
	return 1.0
