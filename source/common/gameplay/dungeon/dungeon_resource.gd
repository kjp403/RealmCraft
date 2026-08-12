class_name DungeonResource
extends InstanceResource
## A dungeon's RULES as data, looked up by its instance_name in the
## instance_collection (DungeonResource IS an InstanceResource, so the collection
## scan registers it automatically). This puts the reward / description / levels /
## difficulty in ONE file instead of scattering them across the map scene's
## RoomNodes — the map scene keeps only encounter authoring (SpawnMarkers), and
## DungeonService reads the reward off the RUN's resource on clear.

## Pretty name shown in the lobby title (falls back to instance_name if blank).
@export var display_name: String = ""
## Max party size for a single run.
@export var party_size: int = 4
## Shown in the dungeon manager / lobby.
@export_multiline var description: String = ""
## Soft level suggestion the dungeon manager surfaces. The entry FLOOR is the
## inherited InstanceResource.level_min (the zone-owned single source of truth,
## and the future v1 can_join_instance hard gate) — the duplicate min_level
## export this class carried was retired 2026-07-20.
@export var recommended_level: int = 1

@export_group("Rewards")
## Completion reward on Normal; the richer one on Hard (falls back to [member
## reward] if Hard's is left null).
@export var reward: DungeonReward
@export var hard_reward: DungeonReward

@export_group("Difficulty")
## Applied to every mob a Normal run spawns (1.0 = authored EnemyType stats).
## Use this to target midgame kits (e.g. Runite + Fire) without buffing the
## same archetypes in the overworld.
@export var normal_health_mult: float = 1.0
@export var normal_damage_mult: float = 1.0
## Extra multipliers stacked on bosses only (Normal and Hard). Lets trash stay
## snappy while bosses last long enough to force potions.
@export var boss_health_mult: float = 1.0
@export var boss_damage_mult: float = 1.0

@export_group("Hard mode")
## Absolute multipliers for Hard runs (not stacked on Normal mults).
@export var hard_health_mult: float = 2.0
@export var hard_damage_mult: float = 1.5


## Pretty name everywhere (lobby title, entered/left banners, recap): prefers
## display_name, else the base InstanceResource fallback (zone_title /
## prettified instance_name).
func display_title() -> String:
	return display_name if not display_name.is_empty() else super.display_title()


## Legacy alias — older lobby code calls title(); same value as display_title().
func title() -> String:
	return display_title()
