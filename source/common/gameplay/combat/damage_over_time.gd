class_name DamageOverTime
extends Node
## A server-side damage tick (burn, poison, ...) attached to its VICTIM as a
## child node, so it dies with the victim's node and needs no manager. One
## node per effect kind — re-applying the same kind REFRESHES duration and
## ownership instead of stacking (bolt spam can't pile burns).
##
## Damage goes through Character.take_damage directly: the zone/PvP gates ran
## on the hit that APPLIED the effect (CombatHit.try_damage), and a burn that
## stops at a zone line would feel arbitrary anyway.


var source: Character
var damage_per_tick: float
var damage_type: StringName = CombatHit.DAMAGE_MAGIC
## Effect family (&"burn", &"poison", ...) — the node name carries it for
## refresh lookups, this exposes it for the status HUD.
var kind: StringName
var _remaining_ticks: int
## Wall-clock ms this APPLICATION dies at no matter how often it is refreshed.
## 0 = uncapped (every DoT except venom).
var _expires_at_ms: int = 0


## Whole seconds left, for the status-icon countdown.
func remaining_seconds() -> int:
	return maxi(0, _remaining_ticks)


## Attach (or refresh) a DoT on [param victim]. Server-side only; clients see
## the health drain through the regular stat sync.
## [param max_lifespan_s] caps how long ONE APPLICATION may be kept alive by
## refreshes. 0 (the default) means uncapped, which is how every existing caller
## behaves and must keep behaving.
##
## Without a cap, "a hit refreshes the timer" means a player who keeps landing
## hits holds the DoT forever — the damage is no longer a burst you set up and
## then have to re-earn, it is a second, permanent damage stat. The cap is a
## deadline set when the effect FIRST lands and never moved afterwards, so
## refreshes can top the timer back up but can never push past it. When it
## lapses the node frees, and the next landed hit starts a fresh application with
## a fresh deadline.
static func apply(
	victim: Character,
	from: Character,
	effect_kind: StringName,
	dps: float,
	duration_s: float,
	type: StringName = CombatHit.DAMAGE_MAGIC,
	max_lifespan_s: float = 0.0
) -> void:
	if victim == null or not victim.multiplayer.is_server() or dps <= 0.0:
		return
	var node_name: String = "DoT_%s" % effect_kind
	var existing: DamageOverTime = victim.get_node_or_null(NodePath(node_name)) as DamageOverTime
	if existing != null:
		existing.source = from
		existing.damage_per_tick = dps
		existing._remaining_ticks = maxi(existing._remaining_ticks, ceili(duration_s))
		# The deadline is deliberately NOT re-armed here — re-arming it on every
		# hit is exactly the infinite uptime this exists to stop.
		existing._clamp_to_deadline()
		return
	var dot: DamageOverTime = DamageOverTime.new()
	dot.name = node_name
	dot.kind = effect_kind
	dot.source = from
	dot.damage_per_tick = dps
	dot.damage_type = type
	dot._remaining_ticks = ceili(duration_s)
	if max_lifespan_s > 0.0:
		dot._expires_at_ms = Time.get_ticks_msec() + int(max_lifespan_s * 1000.0)
		dot._clamp_to_deadline()
	victim.add_child(dot)


## Trim the countdown so it can never run past [member _expires_at_ms]. No-op for
## an uncapped DoT, which is every one that existed before venom.
func _clamp_to_deadline() -> void:
	if _expires_at_ms <= 0:
		return
	var left: int = maxi(0, ceili((_expires_at_ms - Time.get_ticks_msec()) / 1000.0))
	_remaining_ticks = mini(_remaining_ticks, left)


func _ready() -> void:
	var timer: Timer = Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(_tick)
	add_child(timer)
	timer.start()


func _tick() -> void:
	var victim: Character = get_parent() as Character
	# The deadline is checked HERE as well as on refresh, so a capped DoT ends on
	# time even if nothing ever hits the victim again — the clamp on refresh only
	# runs when a refresh happens.
	if _expires_at_ms > 0 and Time.get_ticks_msec() >= _expires_at_ms:
		queue_free()
		return
	if victim == null or victim.is_dead or _remaining_ticks <= 0:
		queue_free()
		return
	_remaining_ticks -= 1
	victim.take_damage(damage_per_tick, source, damage_type, kind)
	if _remaining_ticks <= 0:
		queue_free()
