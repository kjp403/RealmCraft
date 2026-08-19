class_name Stat


const HEALTH: StringName = &"health"
const HEALTH_MAX: StringName = &"health_max"

const MANA: StringName = &"mana"
const MANA_MAX: StringName = &"mana_max"
## Mana restored per second by the instance status tick (base + Spirit + gear).
const MANA_REGEN: StringName = &"mana_regen"

const ENERGY: StringName = &"energy"
const ENERGY_MAX: StringName = &"energy_max"

## Prayer points. The pool is PRAYER_MAX = your Prayer level (OSRS rule), so it
## is recomposed from the skill on every spawn; the CURRENT value is runtime
## state on the PlayerResource, restored on top of the rebuild by
## PrayerService.reapply — if it lived in the recomposed block instead, walking
## into any building would refill it for free.
const PRAYER: StringName = &"prayer"
const PRAYER_MAX: StringName = &"prayer_max"

const SHIELD: StringName = &"shield"

## Physical Resistance
const ARMOR: StringName = &"armor"
## Magic Resistance
const MR: StringName = &"mr"

## Attack Damage
const AD: StringName = &"ad"
## Ability Power
const AP: StringName = &"ap"

const ATTACK_SPEED: StringName = &"attack_speed"
const ATTACK_RANGE: StringName = &"attack_range"

const MOVE_SPEED: StringName = &"move_speed"

const CRIT_CHANCE: StringName = &"crit_chance"
const CRIT_DAMAGE: StringName = &"crit_damage"
const ABILITY_HASTE: StringName = &"ability_haste"

## Conditional damage amp (%): extra damage dealt to targets below a low-HP
## threshold (mastery "Executioner" passive). Read at melee-hit time; 0 for anyone
## without the passive, so it's inert by default. See MeleeArc.
const DAMAGE_VS_LOW_HP: StringName = &"damage_vs_low_hp"

## Lifesteal (%): heal this fraction of damage you DEAL back to yourself. 0 by
## default (inert); the sword "Berserk" active grants a big timed chunk. Applied
## server-side in Character.take_damage on the attacker. See BuffService / Berserk.
const LIFESTEAL: StringName = &"lifesteal"

## Gathering speed multiplier. 1.0 = normal, 1.2 = 20% faster, etc.
const GATHER_SPEED: StringName = &"gather_speed"
## Gathering bonus yield chance. 0.15 = 15% chance of extra resources.
const GATHER_YIELD: StringName = &"gather_yield"
## Gathering XP multiplier. 0.20 = 20% more XP.
const GATHER_XP: StringName = &"gather_xp"


## Player-facing labels for stats shown in tooltips. Anything not listed falls back
## to a capitalized form of the raw key.
const DISPLAY_NAMES: Dictionary = {
	HEALTH_MAX: "Max Health",
	MANA_MAX: "Max Mana",
	MANA_REGEN: "Mana Regen",
	PRAYER_MAX: "Max Prayer",
	ARMOR: "Armor",
	MR: "Magic Resist",
	AD: "Attack Damage",
	AP: "Ability Power",
	ATTACK_SPEED: "Attack Speed",
	ATTACK_RANGE: "Attack Range",
	MOVE_SPEED: "Move Speed",
	CRIT_CHANCE: "Crit Chance",
	CRIT_DAMAGE: "Crit Damage",
	ABILITY_HASTE: "Ability Haste",
	DAMAGE_VS_LOW_HP: "Damage vs Low HP",
	LIFESTEAL: "Lifesteal",
	GATHER_SPEED: "Gather Speed",
	GATHER_YIELD: "Gather Yield",
	GATHER_XP: "Gather XP",
}

## Stats whose value reads as a percentage in UI (rendered "+25%" not "+25").
const PERCENT_STATS: Array[StringName] = [DAMAGE_VS_LOW_HP, LIFESTEAL, GATHER_SPEED, GATHER_YIELD, GATHER_XP]


static func display_name(stat_name: StringName) -> String:
	return DISPLAY_NAMES.get(stat_name, String(stat_name).capitalize())


static func is_percent(stat_name: StringName) -> bool:
	return PERCENT_STATS.has(stat_name)
