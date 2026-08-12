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
## Lifetime "adventure XP" only. This does NOT level anyone: it is banked by
## PlayerResource.add_experience, which increments the `experience` counter and
## returns levels_gained 0 unconditionally. The counter survives for the save
## column and the progression UI.
##
## Character/combat level is DERIVED from the five weapon masteries
## (PlayerResource.derived_combat_level: (highest + mean) × 7 / 11, capped at 126),
## which ride the OSRS SkillXp 1–99 curve at 13,034,431 XP per mastery. The number
## that actually progresses a character is therefore [method combat_skill_xp], not
## this one. Do not "unify" the two: one serves a cosmetic counter, the other a
## curve three orders of magnitude bigger.
##
## (An earlier version of this comment described a live 1–20 character curve worth
## ~13,300 XP. That system was retired when level became mastery-derived; the note
## outlived it and is corrected here.)
@export var xp_reward: int = 25
## Seconds before respawn after death.
@export var respawn_delay: float = 5.0
## Whether the mob respawns at all. False = SINGLE-LIFE — the body is removed
## instead of returning (dungeon mobs, one-off event bosses). A mob with no
## xp_reward AND no loot grants nothing on death (the natural "shadow" trash).
@export var respawns: bool = true
@export var loot: Array[LootDrop]
## AUTHORED weapon-mastery / Slayer XP for a kill. 0 (the default) keeps the
## stat-derived number, which is what every ordinary mob should use — see
## [method combat_skill_xp_for] for why that rule exists.
##
## Set it only where the derived value stops being meaningful. A raid boss is the
## case: skill XP scales with effective HP, so giving one a big health bar
## silently multiplies its payout (Ossuran at 10,000 HP derives 116,000 XP, nine
## times Cinderborn, purely from being tanky). An override decouples "how long
## this takes to kill" from "what it is worth", without touching the curve for
## anything else.
##
## Note this also opts the mob out of difficulty scaling: dungeon Hard mode
## inflates max_health, which raises DERIVED xp but cannot raise an authored one.
@export var combat_skill_xp_override: int = 0


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
## DPS-ranked ornate chest grants. When ornate_chest_top_max > 0, RewardService
## awards [member ornate_chest_item] by damage rank among eligible contributors:
## top DPS gets [top_min, top_max], optional #2 gets [second_min, second_max],
## everyone else rolls [member ornate_chest_consolation_chance] for 1 chest.
## Empty [member ornate_chest_item] defaults to T3 Ornate Gold / pink (249).
@export var ornate_chest_top_min: int = 0
@export var ornate_chest_top_max: int = 0
@export var ornate_chest_second_min: int = 0
@export var ornate_chest_second_max: int = 0
@export_range(0.0, 1.0, 0.01) var ornate_chest_consolation_chance: float = 0.0
## Bag chest item for ranked grants (e.g. Ornate Red / Blue / Gold). Empty = pink (249).
@export var ornate_chest_item: Item


@export_group("Boss Spells")
## SpriteFrames swapped onto the body when it enrages — a visible phase form,
## not just a speed buff. Empty = keep the opening skin. The swap keeps every
## clip NAME, so the locomotion AnimationTree is untouched; only the art changes.
## Restored automatically on respawn.
@export_file("*.tres") var phase2_skin: String = ""

## Skin clip played while the boss winds up a cast (slam / laser / sweeping beam).
## Defaults to "special", which is what every boss used before this was a choice.
## Set it per boss when "special" is a specific piece of art rather than a generic
## cast pose — Cleetus's special IS his freeze-over, so playing it under a FIRE
## spell had him icing up to throw a fireball. Killing Frost and the enrage
## transform always use "special": for those the freeze is the point.
@export var cast_anim: StringName = &"special"

## Tint every telegraph this boss draws: 0 = fire, 1 = frost, 2 = storm. It is
## the boss's colour signature, not a damage type — players learn "orange ring =
## the big one" long before they learn its name.
@export_range(0, 2) var telegraph_element: int = 0
## Element after enrage. -1 = keep [member telegraph_element]. Setting this is
## how a fight visibly changes hands at phase two.
@export var enraged_telegraph_element: int = -1

## Every spell below is OFF by default (its "count"/"radius"/"arc" gate at 0), so
## existing bosses keep the exact slam/laser/arm kit they had. A phase field of
## 0 = usable in both phases, 1 = phase one only, 2 = only after enrage — that is
## what lets one boss open with fire and finish with ice.

## EMBER RAIN — a volley of meteors on telegraphed ground, staggered so players
## have to keep relocating instead of dodging once. 0 = off.
@export var meteor_count: int = 0
@export var meteor_radius: float = 56.0
@export var meteor_damage: float = 60.0
## Telegraph lead on each meteor (the comet falls during the last of it).
@export var meteor_windup_s: float = 1.5
## Gap between successive meteors in one volley.
@export var meteor_stagger_s: float = 0.45
## How far from the boss meteors can land.
@export var meteor_spread_px: float = 190.0
@export var meteor_interval_s: float = 11.0
@export var enraged_meteor_interval_s: float = 0.0
@export_range(0, 2) var meteor_phase: int = 0

## CINDER LASH — a beam that SWEEPS through an arc. Unlike the fixed laser
## corridor, standing still or sidestepping both fail; you have to move around
## the boss or get behind the sweep. 0 arc = off.
@export var sweep_arc_deg: float = 0.0
@export var sweep_range: float = 300.0
@export var sweep_width: float = 34.0
@export var sweep_windup_s: float = 1.2
## How long the beam takes to travel its arc (also the damage window).
@export var sweep_duration_s: float = 1.1
@export var sweep_damage: float = 70.0
@export var sweep_interval_s: float = 12.0
@export var enraged_sweep_interval_s: float = 0.0
@export_range(0, 2) var sweep_phase: int = 0

## KILLING FROST — the arena freezes EXCEPT one marked circle. The telegraph is
## inverted: players must run INTO the marker, not out of it. 0 radius = off.
@export var frost_safe_radius: float = 0.0
@export var frost_windup_s: float = 2.6
## Damage to everyone caught OUTSIDE the safe circle. Meant to hurt.
@export var frost_damage: float = 110.0
## How far from the boss the safe circle is placed — far enough to be a run.
@export var frost_offset_px: float = 150.0
@export var frost_interval_s: float = 16.0
@export var enraged_frost_interval_s: float = 0.0
@export_range(0, 2) var frost_phase: int = 0

## STATIC ARC — lightning that jumps from the boss to a target and then to
## whoever is standing near them. The anti-stacking move: spread out or the
## chain runs the whole raid. 0 targets = off.
@export var chain_targets: int = 0
## Jump distance for each subsequent link.
@export var chain_range: float = 170.0
@export var chain_damage: float = 45.0
@export var chain_windup_s: float = 0.9
@export var chain_interval_s: float = 9.0
@export var enraged_chain_interval_s: float = 0.0
@export_range(0, 2) var chain_phase: int = 0


# ---------------------------------------------------------------------------
# Skill XP from a kill (weapon mastery + Slayer) — NOT character xp_reward.
# ---------------------------------------------------------------------------

## XP per point of effective HP, for the SkillXp 1–99 curve. 4.0 is OSRS's real
## combat rate (XP scales with damage dealt), which lands mastery 1–99 at roughly
## 12k–33k kills and Slayer at ~3× that — in line with this game's gathering
## skills, already near OSRS parity on the same curve (adamant ore 58 XP ≈ 224k
## actions to 99). This is THE pacing dial for all combat skilling: halve it to
## double the grind, and Slayer follows automatically.
const COMBAT_SKILL_XP_PER_HP: float = 4.0

## Armor's assumed contribution to how long a kill takes. Armor [param armor]
## behaves like (1 + armor/ARMOR_EHP_DIVISOR)× the health bar, so a tankier mob
## pays proportionally more. Keeping XP tied to time-to-kill is what makes XP/hour
## roughly flat across the roster — no monster is a trap, and no monster is a
## strictly-better farm than the one the level ladder points you at.
const ARMOR_EHP_DIVISOR: float = 20.0


## Weapon-mastery / Slayer XP for killing this archetype: effective HP × the OSRS
## rate. Deliberately derived from the stat block rather than read off xp_reward —
## see the note on [member xp_reward] for why the two cannot be the same number.
## Static so callers holding a live [HostileNpc] (which copies these stats out of
## the resource) can use the identical rule without re-loading the resource.
static func combat_skill_xp_for(enemy_max_health: float, enemy_armor: float) -> int:
	var effective_hp: float = maxf(1.0, enemy_max_health) * (1.0 + maxf(0.0, enemy_armor) / ARMOR_EHP_DIVISOR)
	return maxi(1, roundi(effective_hp * COMBAT_SKILL_XP_PER_HP))


## [method combat_skill_xp_for] for this resource's own stat block, unless
## [member combat_skill_xp_override] authors a value instead.
func combat_skill_xp() -> int:
	if combat_skill_xp_override > 0:
		return combat_skill_xp_override
	return combat_skill_xp_for(max_health, armor)


## Combat level for the nameplate. Authored value wins; otherwise derive a
## readable band from HP / damage / armor so every hostile shows something.
func resolved_combat_level() -> int:
	if combat_level > 0:
		return combat_level
	var derived: int = int(round((max_health / 12.0) + (attack_damage * 1.4) + (armor * 0.8)))
	return clampi(derived, 1, 99)
