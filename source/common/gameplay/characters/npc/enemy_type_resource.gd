class_name EnemyTypeResource
extends Resource
## Data-driven enemy definition. Drop one of these into a HostileNpc node's
## `enemy_data` slot and the NPC reads its stats / loot / AI knobs from this
## resource instead of inspector-tuned per-instance @exports. Mirrors how
## ShopResource powers a shop NPC and CraftingStationResource powers
## CraftingStation — the pattern is "one .tres = one enemy archetype, drop
## it into many instances."
##
## Why: balancing a tier of enemies means editing one file, not N nodes. New
## enemy types are pure data — no scene authoring beyond placing the generic
## hostile_npc.tscn somewhere on the map.
##
## Fields the NPC node still owns: position, detection_area (needs a node
## reference), per-instance overrides via the inspector if you want a one-off.

## Identifier matched against quest KILL objectives (&"iron_golem", &"wolf",
## etc.). Enemies with the same enemy_type aggregate to the same objective —
## useful for "elite" variants that share progression.
@export var enemy_type: StringName

## Friendly name for UI / chat announcements (e.g. "Iron Golem").
@export var display_name: String

## Sprite the NPC renders with. Keep this on the resource so a re-skin is a
## one-file change.
@export var skin: SpriteFrames
## Visual size multiplier — a boss reads BIGGER. Scales the sprite (and matching
## HurtBox / click volume). The CharacterBody2D nav capsule stays unscaled so the
## mob can still close to melee range. 1.0 = normal.
@export var visual_scale: float = 1.0
## A BOSS type. A dungeon RoomNode gives any boss-type mob it spawns a BossController
## (phases, telegraphed slam, enrage) and keeps its loot — no per-marker flag needed.
@export var is_boss: bool = false

@export_group("Combat")
## Player-facing combat level shown on the nameplate ("Slime (Lv 16)").
## 0 = derive a band from HP / damage / armor so every hostile still shows one.
@export var combat_level: int = 0
@export var max_health: float = 50.0
@export var attack_damage: float = 8.0
## Seconds between auto-attacks while in range.
@export var attack_cooldown: float = 1.5
@export var armor: float = 0.0
## Magic resistance — mitigates magic damage (wand bolts) the way armor mitigates
## physical. Default 0: mob toughness is tuned via HP; reserve MR for the rare
## "resists magic" archetype so the stat means something when it appears.
@export var mr: float = 0.0
## Optional weapon. Null = melee AoE attacker.
@export var weapon: WeaponItem

@export_group("Behaviors")
## Composable server-side behaviors (docs/hostile_npc_refactor.md): drop in a
## LungeBehavior etc. Runs alongside the base chase/attack chassis. (The old
## flat lunge_* fields were migrated into LungeBehavior sub-resources on every
## user and deleted, 2026-07-09.)
@export var behaviors: Array[MobBehavior]
## What the mob DOES on its swing timer (attack_cooldown = the global swing
## rate). Order = priority: each swing goes to the FIRST attack whose own
## recharge is up and whose target exists. EMPTY = the classic default —
## a WeaponAttack if `weapon` is set, else a MeleeAttack at engagement range
## (synthesized in _apply_enemy_data; no .tres needs authoring for the basics).
@export var attacks: Array[MobAttack]

@export_group("AI & Movement")
@export var move_speed: int = 20
@export var distance_to_attack: int = 20
## Leash radius. The mob will chase / attack up to this far from its spawn
## point; cross it and the mob disengages and walks home (regenerates HP
## en route at the boosted return speed). Tune small for tight cave mobs,
## bigger for open-field mobs that need to allow comfortable ranged
## engagement. ~300 default = bow at full draw + a bit of breathing room.
@export var max_distance_from_spawn: int = 300
## Whether the mob leashes home past max_distance_from_spawn. False = it COMMITS
## and fights to the death — bosses (a world boss in the open field, or a dungeon
## boss) and trash in bounded dungeon rooms.
@export var leashes: bool = true

## Aggro radius. The mob "sees" any player inside this circle and engages
## (when chase_on_area is true) — or pack-mates that hear an ally's
## was_attacked signal use it to decide if they're close enough to help.
## Should be SMALLER than max_distance_from_spawn so the mob can reach
## anything it sees before the leash kicks in. ~150 default.
@export var detection_radius: int = 150
@export var chase_on_area: bool = false
## When true, this archetype never joins pack assist — hitting one does not
## pull nearby allies via was_attacked, and it won't help neighbors either.
## Use for early trash (goblins) so you can fight one at a time.
@export var is_lone: bool = false
## Idle stroll radius around spawn (px). 0 = stand still while idle.
## Kept well under max_distance_from_spawn so wander never fights the leash.
@export var wander_radius: float = 0.0
## Pause between idle wander legs (seconds).
@export var wander_pause_min_s: float = 1.5
@export var wander_pause_max_s: float = 4.0

@export_group("Rewards")
@export var xp_reward: int = 25
## Seconds before respawn after death.
@export var respawn_delay: float = 5.0
## Whether the mob respawns at all. False = SINGLE-LIFE — the body is removed
## instead of returning (dungeon mobs, one-off event bosses). A mob with no
## xp_reward AND no loot grants nothing on death (the natural "shadow" trash).
@export var respawns: bool = true
@export var loot: Array[LootDrop]


@export_group("Boss")
## Phase 2: enrage when HP drops to this fraction of max (speeds the body up,
## summons adds, slams faster). Only read for an is_boss type that a dungeon
## RoomNode has given a BossController.
@export var enrage_health_fraction: float = 0.5
## Telegraphed slam: danger-ring radius (px), the wind-up players get to step out
## of it, and the damage dealt to anyone still inside when it lands.
@export var slam_radius: float = 110.0
@export var slam_windup_s: float = 1.1
@export var slam_damage: float = 45.0
## Seconds between slams — phase 1, then the faster enraged cadence.
@export var slam_interval_s: float = 6.0
@export var enraged_slam_interval_s: float = 3.5
## On enrage: summon this many of this enemy slug, spread around the boss.
@export var add_enemy_slug: StringName = &"rat_base"
@export var add_count: int = 2
@export var add_spread_px: float = 48.0
## Move-speed multiplier applied to the body on enrage (it chases harder).
@export var enrage_speed_mult: float = 1.3
## Telegraphed laser corridor (px reach / half-width). 0 range = disabled —
## used by Mecha-stone Golem to force lateral dodges between slams.
@export var laser_range: float = 0.0
@export var laser_width: float = 28.0
@export var laser_windup_s: float = 1.15
@export var laser_damage: float = 55.0
@export var laser_interval_s: float = 8.0
@export var enraged_laser_interval_s: float = 5.0
## Arm-cannon projectile. 0 interval = disabled.
@export var arm_shot_interval_s: float = 0.0
@export var arm_shot_damage: float = 40.0
@export var arm_shot_speed: float = 220.0
@export var arm_shot_lifetime_s: float = 1.4
@export var enraged_arm_shot_interval_s: float = 0.0
## DPS-ranked ornate chest grants (bag LootChestItems: blue/red/pink). When
## ornate_chest_top_max > 0, RewardService sorts contributors by damage and
## awards: top → [top_min, top_max], 2nd → [second_min, second_max], everyone
## else → 1 chest at consolation_chance (e.g. 0.25). Each chest is rolled
## independently among the three ornate tiers. 0 top_max = disabled.
@export var ornate_chest_top_min: int = 0
@export var ornate_chest_top_max: int = 0
@export var ornate_chest_second_min: int = 0
@export var ornate_chest_second_max: int = 0
@export_range(0.0, 1.0, 0.01) var ornate_chest_consolation_chance: float = 0.0


## Combat level for the nameplate. Authored value wins; otherwise derive a
## readable band from HP / damage / armor so every hostile shows something.
func resolved_combat_level() -> int:
	if combat_level > 0:
		return combat_level
	var derived: int = int(round((max_health / 12.0) + (attack_damage * 1.4) + (armor * 0.8)))
	return clampi(derived, 1, 99)
