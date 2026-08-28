class_name WardAbility
extends AbilityResource
## SPECTRAL WARD — the Heavy Weapons tank's signature: shields that orbit the
## caster, cut a FLAT percentage off every hit they take, and throw the absorbed
## damage straight back at whoever dealt it.
##
## Why a flat cut and not more armor (which is what [GuardAbility] does): armor is
## a diminishing percentage of the attacker's number, so against a boss hitting for
## 300 a +50 armor swing is nearly invisible, and the tank never gets a moment
## where they feel like a tank. [member damage_reduction_pct] is legible from the
## damage numbers themselves — "that slam hit me for 180 instead of 300" — and it
## scales WITH boss damage instead of against it. It rides
## [member Character.ward_damage_mult] through [WardState], so it multiplies with
## armor rather than competing with it.
##
## The REFLECT is what makes it the tank's ability rather than a generic defensive:
## a tank's whole job is to be the one being hit, so paying them for it turns the
## Mighty Roar → Spectral Ward pull into real damage instead of dead time. Note it
## scales off the reduction — a bigger cut absorbs more, so it reflects more.
##
## Server owns the mitigation and the reflect; every peer draws the orbiting
## shields from the action.perform echo (the Meteor pattern), so allies read the
## tank's cooldown without a second push topic.


## Fraction of incoming damage removed while the ward holds. 0.30 = you take 70%.
## Clamped to [constant MAX_REDUCTION] on use — a 100% ward is an invulnerability
## button (and, with the reflect, an infinite-damage one), not a cooldown.
@export_range(0.0, 0.75, 0.01) var damage_reduction_pct: float = 0.30
## Share of the ABSORBED damage thrown back at the attacker. 1.0 = all of it.
@export_range(0.0, 1.0, 0.05) var reflect_ratio: float = 1.0
@export var duration_s: float = 6.0
## Flat ARMOR granted alongside the cut (0 = pure reduction). Small by design —
## the percentage is the ability; this is texture.
@export var armor_bonus: float = 0.0
## Flat MAGIC RESIST granted for the same window (0 = none).
@export var mr_bonus: float = 0.0
## Shields drawn orbiting the caster. Purely a tier tell — you can count them.
@export_range(1, 6) var shield_count: int = 3
@export var orbit_radius: float = 20.0
@export var ward_color: Color = Color(0.55, 0.78, 1.0)

## Hard ceiling on [member damage_reduction_pct] — see its doc comment.
const MAX_REDUCTION: float = 0.75


func use_ability(user: Entity, _direction: Vector2) -> void:
	if user is not Character:
		return
	var caster: Character = user as Character
	if GameMode.is_client():
		_spawn_visual(caster)
	if not GameMode.is_world_server() or caster is not Player:
		return
	WardState.install(caster, 1.0 - _reduction(), reflect_ratio, duration_s)
	if armor_bonus > 0.0:
		BuffService.apply(caster as Player, Stat.ARMOR, armor_bonus, duration_s)
	if mr_bonus > 0.0:
		BuffService.apply(caster as Player, Stat.MR, mr_bonus, duration_s)


func _reduction() -> float:
	return clampf(damage_reduction_pct, 0.0, MAX_REDUCTION)


## Orbiting shields on the caster, on every client. One at a time: re-casting
## replaces the ring rather than stacking two out-of-phase orbits on one body.
func _spawn_visual(caster: Character) -> void:
	var existing: Node = caster.get_node_or_null(NodePath(ShieldWard.NODE_NAME))
	if existing != null:
		existing.queue_free()
	var ward: ShieldWard = ShieldWard.new()
	ward.name = ShieldWard.NODE_NAME
	ward.duration = duration_s
	ward.shield_count = shield_count
	ward.radius = orbit_radius
	ward.color = ward_color
	caster.add_child(ward)


func extra_stat_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("-%d%% damage taken" % int(round(_reduction() * 100.0)))
	if reflect_ratio > 0.0:
		# Say what the player will SEE: the reflect is a multiple of the damage
		# that still gets through, not of the raw incoming hit.
		var absorbed_vs_taken: float = (1.0 / maxf(0.01, 1.0 - _reduction())) - 1.0
		lines.append("reflects %d%% of the damage it blocks" % int(round(reflect_ratio * 100.0)))
		lines.append("= %sx the damage you take, back at them"
			% fmt_num(snappedf(absorbed_vs_taken * reflect_ratio, 0.1)))
	if armor_bonus > 0.0:
		lines.append("+%s armor" % fmt_num(armor_bonus))
	if mr_bonus > 0.0:
		lines.append("+%s magic resist" % fmt_num(mr_bonus))
	lines.append("%ss ward" % fmt_num(duration_s))
	return lines
