class_name PrayerResource
extends Resource
## One prayer the player can switch on. A prayer is a TOGGLE, not a timed buff:
## while it is on it grants [member modifiers] and drains prayer points; when
## the points run out (or the player switches it off) the modifiers come back
## off. See [PrayerService].
##
## Authored as .tres files under `prayer/prayers/` and listed in
## [PrayerBook.PRAYERS]. Not a registry content type — prayers are referenced by
## slug over the wire, never by a numeric id, so they need no index entry.

## Stable id used over the wire and in the saved "prayers I have on" set. Comes
## from the filename slug; do NOT rename one after release.
@export var slug: StringName = &""
@export var display_name: String = "Prayer"
@export_multiline var description: String = ""
@export var icon: Texture2D

## Prayer level needed to switch it on.
@export_range(1, 99, 1) var required_level: int = 1

## Points burned per MINUTE while active. Authored per minute (not per second)
## because that is the scale players reason in — "1 point a minute" — and the
## drain tick converts. See PrayerService.DRAIN_TICK_S.
@export_range(0.0, 120.0, 0.1) var drain_per_minute: float = 1.0

## Stat bonuses granted while active, applied through the same modify_stat path
## BuffService uses so a prayer stacks with gear and buffs predictably.
@export var modifiers: Array[StatModifier] = []

## Groups this prayer competes in. Switching it on turns off every OTHER active
## prayer sharing any of these groups (the OSRS "one protect prayer" rule).
## Empty = stacks with everything.
##
## An ARRAY, not one group, because Piety is both an attack and a defence
## prayer and has to cancel each ladder's lower rungs.
## Convention: &"protection" / &"offence" / &"defence".
@export var exclusive_groups: Array[StringName] = []


## True when switching this on must switch [param other] off.
func conflicts_with(other: PrayerResource) -> bool:
	if other == null or other == self:
		return false
	for group: StringName in exclusive_groups:
		if other.exclusive_groups.has(group):
			return true
	return false


## "+10 Armor, +5 Attack Damage" — the effect line for the prayer book.
func describe_modifiers() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for modifier: StatModifier in modifiers:
		if modifier == null or is_zero_approx(modifier.value):
			continue
		parts.append(GearItem._format_modifier(modifier))
	return ", ".join(parts)


## "1 pt/min" / "0.5 pt/min" — the drain line for the prayer book.
func describe_drain() -> String:
	if is_equal_approx(drain_per_minute, roundf(drain_per_minute)):
		return "%d pt/min" % int(drain_per_minute)
	return "%.1f pt/min" % drain_per_minute
