class_name AmmoProcService
## On-hit effects carried by the ARROW rather than the bow.
##
## Server-side only. [method on_hit] is called from [method CombatHit.try_damage]
## beside [method CoatingService.on_hit] — the ONE place every melee arc and
## projectile resolves a hit — so no per-weapon or per-ability code is needed and
## a proc cannot be reached by any path that skipped the target rules.
##
## THE ROLL IS SERVER-SIDE AND UNREACHABLE FROM THE CLIENT
## `randf()` runs here, in the authoritative instance, against a chance read from
## the item resource on disk. Nothing the client sends reaches this decision: the
## client does not roll, does not report a proc, and cannot re-roll a miss. It
## learns a proc happened only from the damage payload that comes back, which is
## the same channel every other hit already uses.
##
## ONLY BOW SHOTS PROC
## The hook fires for every landed hit, so the gate is
## `damage_type == CombatHit.DAMAGE_RANGED`: melee sends physical, wands send
## magic, and only a bow sends ranged. Without that gate a quiver in the ammo
## slot would proc off sword swings.
##
## Effects are dispatched by [member AmmoItem.effect_type]. An unknown value is
## IGNORED rather than guessed at — a typo in a .tres should ship as "no proc",
## never as the wrong proc.

## Thermal burn plus an armour shred. `proc_magnitude` is damage per second;
## the shred is a fixed fraction of it so one dial tunes both.
const EFFECT_THERMAL: StringName = &"thermal_burn"
## Converts a fraction of the damage dealt into health for the attacker.
## `proc_magnitude` is that fraction, 0-1.
const EFFECT_SIPHON: StringName = &"life_siphon"
## Radiant splash onto everything near the victim. `proc_magnitude` is the
## splash damage; the victim itself is excluded.
const EFFECT_SPLASH: StringName = &"holy_splash"
## Heavy movement + attack-speed slow. `proc_magnitude` is the slow fraction.
const EFFECT_GRAVITY: StringName = &"gravity_slow"

## Effect kinds the floating combat text colours. Kept as constants because the
## client's FloatingDamageNumber matches on these exact strings — a rename here
## without one there silently drops the splat back to default orange.
const SPLAT_THERMAL: StringName = &"arrow_thermal"
const SPLAT_SIPHON: StringName = &"arrow_siphon"
const SPLAT_SPLASH: StringName = &"arrow_splash"
const SPLAT_GRAVITY: StringName = &"arrow_gravity"

## Radius of the Celestial splash, in pixels.
const SPLASH_RADIUS: float = 72.0
## Cap on colliders the splash query returns. Well clear of a packed camp;
## anything past it is dropped, which reads in-game as "it missed that one".
const SPLASH_MAX_TARGETS: int = 16
## Armour removed by a thermal burn, as a multiple of its damage-per-second.
const THERMAL_SHRED_RATIO: float = 0.5

## Re-entrancy guard. The Celestial splash deals its damage back through
## CombatHit.try_damage so each splash target gets the full target rules — which
## means try_damage calls straight back into on_hit. Without this a splash procs
## a splash procs a splash: at a 20% chance in a packed camp that is an
## exponential chain, and it would surface as a server hang rather than as
## anything a player could describe. Server logic is single-threaded per
## instance, so a plain static flag is sufficient and cheaper than threading a
## depth parameter through CombatHit's signature.
static var _resolving: bool = false


## Fire the equipped ammunition's proc on a landed hit.
##
## Called AFTER the damage is dealt and after every target rule has had its say,
## so a proc can never reach a target the shot itself was not allowed to hit.
## [param damage] is the amount that actually landed — the siphon is a fraction
## of it, so a hit softened by armour siphons proportionally less.
static func on_hit(
	source: Character, victim: Character, damage: float, damage_type: StringName
) -> void:
	if damage_type != CombatHit.DAMAGE_RANGED:
		return
	if source is not Player or victim == null or victim.is_dead:
		return
	var player: Player = source as Player
	if player.player_resource == null or player.equipment_component == null:
		return
	var ammo: AmmoItem = _equipped_ammo(player)
	if ammo == null or not ammo.has_proc():
		return
	if _resolving:
		return
	if randf() >= ammo.proc_chance:
		return

	_resolving = true
	match ammo.effect_type:
		EFFECT_THERMAL:
			_thermal(player, victim, ammo)
		EFFECT_SIPHON:
			_siphon(player, victim, ammo, damage)
		EFFECT_SPLASH:
			_splash(player, victim, ammo)
		EFFECT_GRAVITY:
			_gravity(victim, ammo)
		_:
			pass  # unknown effect_type: ship as no proc, never as a wrong proc
	_resolving = false


## The AmmoItem currently slotted, or null. The slot holds only an id and the
## stack is bag-resident, so it can be traded or banked out from under the slot
## — every reader has to tolerate "points at an id you no longer own".
static func _equipped_ammo(player: Player) -> AmmoItem:
	var ammo_id: int = int(player.equipment_component.slots.values.get(&"ammo", 0))
	if ammo_id <= 0:
		return null
	return ContentRegistryHub.load_by_id(&"items", ammo_id) as AmmoItem


## Dragon: a searing burn that also softens the armour it is burning through.
## The shred is derived from the burn rate rather than authored separately, so
## the two can never drift apart in the .tres.
static func _thermal(player: Player, victim: Character, ammo: AmmoItem) -> void:
	DamageOverTime.apply(
		victim, player, SPLAT_THERMAL, ammo.proc_magnitude, ammo.proc_duration_s,
		CombatHit.DAMAGE_RANGED
	)
	TimedDebuff.apply(
		victim, SPLAT_THERMAL, ammo.proc_duration_s,
		ammo.proc_magnitude * THERMAL_SHRED_RATIO
	)


## Obsidian: pays the ATTACKER a fraction of what landed. Routed through
## apply_heal with counts_as_combat_heal so the sear-wound interaction sees it
## like any other in-combat heal rather than as free sustain.
static func _siphon(
	player: Player, _victim: Character, ammo: AmmoItem, damage: float
) -> void:
	var healed: float = damage * ammo.proc_magnitude
	if healed <= 0.0:
		return
	player.apply_heal(healed, player, true, SPLAT_SIPHON)


## Celestial: a radiant burst onto everything ADJACENT to the victim. The victim
## is excluded — it already took the arrow, and paying it twice would make this
## a damage multiplier on a single target rather than an AoE.
##
## Each splash target is routed back through CombatHit.try_damage rather than
## take_damage directly, so the zone, allegiance and spar rules run per target.
## A burst next to a guildmate must not hit them.
static func _splash(player: Player, victim: Character, ammo: AmmoItem) -> void:
	for body: Node2D in CombatHit.bodies_in_circle(
		victim, victim.global_position, SPLASH_RADIUS, SPLASH_MAX_TARGETS
	):
		var other: Node2D = body
		if other is HurtBox:
			other = (other as HurtBox).character
		if other == null or other == victim or other == player:
			continue
		CombatHit.try_damage(
			player, other, ammo.proc_magnitude, CombatHit.DAMAGE_RANGED, false, SPLAT_SPLASH
		)


## Astralite: heavy gravity. Slows movement by proc_magnitude and attack speed
## by half that, on players and NPCs alike — see TimedDebuff for why this cannot
## go through BuffService.
static func _gravity(victim: Character, ammo: AmmoItem) -> void:
	TimedDebuff.apply(
		victim, SPLAT_GRAVITY, ammo.proc_duration_s,
		0.0, ammo.proc_magnitude, ammo.proc_magnitude * 0.5
	)
