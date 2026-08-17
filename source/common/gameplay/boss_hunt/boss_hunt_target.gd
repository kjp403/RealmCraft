class_name BossHuntTarget
extends Resource
## ONE purchasable boss contract. A Boss Hunt is a paid, private 30-minute arena
## where a single boss respawns on a short timer so a party can farm it — the
## rules for each huntable boss live in one .tres under boss_hunt/targets/ and
## BossHuntCatalog scans that folder.
##
## Tuning intent: an instanced boss is the FASTER farm, never the BETTER one.
## The open-world kill stays superior per-kill — a hunt pays [member xp_mult] of
## the archetype's XP — and the arena only wins on throughput (private room, no
## contest, a respawn every few seconds). There is deliberately no solo bonus of
## any kind: a lone hunter fights the boss at its authored strength, and every
## extra body in the room makes it tougher, not weaker.

## Stable id used on the wire (menu selection, lobby state). Falls back to the
## enemy type's slug when left blank.
@export var slug: StringName = &""
## Name shown in the contract board. Falls back to the EnemyTypeResource's.
@export var display_name: String = ""
@export_multiline var description: String = ""
## The archetype the arena spawns. Required — a target without one is skipped.
@export var enemy_type: EnemyTypeResource
## Gold the STARTER pays to open the contract. Party members join free.
@export var cost: int = 0
## Advisory level shown on the contract card (no hard gate).
@export var recommended_level: int = 1

@export_group("Fight tuning")
## SOLO baseline health, as a multiple of the archetype's authored max_health.
## 1.0 = a lone hunter faces exactly the world boss's stat block.
@export var health_mult: float = 1.0
## Health added per EXTRA player in the arena, as a fraction of the solo bar.
## 0.6 means a duo fights 1.6x, a trio 2.2x, a full party 2.8x. Scaling UP is the
## point: a bigger group brings more damage, so the fight has to grow with it or
## four people trivialise a boss one person is meant to struggle with.
@export var health_per_extra_player: float = 0.6
## Applied to the authored attack damage, always.
@export var damage_mult: float = 1.0
## Absolute slam damage for the BossController. 0 = scale the authored slam by
## [member damage_mult] (same as the melee swing).
@export var slam_damage: float = 0.0

@export_group("Farm loop")
## Seconds between one kill and the next spawn. This is the whole point of the
## mode — keep it short.
@export var respawn_delay_s: float = 12.0
## Fraction of the archetype's normal XP a hunt kill pays — character XP, weapon
## mastery and Slayer alike. 0.5 by design: killing the boss where it actually
## lives is worth double, so the open world stays the better place to level and
## the arena is only the faster place to farm loot.
##
## Applied to the AUTHORED payout, never the party-scaled one — see
## BossHuntArena._spawn_boss. Without that, a full party's inflated health bar
## would hand every member ~3x the mastery XP a solo hunter gets.
@export var xp_mult: float = 0.5


## The wire id for this contract: explicit slug, else the enemy type's registry
## slug, else its enemy_type name. Never empty for a valid target.
func contract_id() -> StringName:
	if not slug.is_empty():
		return slug
	if enemy_type == null:
		return &""
	return enemy_type.get_meta(&"slug", enemy_type.enemy_type)


## Name for the contract board / banners.
func title() -> String:
	if not display_name.is_empty():
		return display_name
	if enemy_type == null:
		return "Unknown"
	return enemy_type.display_name if not enemy_type.display_name.is_empty() \
			else String(enemy_type.enemy_type).capitalize()


## Absolute spawn HP for [param player_count] players in the arena: the solo bar
## ([member health_mult] x authored max_health), grown by
## [member health_per_extra_player] for each body past the first. Returns 0 when
## the enemy type is missing, which the caller reads as "leave health alone".
func party_health(player_count: int) -> float:
	if enemy_type == null:
		return 0.0
	var extra: int = maxi(0, player_count - 1)
	var scale: float = health_mult * (1.0 + health_per_extra_player * float(extra))
	return maxf(1.0, enemy_type.max_health * scale)
