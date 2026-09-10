class_name CoatingService
## Weapon coatings — a timed self buff that makes every hit you LAND do
## something extra. Smear a vial on your weapon and it stays coated until the
## timer runs out: poison and ember burn what you hit, salve heals you back.
##
## Deliberately NOT a [BuffService] entry: that stores {stat, amount} and pipes
## through modify_stat, and "your hits poison" is not a stat. It lives in the
## same place though — a runtime-only field on the [PlayerResource], so it
## survives an instance change within a session and dies naturally on logout,
## exactly like [member PlayerResource.active_buffs].
##
## TWO SLOTS, one draught in each. The OFFENSIVE slot holds whichever of poison
## / ember / corrode / venom you chose; the SUSTAIN slot holds the Weapon Salve.
## Within a slot it is still one at a time, by design (owner call): drinking a
## second coating of the same kind of slot is REFUSED, not merged and not
## refreshed, which is why [method apply] returns a bool instead of quietly
## winning. Across slots they stack.
##
## The salve started out sharing the offensive slot, and that made it a draught
## nobody drank: it is lifesteal on hit, so its whole job is to keep you alive
## while you fight, and the price of drinking it was giving up the damage you
## were fighting WITH. Choosing between "kill it faster" and "survive it" is not
## the decision the one-slot rule was written to protect — that rule exists so
## picking poison over ember means something — and the salve lost it every time.
## It now runs alongside a damage coating and only ever competes with itself.
##
## It does NOT hold the combat-draught slot any more either (see
## [method ConsumableItem.draught_slot_busy]), so a Defense Tonic and a salve
## coexist for the same reason.
##
## Server-side only. [method on_hit] is called from [method CombatHit.try_damage],
## which is the ONE place every melee arc and projectile resolves a hit, so a
## new weapon type is coatable with no code of its own.

## Coating kinds. POISON and BURN attach a [DamageOverTime] of that name to the
## victim (both already have status art and a victim-side tooltip); HEAL pays
## the attacker instead and touches the victim not at all.
const KIND_POISON: StringName = &"poison"
const KIND_BURN: StringName = &"burn"
const KIND_HEAL: StringName = &"heal"
## Corrosive Ember Draught: a capped, stacking, percentage armor strip plus a
## minor burn. Not a DOT_KIND — its damage is only half of what it does, and the
## stack ledger lives on [StatusEffectManager], so it is routed separately in
## [method on_hit].
const KIND_CORRODE: StringName = &"corrode"
## Venom Draught: a true damage-over-time keyed by the PLAYER who applied it, so
## two players' venoms tick independently instead of overwriting one another.
## Also not a DOT_KIND, because a plain [DamageOverTime] is exactly the
## source-blind behaviour it exists to replace.
const KIND_VENOM: StringName = &"venom"

## Kinds whose effect is a damage-over-time on the victim. Everything else is
## resolved on the attacker.
const DOT_KINDS: Array[StringName] = [KIND_POISON, KIND_BURN]

## Kinds that ride the SUSTAIN slot instead of the offensive one, and so stack
## with a damage coating. Membership is by KIND rather than by item, so a second
## sustain draught added later inherits the whole rule — the slot routing, the
## expiry, the status row and the refusal — by naming its kind here.
const SUSTAIN_KINDS: Array[StringName] = [KIND_HEAL]

## Kinds that need per-victim tuning beyond {potency, hit_duration_s} and are
## therefore carried in the coating's [code]extras[/code] bag. Listed so
## [method ConsumableItem.is_coating] can accept them without treating a missing
## hit_duration_s as an authoring slip.
const EXTRA_KINDS: Array[StringName] = [KIND_CORRODE, KIND_VENOM]

## Status-strip ids are prefixed so a coating can never collide with the DEBUFF
## of the same name — "poison" on the victim's strip means they are poisoned,
## "coating_poison" on yours means your blade is.
const STATUS_PREFIX: String = "coating_"


## True when [param kind] burns the victim over time rather than paying the
## attacker.
static func is_dot_kind(kind: StringName) -> bool:
	return DOT_KINDS.has(kind)


## True when [param kind] belongs in the SUSTAIN slot rather than the offensive
## one. Asked by [ConsumableItem] before it decides which slot to gate on, so
## the bag button, the hotbar tile and the server all route the same vial the
## same way.
static func is_sustain_kind(kind: StringName) -> bool:
	return SUSTAIN_KINDS.has(kind)


## Status-strip id for [param kind], e.g. &"poison" -> "coating_poison".
static func status_id(kind: StringName) -> String:
	return STATUS_PREFIX + String(kind)


## Coat [param player]'s weapon for [param duration_s] seconds.
##
## Returns FALSE and changes nothing when a coating is already running IN THE
## SLOT THIS KIND USES — the caller must not consume the vial in that case. A
## salve and an ember never refuse each other; two embers, or two salves, do.
## Callers that want to explain the refusal should check [method is_active] /
## [method is_sustain_active] first so they can name the coating already there.
## [param extras] carries the per-kind tuning that does not fit {potency,
## hit_duration_s} — the corrosion stack budget, the venom's source-keying rule.
## An untouched dictionary is the default, so every existing caller is unchanged.
static func apply(
	player: Player,
	kind: StringName,
	potency: float,
	hit_duration_s: float,
	duration_s: float,
	extras: Dictionary = {}
) -> bool:
	if player == null or player.player_resource == null:
		return false
	if kind.is_empty() or potency <= 0.0 or duration_s <= 0.0:
		return false
	if is_dot_kind(kind) and hit_duration_s <= 0.0:
		return false
	var sustain: bool = is_sustain_kind(kind)
	if _slot_active(player, sustain):
		return false
	var entry: Dictionary = {
		"kind": String(kind),
		"potency": potency,
		"hit_duration_s": hit_duration_s,
		"expires_ms": Time.get_ticks_msec() + int(duration_s * 1000.0),
		"extras": extras,
	}
	if sustain:
		player.player_resource.weapon_salve = entry
	else:
		player.player_resource.weapon_coating = entry
	return true


## Is the OFFENSIVE slot busy? This is the one [method
## ConsumableItem.draught_slot_busy] asks, so it must stay the offensive slot
## alone: widening it to "either slot" would put the salve back to blocking the
## tonics and the auras, which is the whole thing this split undoes.
static func is_active(player: Player) -> bool:
	return _slot_active(player, false)


## Is the SUSTAIN slot busy? Only another salve cares.
static func is_sustain_active(player: Player) -> bool:
	return _slot_active(player, true)


## The offensive coating currently on the weapon, or &"" when it carries none.
## Used to name the running coating when a second one is refused.
static func active_kind(player: Player) -> StringName:
	return _slot_kind(player, false)


## The sustain coating currently on the weapon, or &"" when it carries none.
static func sustain_kind(player: Player) -> StringName:
	return _slot_kind(player, true)


## Whole seconds left on the offensive slot, for the status-icon countdown.
## 0 when uncoated.
static func remaining_seconds(player: Player) -> int:
	return _slot_remaining(player, false)


## Whole seconds left on the sustain slot. 0 when unsalved.
static func sustain_remaining_seconds(player: Player) -> int:
	return _slot_remaining(player, true)


## Wipes BOTH slots outright, whatever is left on them. Death calls this beside
## [method BuffService.clear_all]: the offensive coating shares the one COMBAT
## DRAUGHT slot with those buffs, so leaving it behind when they go would let a
## corpse walk back holding a slot it no longer shows an icon for. The salve
## holds no slot, but it is still a draught the corpse paid for and stops
## showing an icon for, so it goes with them.
static func clear(player: Player) -> void:
	if player == null or player.player_resource == null:
		return
	player.player_resource.weapon_coating = {}
	player.player_resource.weapon_salve = {}


## Drops either coating once it has run out. Called from the instance's 1 Hz
## status tick alongside [method BuffService.tick] so the field is empty the same
## second the icon disappears — which also means the next vial is drinkable the
## moment the strip clears, rather than on the next swing.
static func tick(player: Player) -> void:
	if player == null or player.player_resource == null:
		return
	var resource: PlayerResource = player.player_resource
	var now: int = Time.get_ticks_msec()
	if (
		not resource.weapon_coating.is_empty()
		and now >= int(resource.weapon_coating.get("expires_ms", 0))
	):
		resource.weapon_coating = {}
	if (
		not resource.weapon_salve.is_empty()
		and now >= int(resource.weapon_salve.get("expires_ms", 0))
	):
		resource.weapon_salve = {}


## The live entry in one slot, or an empty dictionary when it is clean or
## elapsed. Every reader below goes through it, so an expired coating can never
## read as active in one of them and inactive in another.
static func _slot(player: Player, sustain: bool) -> Dictionary:
	if player == null or player.player_resource == null:
		return {}
	var entry: Dictionary = (
		player.player_resource.weapon_salve if sustain
		else player.player_resource.weapon_coating
	)
	if entry.is_empty():
		return {}
	if Time.get_ticks_msec() >= int(entry.get("expires_ms", 0)):
		return {}
	return entry


static func _slot_active(player: Player, sustain: bool) -> bool:
	return not _slot(player, sustain).is_empty()


static func _slot_kind(player: Player, sustain: bool) -> StringName:
	return StringName(str(_slot(player, sustain).get("kind", "")))


static func _slot_remaining(player: Player, sustain: bool) -> int:
	var entry: Dictionary = _slot(player, sustain)
	if entry.is_empty():
		return 0
	return maxi(0, ceili((int(entry["expires_ms"]) - Time.get_ticks_msec()) / 1000.0))


## Fire BOTH coatings on a landed hit, if [param source] is a player carrying
## them. Called AFTER the hit is resolved and dealt, so every target rule (safe
## zones, allegiance, deflect) has already had its say.
##
## Both slots resolve off the SAME hit: a salved, envenomed swing poisons what it
## lands on and pays the swinger back, which is the point of splitting them.
static func on_hit(source: Character, victim: Character) -> void:
	if source is not Player or victim == null:
		return
	var player: Player = source as Player
	_fire_slot(player, victim, false)
	_fire_slot(player, victim, true)


static func _fire_slot(player: Player, victim: Character, sustain: bool) -> void:
	var coating: Dictionary = _slot(player, sustain)
	if coating.is_empty():
		return
	var kind: StringName = StringName(str(coating.get("kind", "")))
	var potency: float = float(coating.get("potency", 0.0))
	var hit_duration_s: float = float(coating.get("hit_duration_s", 0.0))
	var extras: Dictionary = coating.get("extras", {})
	if is_dot_kind(kind):
		DamageOverTime.apply(victim, player, kind, potency, hit_duration_s)
	elif kind == KIND_HEAL:
		# Pays the ATTACKER, not the victim. counts_as_combat_heal stays true so
		# the sear-wound interaction sees it like any other in-combat heal.
		player.apply_heal(potency, player, true)
	elif kind == KIND_CORRODE:
		# Two payloads off one hit: the stack ledger (capped, refresh-only) and a
		# deliberately minor burn. The strip is the draught's value; paying full
		# damage on top would make it strictly better than an Ember.
		var manager: StatusEffectManager = StatusEffectManager.for_character(victim)
		if manager != null:
			manager.apply_stack(
				StatusEffectManager.EFFECT_CORRODING_HEAT,
				float(extras.get("armor_per_stack", 0.0)),
				int(extras.get("max_stacks", 0)),
				float(extras.get("stack_duration_s", 0.0))
			)
		if potency > 0.0 and hit_duration_s > 0.0:
			DamageOverTime.apply(victim, player, KIND_BURN, potency, hit_duration_s)
	elif kind == KIND_VENOM:
		StatusEffectManager.apply_source_dot(
			victim, player, KIND_VENOM, potency, hit_duration_s,
			bool(extras.get("per_source", true)),
			CombatHit.DAMAGE_MAGIC,
			float(extras.get("max_lifespan_s", 0.0))
		)
