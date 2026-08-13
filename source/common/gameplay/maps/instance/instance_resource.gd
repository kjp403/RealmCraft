class_name InstanceResource
extends Resource

## [DEFAULT] - uses default map spawn logic.
## [ENTRY] - spawn player on map entrance.
## [WORLD] - spawn player on default map spawn.
enum SpawnOverride {
	DEFAULT,
	ENTRY,
	WORLD
}

@export var instance_name: StringName
@export_file("*.tscn") var map_path: String
@export var load_at_startup: bool = false
@export var spawn_override: SpawnOverride = SpawnOverride.DEFAULT

@export_group("Zone display")
## Player-facing zone name ("Goblin Woodland"). Empty = capitalized instance_name.
@export var zone_title: String = ""
## The zone's intended level band. Shown as the banner subtitle ("Levels 1-5")
## and intended as the single source of truth for entry gating too — warper
## warnings and the future v1 wardstone can_join_instance check should read
## THESE numbers, not carry their own, so every door into a zone agrees. 0 = no band.
@export var level_min: int = 0
@export var level_max: int = 0
## Show the zone banner when a player enters this instance's map (see ZoneDiscovery).
@export var show_discovery: bool = false

@export_group("Progression")
## Wardstone slug required to enter (docs/wardstones.md) — the previous biome's
## stone on the critical path (e.g. fungus_cave requires &"woodland"). Empty =
## open. Checked server-side in can_join_instance; levels are advisory only.
@export var required_wardstone: StringName = &""

@export_group("Death return")
## When set, dying in this instance ejects the player here (e.g. boss arenas
## return to Castle Garden) instead of the local RespawnPoint. Empty = stay
## on this map and use [method Map.get_spawn_position].
@export var death_return_instance: InstanceResource
## Warper id inside [member death_return_instance] to land on (0 = default spawn).
@export var death_return_warper_id: int = 0

@export_group("Zone difficulty")
## Multiplies the max health of every NON-BOSS hostile spawned in this instance
## (1.0 = authored values; [member EnemyTypeResource.is_boss] mobs always keep their
## authored HP, since a finale is tuned as its own fight). Tune a zone's pacing
## without touching EnemyTypeResources that other maps share — Bandit Hideout runs its roster at 0.5, but the sorcerer and
## captain it shares with the Forest keep full health there. Mob XP derives from
## live HP (EnemyTypeResource.combat_skill_xp_for), so a scaled zone pays out in
## proportion and can't become an XP-per-kill outlier. Applied in HostileNpc._ready.
@export var enemy_health_mult: float = 1.0

@export_group("Zone kill loot")
## Extra independent loot rolls applied to EVERY hostile kill in this instance.
## Use for zone-wide rares (e.g. Wood Silver chests in Goblin Woodlands) so new
## NPCs placed here inherit the drop without editing each enemy type.
@export var zone_kill_loot: Array[LootDrop] = []

var loading_instances: Array
var charged_instances: Array[Node]


## Banner title: explicit zone_title, else the instance_name prettified
## ("bandit_hideout" -> "Bandit Hideout").
func display_title() -> String:
	return zone_title if not zone_title.is_empty() else String(instance_name).capitalize()


## Banner subtitle from the level band. Zone level bands are retired — combat
## level now lives on NPCs — so this always returns empty.
func level_band() -> String:
	return ""


@warning_ignore("unused_parameter")
func can_join_instance(player: Player, index: int = -1) -> bool:
	# Wardstone gate (docs/wardstones.md): character-wide progress key, no
	# level or party bypass. Everything else stays open.
	if required_wardstone.is_empty():
		return true
	if player == null or player.player_resource == null:
		return false
	return player.player_resource.wardstones.has(String(required_wardstone))


func get_instance(index: int = -1) -> Node:
	if charged_instances.is_empty() or charged_instances.size() <= index:
		return null
	return charged_instances[index]
