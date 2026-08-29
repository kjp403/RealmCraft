class_name DamageInfo
extends RefCounted
## THE attack-origin parser for the Ossuran encounter (and any later fight that
## wants to gate on combat style).
##
## Why this exists at all: [CombatHit]'s three damage types are a MITIGATION
## vocabulary, not a style one. `physical` and `ranged` are both resisted by
## ARMOR — `ranged` exists only to tint the hit splat — and the bow proves the
## gap: [code]arrow.gd[/code] ships its hits as DAMAGE_PHYSICAL. So a phase that
## must accept a sword and refuse a bow CANNOT read damage_type alone, or every
## archer in the instance passes the melee check.
##
## The reliable signal is the one the existing style ward already trusts: the
## attacker's equipped weapon category (see
## [method PlayerResource.equipped_weapon_category]). This class folds the two
## signals together in a fixed priority and hands back a single [enum Style],
## so the arena scripts never re-derive the rule and can never drift apart.
##
## SERVER-ONLY by construction: it reads `player_resource`, which is null on the
## client (every mirror there would silently classify as UNKNOWN). That is fine
## — damage resolution is server-authoritative, and UNKNOWN is treated as
## "never punished" by callers so a mis-parse can never brick a phase.

## Attack origin. UNKNOWN is a deliberate member, not a failure code: environment
## ticks (the cold, a hazard cloud) and NPC-on-NPC damage have no combat style,
## and a phase gate must let those through untouched rather than negate them.
enum Style {
	UNKNOWN,
	MELEE,
	RANGED,
	MAGIC,
}

## Weapon categories, split by style. Mirrors PlayerResource.COMBAT_STYLE_CATEGORIES
## (&"sword", &"hammer", &"bow", &"wand", &"book") — if a sixth category is ever
## added there it must be added here too, or it parses UNKNOWN and ignores wards.
const MELEE_CATEGORIES: Array[StringName] = [&"sword", &"hammer"]
const RANGED_CATEGORIES: Array[StringName] = [&"bow"]
const MAGIC_CATEGORIES: Array[StringName] = [&"wand", &"book"]

## Human-readable style names, indexed by [enum Style]. Used by callouts and by
## the debug print in the verifier.
const STYLE_NAMES: Array[String] = ["Unknown", "Melee", "Ranged", "Magic"]

## Who swung. May be null (environment damage).
var attacker: Character = null
## Post-mitigation amount the hit was going to land for, before any ward factor.
var amount: float = 0.0
## The raw CombatHit type the hit travelled with (physical / ranged / magic).
var raw_type: StringName = CombatHit.DAMAGE_PHYSICAL
## The parsed origin — what every gate in the fight actually reads.
var style: Style = Style.UNKNOWN
## The attacker's weapon category at the moment of the hit (&"" for non-players).
## Kept for callouts ("your bow") and for debugging a mis-parse after the fact.
var weapon_category: StringName = &""


## Parse a hit into its combat style.
##
## Priority is deliberate and must not be reordered:
##   1. raw_type == magic wins outright. A spell is magic no matter what is in
##      the caster's hands — a sword user who casts Meteor is doing MAGIC damage,
##      and Ossuran's melee phase is right to reject it.
##   2. Otherwise a Player is classified by EQUIPPED WEAPON CATEGORY, because
##      that is the only signal that separates a bow from a blade (both arrive
##      as `physical`).
##   3. Anything else (NPC, environment, a player whose resource is unavailable)
##      falls back to the raw type, mapping ranged→RANGED and physical→MELEE.
##      Non-player damage never feeds a style gate, so this branch only has to be
##      sane, not authoritative.
static func parse(
	from: Character,
	damage_amount: float,
	damage_type: StringName = CombatHit.DAMAGE_PHYSICAL
) -> DamageInfo:
	var info: DamageInfo = DamageInfo.new()
	info.attacker = from
	info.amount = damage_amount
	info.raw_type = damage_type

	# 1. Magic is self-declaring and outranks the weapon in hand.
	if damage_type == CombatHit.DAMAGE_MAGIC:
		info.style = Style.MAGIC
		info.weapon_category = _category_of(from)
		return info

	# 2. Players: the weapon category is the truth. This is the branch that
	#    catches the bow-sends-physical trap.
	var category: StringName = _category_of(from)
	info.weapon_category = category
	if not category.is_empty():
		if MELEE_CATEGORIES.has(category):
			info.style = Style.MELEE
		elif RANGED_CATEGORIES.has(category):
			info.style = Style.RANGED
		elif MAGIC_CATEGORIES.has(category):
			info.style = Style.MAGIC
		else:
			info.style = Style.UNKNOWN
		return info

	# 3. Non-player / unresolvable: map straight off the mitigation type.
	if damage_type == CombatHit.DAMAGE_RANGED:
		info.style = Style.RANGED
	elif damage_type == CombatHit.DAMAGE_PHYSICAL:
		info.style = Style.MELEE
	else:
		info.style = Style.UNKNOWN
	return info


## The attacker's equipped weapon category, or &"" when there isn't one to read
## (not a player, or player_resource unavailable — i.e. anywhere but the world
## server). Callers treat &"" as "fall back to the raw damage type".
static func _category_of(from: Character) -> StringName:
	var player: Player = from as Player
	if player == null or player.player_resource == null:
		return &""
	return player.player_resource.equipped_weapon_category()


## True when this hit is the style [param wanted]. UNKNOWN never matches a real
## style, so environment damage is never mistaken for a player's correct answer.
func is_style(wanted: Style) -> bool:
	return style == wanted


## True when the hit carries no combat style at all (environment, NPC-on-NPC).
## Style gates must PASS these through at full damage: the cold aura and a
## pillar's own damage are not the player answering the mechanic.
func is_styleless() -> bool:
	return style == Style.UNKNOWN


## Display name for the parsed style ("Melee"), for callouts and debug output.
func style_name() -> String:
	return STYLE_NAMES[style]
