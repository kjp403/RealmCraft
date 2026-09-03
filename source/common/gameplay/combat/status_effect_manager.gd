class_name StatusEffectManager
extends Node
## Per-character owner of the effect families the older services structurally
## cannot hold. Attached to its character as a child node named
## [constant NODE_NAME], exactly like [DamageOverTime] and [TimedDebuff]: it dies
## with the body, needs no global registry, and adds nothing to Character,
## Player or HostileNpc beyond a single call each.
##
## WHY THIS EXISTS AND NOT [BuffService] OR [TimedDebuff]
##
## [BuffService] stores its entries on [PlayerResource], so it can only ever
## touch a Player. Corroding Heat lands on MOBS, and a debuff that silently does
## nothing to a mob is not balance, it is a bug that looks like balance — the
## same reasoning [TimedDebuff] already documents.
##
## [TimedDebuff] does work on any [Character], but it is deliberately
## refresh-never-stack with FLAT magnitudes, and re-applying it keeps the
## original numbers. Corroding Heat is the opposite shape: it STACKS, to a hard
## cap, by a PERCENTAGE. Widening TimedDebuff to cover both would have made the
## thing that guards arrow-spam from stacking a mob to zero armor into a thing
## that sometimes permits stacking, which is how that guard gets lost.
##
## Four families live here, and they share this node because they share the same
## three needs: a per-character ledger of what was actually applied, a 1 Hz
## expiry tick, and generic signals the HUD can bind to.
##
##   - [constant EFFECT_CORRODING_HEAT] — capped percentage armor strip on a victim.
##   - [constant EFFECT_VENOM]          — a true DoT keyed BY SOURCE, so two
##                                        players' venoms never overwrite each other.
##   - [constant EFFECT_CINDER_GUARD]   — reactive: burns melee attackers, with a
##                                        per-attacker internal cooldown.
##   - [constant EFFECT_SHADOWVEIL]     — a stealth override read by NPC targeting.
##   - [constant EFFECT_PROVOCATION]    — a pulsing aggro lock built on the taunt
##                                        that every aggro-steal path already defers to.
##
## SERVER-SIDE ONLY. Every entry point either checks `multiplayer.is_server()` or
## is called from a server tick. The client learns about all of it through the
## existing 1 Hz `status.sync` push, never by running this.
##
## EVERY FIELD RECORDS WHAT IT ACTUALLY APPLIED. Reverting a change that was
## never applied silently drains the victim's stat block — the same trap
## [BuffService] documents for suppressed buffs and [TimedDebuff] for its own.

## Child-node name on the owning character. Fixed so [method find] is a lookup
## rather than a scan.
const NODE_NAME: StringName = &"StatusEffects"

## Capped, stacking, percentage armor strip. Applied to a VICTIM by the
## Corrosive Ember Draught's coating.
const EFFECT_CORRODING_HEAT: StringName = &"corroding_heat"
## True damage-over-time keyed by the player who applied it.
const EFFECT_VENOM: StringName = &"venom"
## Reactive burn returned to melee attackers. Lives on the DRINKER.
const EFFECT_CINDER_GUARD: StringName = &"cinder_guard"
## Hostile detection suppressed to zero. Lives on the DRINKER.
const EFFECT_SHADOWVEIL: StringName = &"shadowveil"
## Pulsing aggro lock. Lives on the DRINKER.
const EFFECT_PROVOCATION: StringName = &"provocation"

## Reasons stealth ends, passed to [method break_stealth] purely so the server
## log and the client message can say WHICH action gave the player away.
const BREAK_ATTACK: StringName = &"attack"
const BREAK_GATHER: StringName = &"gather"
const BREAK_DAMAGED: StringName = &"damaged"
const BREAK_EXPIRED: StringName = &"expired"

## Melee reach used to decide whether an incoming hit was a MELEE hit for
## Cinder-Guard's retaliation. Generous enough to cover a mob's swing arc and its
## body radius, short enough that an archer across the room never triggers it.
const MELEE_REACH_PX: float = 120.0

## An effect started, with its opening payload:
## {"remaining": int, "stacks": int, "max_stacks": int}. The HUD binds to this
## and never to the fields below — the point of the signal is that a buff icon
## can exist without knowing that Corroding Heat is armor and Shadowveil is not.
signal effect_applied(id: StringName, data: Dictionary)
## A stacking effect changed count (added, capped, or decayed).
signal stack_updated(id: StringName, stacks: int, max_stacks: int)
## An effect ended — expired, broken, cleared on death, or reverted.
signal effect_removed(id: StringName)
## Convenience edge for the one effect the HUD must react to instantly rather
## than on the next 1 Hz push: going invisible, and being seen again.
signal stealth_changed(active: bool)

## family -> {"stacks", "max_stacks", "per_stack", "applied_armor", "expires_ms"}
var _stacks: Dictionary[StringName, Dictionary] = {}
## family -> {"expires_ms", "potency", "radius", "pulse_ms", "next_pulse_ms",
##            "icd_ms", "payload_s", "max_targets"}
var _auras: Dictionary[StringName, Dictionary] = {}
## "family:instance_id" -> ready_ms. The per-BODY internal cooldown that stops one
## AoE swing clipping you five times from returning five burns.
var _icd: Dictionary[String, int] = {}


# --- Lookup -------------------------------------------------------------------

## The manager on [param character], or null. Use this on READ paths (targeting,
## tooltips, the status push): it never allocates, so asking "is this mob
## corroded" about ten thousand mobs costs ten thousand dictionary misses rather
## than ten thousand nodes.
static func find(character: Character) -> StatusEffectManager:
	if character == null or not is_instance_valid(character):
		return null
	return character.get_node_or_null(NodePath(NODE_NAME)) as StatusEffectManager


## The manager on [param character], creating it if this is the first effect it
## has ever carried. Use on WRITE paths only. Returns null off the server or for
## a character that is gone.
static func for_character(character: Character) -> StatusEffectManager:
	if character == null or not is_instance_valid(character):
		return null
	if not character.is_inside_tree() or not character.multiplayer.is_server():
		return null
	var existing: StatusEffectManager = find(character)
	if existing != null:
		return existing
	var manager: StatusEffectManager = StatusEffectManager.new()
	manager.name = String(NODE_NAME)
	character.add_child(manager)
	return manager


func character() -> Character:
	return get_parent() as Character


# --- Stacking effects (Corroding Heat) ----------------------------------------

## Add one stack of [param family] to this character, or refresh the window if
## already at the cap.
##
## The strip is a share of the armor the victim had when the FIRST stack landed,
## not of their current armor. Compounding off the current value would make stack
## five worth a third of stack one, which reads in game as the debuff getting
## weaker the longer you keep it up — and would make the cap unenforceable.
##
## Stacks decay TOGETHER when the window lapses, rather than one at a time. That
## is what keeps the effect honest against a boss: a fight long enough to hold
## five stacks forever still has to re-earn them every
## [param duration_s] seconds, and a group that stops hitting loses the whole
## strip at once instead of sliding down a staircase.
func apply_stack(family: StringName, per_stack: float, max_stacks: int, duration_s: float) -> void:
	var victim: Character = character()
	if victim == null or victim.is_dead or per_stack <= 0.0 or duration_s <= 0.0:
		return
	if max_stacks <= 0 or victim.stats_component == null:
		return
	var expires_ms: int = Time.get_ticks_msec() + int(duration_s * 1000.0)
	var entry: Dictionary = _stacks.get(family, {})
	var fresh: bool = entry.is_empty()
	if fresh:
		entry = {
			"stacks": 0,
			"max_stacks": max_stacks,
			"per_stack": per_stack,
			# Armor at the moment the first stack landed. Every later stack is
			# priced off THIS number, so the strip is linear and the cap holds.
			"base_armor": maxf(0.0, victim.stats_component.get_stat(Stat.ARMOR)),
			"applied_armor": 0.0,
			"expires_ms": expires_ms,
		}
		_stacks[family] = entry
	entry["expires_ms"] = maxi(int(entry["expires_ms"]), expires_ms)

	var cap: int = mini(max_stacks, int(entry["max_stacks"]))
	if int(entry["stacks"]) >= cap:
		# At the cap the hit still refreshes the window — that is the entire
		# uptime mechanic — but takes no more armor.
		if fresh:
			effect_applied.emit(family, _describe_stack(family, entry))
		return

	# Never strip past zero. A negative armor value turns mitigation into
	# amplification further down the damage formula, which is the trap
	# TimedDebuff already guards for its flat shred.
	var want: float = float(entry["base_armor"]) * per_stack
	var have: float = maxf(0.0, victim.stats_component.get_stat(Stat.ARMOR))
	var taken: float = minf(want, have)
	if taken > 0.0:
		victim.stats_component.modify_stat(Stat.ARMOR, -taken)
		entry["applied_armor"] = float(entry["applied_armor"]) + taken
	entry["stacks"] = int(entry["stacks"]) + 1

	if fresh:
		effect_applied.emit(family, _describe_stack(family, entry))
	stack_updated.emit(family, int(entry["stacks"]), cap)


## Live stack count of [param family], 0 when absent. For tooltips and tests.
func stacks_of(family: StringName) -> int:
	return int((_stacks.get(family, {}) as Dictionary).get("stacks", 0))


## Give back exactly what [param family] took and forget it. Idempotent.
func clear_stack(family: StringName) -> void:
	var entry: Dictionary = _stacks.get(family, {})
	if entry.is_empty():
		return
	_stacks.erase(family)
	var victim: Character = character()
	var applied: float = float(entry.get("applied_armor", 0.0))
	if victim != null and victim.stats_component != null and applied > 0.0:
		victim.stats_component.modify_stat(Stat.ARMOR, applied)
	effect_removed.emit(family)


# --- Source-keyed damage over time (Venom) ------------------------------------

## Attach a true DoT to [param victim] that is owned BY [param source].
##
## [DamageOverTime] names its node after the effect kind alone, so a second
## application of the same kind — from ANY player — overwrites the first's
## damage and ownership. For a burn off a shared boss that is fine. For a venom
## it is not: the group's weakest venom would repeatedly stomp the strongest, and
## kill credit would drift to whoever hit last. Keying the node by source fixes
## both, while keeping the property that matters for exploits — ONE venom per
## player, so re-hitting refreshes rather than stacks.
static func apply_source_dot(
	victim: Character,
	source: Player,
	family: StringName,
	dps: float,
	duration_s: float,
	per_source: bool = true,
	damage_type: StringName = CombatHit.DAMAGE_MAGIC,
	max_lifespan_s: float = 0.0
) -> void:
	if victim == null or source == null or dps <= 0.0 or duration_s <= 0.0:
		return
	if not is_instance_valid(victim) or not victim.is_inside_tree():
		return
	if not victim.multiplayer.is_server() or victim.is_dead:
		return
	if not per_source:
		DamageOverTime.apply(
			victim, source, family, dps, duration_s, damage_type, max_lifespan_s
		)
		return
	# The instance id, not the player id: player_resource is server-side state and
	# this only ever runs on the server, but the instance id is stable for the
	# lifetime of the body and cannot collide across maps.
	var keyed: StringName = StringName("%s#%d" % [family, source.get_instance_id()])
	# The lifespan cap is PER SOURCE too, because the node is: each player's venom
	# carries its own deadline, so one player's expiring application never cuts
	# another's short and neither can extend the other's.
	DamageOverTime.apply(
		victim, source, keyed, dps, duration_s, damage_type, max_lifespan_s
	)


# --- Auras on the drinker -----------------------------------------------------

## Arm [param potion]'s aura on [param owner]. Re-drinking REFRESHES rather than
## stacking, matching every other draught in the game.
func arm_aura(potion: PotionItem, owner: Player) -> void:
	if potion == null or owner == null or not potion.is_aura():
		return
	var family: StringName = potion.aura_effect
	var now: int = Time.get_ticks_msec()
	var pulse_ms: int = int(potion.aura_pulse_s * 1000.0)
	var known: bool = _auras.has(family)
	_auras[family] = {
		"expires_ms": now + int(potion.aura_duration_s * 1000.0),
		"potency": potion.aura_potency,
		"radius": potion.aura_radius,
		"pulse_ms": pulse_ms,
		# Fire the first pulse IMMEDIATELY. A Provocation Brew whose pull does not
		# start until two seconds after you drink it is a brew you cannot use to
		# peel a mob off someone who is already in trouble.
		"next_pulse_ms": now,
		"icd_ms": int(potion.aura_internal_cooldown_s * 1000.0),
		"payload_s": potion.aura_payload_duration_s,
		"max_targets": potion.aura_max_targets,
		"break_on_gather": potion.aura_breaks_on_gather,
		# Whether this aura holds the ONE combat-draught slot. Recorded on the
		# aura rather than inferred, because an aura-only draught (Shadowveil has
		# no stat buff and no coating) is invisible to both of the other two
		# services that answer that question.
		"exclusive": potion.exclusive_buff,
	}
	_mirror_auras()
	if not known:
		effect_applied.emit(family, {
			"remaining": ceili(potion.aura_duration_s), "stacks": 0, "max_stacks": 0,
		})
		if family == EFFECT_SHADOWVEIL:
			stealth_changed.emit(true)
	if pulse_ms > 0:
		_pulse(family, _auras[family])


## Is an aura holding the one combat-draught slot? Consulted by
## [method ConsumableItem.draught_slot_busy] alongside [CoatingService] and
## [BuffService], so all three kinds of draught refuse each other.
static func exclusive_aura_active(character: Character) -> bool:
	var manager: StatusEffectManager = find(character)
	if manager == null:
		return false
	var now: int = Time.get_ticks_msec()
	for family: StringName in manager._auras:
		var aura: Dictionary = manager._auras[family]
		if bool(aura.get("exclusive", false)) and now < int(aura.get("expires_ms", 0)):
			return true
	return false


## Whole seconds left on the exclusive aura, for naming the refusal. 0 when free.
static func exclusive_aura_remaining(character: Character) -> int:
	var manager: StatusEffectManager = find(character)
	if manager == null:
		return 0
	var left: int = 0
	for family: StringName in manager._auras:
		if bool(manager._auras[family].get("exclusive", false)):
			left = maxi(left, manager.aura_remaining_seconds(family))
	return left


func has_aura(family: StringName) -> bool:
	var aura: Dictionary = _auras.get(family, {})
	if aura.is_empty():
		return false
	return Time.get_ticks_msec() < int(aura.get("expires_ms", 0))


## Whole seconds left on [param family], 0 when absent — for the status strip.
func aura_remaining_seconds(family: StringName) -> int:
	if not has_aura(family):
		return 0
	var left: int = int(_auras[family]["expires_ms"]) - Time.get_ticks_msec()
	return maxi(0, ceili(left / 1000.0))


func clear_aura(family: StringName) -> void:
	if not _auras.has(family):
		return
	_auras.erase(family)
	_mirror_auras()
	effect_removed.emit(family)
	if family == EFFECT_SHADOWVEIL:
		stealth_changed.emit(false)


# --- Stealth ------------------------------------------------------------------

## Is [param character] currently hidden from hostile detection? Read by
## [HostileNpc] on its targeting paths, so it must stay allocation-free and cheap
## — hence [method find] rather than [method for_character].
static func is_stealthed(character: Character) -> bool:
	var manager: StatusEffectManager = find(character)
	return manager != null and manager.has_aura(EFFECT_SHADOWVEIL)


## End stealth now. Safe to call on anything, at any time, whether or not the
## character is hidden — every caller is a hot path (a landed hit, a gather
## swing) and should not have to check first.
static func break_stealth(character: Character, reason: StringName) -> void:
	var manager: StatusEffectManager = find(character)
	if manager == null or not manager.has_aura(EFFECT_SHADOWVEIL):
		return
	manager._last_break_reason = reason
	manager.clear_aura(EFFECT_SHADOWVEIL)


## Working a gathering node. Ends the veil only when the draught was authored to
## break on it (see [member PotionItem.aura_breaks_on_gather]) — the one break
## condition that is a balance question rather than a physics one, because the
## draught exists to get a gatherer to a guarded patch in the first place.
##
## Called from [MineableNode.register_gather_hit] on the SWING, not on a
## successful yield: a swing that bounces off a depleted node is still a player
## standing in the open hacking at a plant.
static func on_gather(character: Character) -> void:
	var manager: StatusEffectManager = find(character)
	if manager == null or not manager.has_aura(EFFECT_SHADOWVEIL):
		return
	if not bool(manager._auras[EFFECT_SHADOWVEIL].get("break_on_gather", true)):
		return
	manager._last_break_reason = BREAK_GATHER
	manager.clear_aura(EFFECT_SHADOWVEIL)


var _last_break_reason: StringName = BREAK_EXPIRED


## Why stealth ended last time. Read by the server handler that words the
## "you have been spotted" line.
func last_break_reason() -> StringName:
	return _last_break_reason


# --- Reactive: Cinder-Guard ---------------------------------------------------

## Called from [method Character.take_damage] after the hit has fully resolved.
##
## Placed there and NOT in [method CombatHit.try_damage] on purpose: NPC melee
## behaviours ([MeleeAttack], [LungeBehavior]) call `take_damage` on their target
## DIRECTLY and never pass through CombatHit, so a retaliation hooked into
## CombatHit would do nothing against the exact enemies a tanking draught exists
## for — and would do nothing SILENTLY.
static func on_damaged(
	victim: Character, attacker: Character, damage_type: StringName
) -> void:
	if victim == null or attacker == null or attacker == victim:
		return
	var manager: StatusEffectManager = find(victim)
	if manager == null:
		return
	# Being hit gives away a hidden player as surely as swinging does.
	if manager.has_aura(EFFECT_SHADOWVEIL):
		manager._last_break_reason = BREAK_DAMAGED
		manager.clear_aura(EFFECT_SHADOWVEIL)
	manager._retaliate(attacker, damage_type)


func _retaliate(attacker: Character, damage_type: StringName) -> void:
	if not has_aura(EFFECT_CINDER_GUARD):
		return
	# Melee only. A caster or an archer shooting from across the room has not put
	# themselves in reach of the heat they are standing next to, and returning a
	# burn to them would make the draught the best answer to ranged packs as well
	# as to melee ones.
	if damage_type != CombatHit.DAMAGE_PHYSICAL:
		return
	var owner_body: Character = character()
	if owner_body == null or owner_body.is_dead or not is_instance_valid(attacker):
		return
	if attacker.is_dead:
		return
	if owner_body.global_position.distance_to(attacker.global_position) > MELEE_REACH_PX:
		return
	var aura: Dictionary = _auras[EFFECT_CINDER_GUARD]
	if not _icd_ready(EFFECT_CINDER_GUARD, attacker, int(aura.get("icd_ms", 0))):
		return
	var owner_player: Player = owner_body as Player
	DamageOverTime.apply(
		attacker,
		owner_player if owner_player != null else owner_body,
		CoatingService.KIND_BURN,
		float(aura.get("potency", 0.0)),
		float(aura.get("payload_s", 0.0))
	)


## True (and arms the cooldown) when [param body] may be hit by [param family]
## again. A zero cooldown always passes, so an aura that wants no gate simply
## leaves the field at 0.
func _icd_ready(family: StringName, body: Node, cooldown_ms: int) -> bool:
	if cooldown_ms <= 0:
		return true
	var key: String = "%s:%d" % [family, body.get_instance_id()]
	var now: int = Time.get_ticks_msec()
	if now < int(_icd.get(key, 0)):
		return false
	_icd[key] = now + cooldown_ms
	return true


# --- Pulsing: Provocation -----------------------------------------------------

func _pulse(family: StringName, aura: Dictionary) -> void:
	if family != EFFECT_PROVOCATION:
		return
	var owner_player: Player = character() as Player
	if owner_player == null or owner_player.is_dead:
		return
	var radius: float = float(aura.get("radius", 0.0))
	if radius <= 0.0:
		return
	# Hold each mob a little past the next pulse, so the lock never blinks open
	# between cycles and let a boss re-pick by proximity for half a second.
	var hold_s: float = maxf(1.0, float(aura.get("pulse_ms", 0)) / 1000.0 * 1.5)
	var taken: int = 0
	var budget: int = maxi(1, int(aura.get("max_targets", 8)))
	for npc: HostileNpc in _hostiles_near(owner_player, radius):
		# apply_taunt is the SAME lock Mighty Roar uses, and it is deliberately
		# reused rather than reimplemented: every path that could steal aggro back
		# — the pack ally-call, retaliation on damage, the leash, target loss —
		# already defers to it. A second, parallel "forced target" field would have
		# to teach all of those about itself, and the one that was missed would
		# drop the tank's hold without anyone noticing until a raid.
		npc.apply_taunt(owner_player, hold_s)
		taken += 1
		if taken >= budget:
			break


## Living hostiles within [param radius] of [param caster], nearest first.
##
## Walks BOTH buckets hostiles live in — static children and dynamic_nodes —
## because dungeon and boss-summoned mobs only ever appear in the second, and a
## tanking tool that cannot hold dungeon adds is not a tanking tool. Mirrors
## [method TauntAbility._hostiles_in_range]; kept as its own copy rather than
## made public there because that method is an ability's private business and
## reaching into it would couple a potion to a weapon tree.
static func _hostiles_near(caster: Player, radius: float) -> Array[HostileNpc]:
	var out: Array[HostileNpc] = []
	var map: Node = caster.get_parent()
	if map is not Map:
		return out
	var container: ReplicatedPropsContainer = (map as Map).replicated_props_container
	if container == null:
		return out
	var candidates: Array = container.get_children()
	candidates.append_array(container.dynamic_nodes.values())
	for node: Variant in candidates:
		var npc: HostileNpc = node as HostileNpc
		if npc == null or not is_instance_valid(npc) or npc.is_dead:
			continue
		if caster.global_position.distance_to(npc.global_position) > radius:
			continue
		out.append(npc)
	# Nearest first is what makes the target budget behave: an arbitrary child
	# order lets a distant straggler eat the budget while the boss standing on
	# the tank goes un-taunted.
	out.sort_custom(
		func(a: HostileNpc, b: HostileNpc) -> bool:
			return (
				caster.global_position.distance_squared_to(a.global_position)
				< caster.global_position.distance_squared_to(b.global_position)
			)
	)
	return out


# --- Lifecycle ----------------------------------------------------------------

func _ready() -> void:
	var timer: Timer = Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(_tick)
	add_child(timer)
	timer.start()


## 1 Hz, matching [DamageOverTime] and the instance status tick. Everything here
## either counts whole seconds or fires on a millisecond deadline, so a faster
## clock would buy nothing and cost a timer per body in every mob camp.
func _tick() -> void:
	var body: Character = character()
	if body == null or not is_instance_valid(body):
		queue_free()
		return
	if body.is_dead:
		clear_all()
		return
	var now: int = Time.get_ticks_msec()

	for family: StringName in _stacks.keys():
		if now >= int(_stacks[family]["expires_ms"]):
			clear_stack(family)

	for family: StringName in _auras.keys():
		var aura: Dictionary = _auras[family]
		if now >= int(aura["expires_ms"]):
			if family == EFFECT_SHADOWVEIL:
				_last_break_reason = BREAK_EXPIRED
			clear_aura(family)
			continue
		var pulse_ms: int = int(aura.get("pulse_ms", 0))
		if pulse_ms > 0 and now >= int(aura.get("next_pulse_ms", 0)):
			aura["next_pulse_ms"] = now + pulse_ms
			_pulse(family, aura)

	# Expired internal cooldowns are dropped here rather than on lookup, so a boss
	# fight against a large pack cannot grow this dictionary without bound.
	for key: String in _icd.keys():
		if now >= int(_icd[key]):
			_icd.erase(key)


## Revert everything this manager applied. Death calls it (via the tick) beside
## [method BuffService.clear_all] and [method CoatingService.clear], and for the
## same reason: an effect that survives a corpse is an effect the player cannot
## see the end of.
func clear_all() -> void:
	for family: StringName in _stacks.keys():
		clear_stack(family)
	for family: StringName in _auras.keys():
		clear_aura(family)
	_icd.clear()
	_mirror_auras()


## Covers the paths the timer never reaches: the body being freed from under us,
## an instance teardown, a map change. Reverting twice is a no-op because
## [method clear_stack] erases before it gives back.
func _exit_tree() -> void:
	for family: StringName in _stacks.keys():
		clear_stack(family)


## Copy the live auras onto the [PlayerResource], which is the only thing that
## survives an instance change. Cheap: a duplicate of at most a handful of small
## dictionaries, written only when an aura starts or ends, never per tick.
func _mirror_auras() -> void:
	var player: Player = character() as Player
	if player == null or player.player_resource == null:
		return
	player.player_resource.active_auras = _auras.duplicate(true)


## Put live auras back on a FRESHLY SPAWNED player, from the resource mirror.
## Called from [LevelSync] beside [method BuffService.reapply] and for exactly
## the same reason: the spawn built a new Player node, so everything that lived
## on the OLD node is gone while everything on the resource is not.
##
## Anything that expired in transit is dropped rather than resumed.
static func reapply(player: Player) -> void:
	if player == null or player.player_resource == null:
		return
	var stored: Dictionary = player.player_resource.active_auras
	if stored.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var live: Dictionary = {}
	for family: StringName in stored:
		var aura: Dictionary = stored[family]
		if now < int(aura.get("expires_ms", 0)):
			# A pulsing aura must fire again promptly on the far side of the
			# doorway rather than waiting out the rest of its old cycle.
			aura["next_pulse_ms"] = now
			live[family] = aura
	player.player_resource.active_auras = live
	if live.is_empty():
		return
	var manager: StatusEffectManager = for_character(player)
	if manager == null:
		return
	manager._auras = live.duplicate(true)
	for family: StringName in manager._auras:
		manager.effect_applied.emit(family, {
			"remaining": manager.aura_remaining_seconds(family),
			"stacks": 0,
			"max_stacks": 0,
		})
		if family == EFFECT_SHADOWVEIL:
			manager.stealth_changed.emit(true)


# --- Reporting ----------------------------------------------------------------

## Rows for the 1 Hz `status.sync` push, in [StatusService]'s wire shape.
## [param as_debuff] picks the strip: an aura on the drinker is a BUFF, a stack
## on a victim is a DEBUFF.
func status_rows(as_debuff: bool) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var now: int = Time.get_ticks_msec()
	if as_debuff:
		for family: StringName in _stacks:
			var left: int = ceili((int(_stacks[family]["expires_ms"]) - now) / 1000.0)
			if left <= 0:
				continue
			rows.append({
				"id": String(family),
				"remaining": left,
				"stacks": int(_stacks[family]["stacks"]),
			})
		return rows
	for family: StringName in _auras:
		var remaining: int = aura_remaining_seconds(family)
		if remaining > 0:
			rows.append({"id": String(family), "remaining": remaining})
	return rows


func _describe_stack(family: StringName, entry: Dictionary) -> Dictionary:
	return {
		"remaining": maxi(0, ceili((int(entry["expires_ms"]) - Time.get_ticks_msec()) / 1000.0)),
		"stacks": int(entry["stacks"]),
		"max_stacks": int(entry["max_stacks"]),
		"family": String(family),
	}


## Tooltip lines for [param potion]'s aura. Lives here rather than on the item so
## that changing what a family DOES and changing what the tooltip SAYS are the
## same edit — the pattern [ConsumableItem._coating_effect_line] already sets.
##
## Plain literals, not tr(): a static function cannot call tr() in GDScript, and
## the silent parse error that causes drops the whole class.
static func describe(potion: PotionItem) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if potion == null or not potion.is_aura():
		return lines
	# "5m", not "300s" — the same wording every other timed line on a potion
	# tooltip uses, so a 300s aura and a 300s buff on the SAME vial do not read as
	# two different lengths.
	var span: String = _format_span(potion.aura_duration_s)
	match potion.aura_effect:
		EFFECT_CINDER_GUARD:
			lines.append("Melee attackers are set alight for %d damage" % int(
				potion.aura_potency * potion.aura_payload_duration_s
			))
			lines.append("Once per attacker every %ss" % (
				"%.1f" % potion.aura_internal_cooldown_s
			))
			lines.append("Lasts %s" % span)
		EFFECT_SHADOWVEIL:
			lines.append("Hostiles cannot see you for %s" % span)
			lines.append(
				"Attacking, casting or gathering breaks the veil"
				if potion.aura_breaks_on_gather
				else "Attacking or taking a hit breaks the veil — gathering does not"
			)
		EFFECT_PROVOCATION:
			lines.append("Up to %d nearby enemies attack you" % potion.aura_max_targets)
			lines.append("Re-provokes every %ss for %s" % [
				"%.1f" % potion.aura_pulse_s, span,
			])
		_:
			lines.append("Lasts %s" % span)
	return lines


## "5m" / "1m 30s" / "45s". Mirrors [method ConsumableItem._format_duration]
## rather than calling it: that one is the item layer's own private helper, and a
## status service reaching into it would couple the two in the wrong direction.
## Same rule about not truncating the remainder — a 90s aura is not "1m".
static func _format_span(seconds: float) -> String:
	var whole: int = int(seconds)
	if whole < 60:
		return "%ds" % whole
	var minutes: int = whole / 60
	var rest: int = whole % 60
	return "%dm" % minutes if rest == 0 else "%dm %ds" % [minutes, rest]
