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
## ONE coating at a time, by design (owner call): drinking any coating while
## another is running is REFUSED, not merged and not refreshed. That is what
## makes the choice of coating a real decision rather than a stack to pile up,
## and it is why [method apply] returns a bool instead of quietly winning.
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

## Kinds whose effect is a damage-over-time on the victim. Everything else is
## resolved on the attacker.
const DOT_KINDS: Array[StringName] = [KIND_POISON, KIND_BURN]

## Status-strip ids are prefixed so a coating can never collide with the DEBUFF
## of the same name — "poison" on the victim's strip means they are poisoned,
## "coating_poison" on yours means your blade is.
const STATUS_PREFIX: String = "coating_"


## True when [param kind] burns the victim over time rather than paying the
## attacker.
static func is_dot_kind(kind: StringName) -> bool:
	return DOT_KINDS.has(kind)


## Status-strip id for [param kind], e.g. &"poison" -> "coating_poison".
static func status_id(kind: StringName) -> String:
	return STATUS_PREFIX + String(kind)


## Coat [param player]'s weapon for [param duration_s] seconds.
##
## Returns FALSE and changes nothing when a coating is already running — the
## caller must not consume the vial in that case. Callers that want to explain
## the refusal should check [method is_active] first so they can name the
## coating already on the weapon.
static func apply(
	player: Player,
	kind: StringName,
	potency: float,
	hit_duration_s: float,
	duration_s: float
) -> bool:
	if player == null or player.player_resource == null:
		return false
	if kind.is_empty() or potency <= 0.0 or duration_s <= 0.0:
		return false
	if is_dot_kind(kind) and hit_duration_s <= 0.0:
		return false
	if is_active(player):
		return false
	player.player_resource.weapon_coating = {
		"kind": String(kind),
		"potency": potency,
		"hit_duration_s": hit_duration_s,
		"expires_ms": Time.get_ticks_msec() + int(duration_s * 1000.0),
	}
	return true


static func is_active(player: Player) -> bool:
	if player == null or player.player_resource == null:
		return false
	var coating: Dictionary = player.player_resource.weapon_coating
	if coating.is_empty():
		return false
	return Time.get_ticks_msec() < int(coating.get("expires_ms", 0))


## The coating currently on the weapon, or &"" when it is clean. Used to name
## the running coating when a second one is refused.
static func active_kind(player: Player) -> StringName:
	if not is_active(player):
		return &""
	return StringName(str(player.player_resource.weapon_coating.get("kind", "")))


## Whole seconds left, for the status-icon countdown. 0 when uncoated.
static func remaining_seconds(player: Player) -> int:
	if not is_active(player):
		return 0
	var left_ms: int = (
		int(player.player_resource.weapon_coating["expires_ms"]) - Time.get_ticks_msec()
	)
	return maxi(0, ceili(left_ms / 1000.0))


## Drops the coating once it has run out. Called from the instance's 1 Hz status
## tick alongside [method BuffService.tick] so the field is empty the same second
## the icon disappears — which also means the next vial is drinkable the moment
## the strip clears, rather than on the next swing.
static func tick(player: Player) -> void:
	if player == null or player.player_resource == null:
		return
	var coating: Dictionary = player.player_resource.weapon_coating
	if coating.is_empty():
		return
	if Time.get_ticks_msec() >= int(coating.get("expires_ms", 0)):
		player.player_resource.weapon_coating = {}


## Fire the coating on a landed hit, if [param source] is a player carrying one.
## Called AFTER the hit is resolved and dealt, so every target rule (safe zones,
## allegiance, deflect) has already had its say.
static func on_hit(source: Character, victim: Character) -> void:
	if source is not Player or victim == null:
		return
	var player: Player = source as Player
	if not is_active(player):
		return
	var coating: Dictionary = player.player_resource.weapon_coating
	var kind: StringName = StringName(str(coating.get("kind", "")))
	var potency: float = float(coating.get("potency", 0.0))
	if is_dot_kind(kind):
		DamageOverTime.apply(
			victim, player, kind, potency, float(coating.get("hit_duration_s", 0.0))
		)
	elif kind == KIND_HEAL:
		# Pays the ATTACKER, not the victim. counts_as_combat_heal stays true so
		# the sear-wound interaction sees it like any other in-combat heal.
		player.apply_heal(potency, player, true)
