@tool
class_name HostileNpc
extends Character


enum EnemyState {
	RETURNING,
	IDLE,
	CHASE,
	ATTACK,
	DEAD,
	# Appended (don't reorder — the int value is state-synced to clients):
	LUNGE_WINDUP, ## planted, telegraphing the pounce zone
	LUNGING,      ## dashing to the locked spot
	REVIVING,     ## down but not out — body on the ground, second wind incoming
}

## Flip to true to dump every meaningful NPC state transition. Server lines
## use [SRV NPC <type>] tags, client lines use [CLI NPC <type>] — grep one
## or the other in journalctl / the editor console depending on which side
## you're investigating. Leave off in normal play; the printerr volume
## scales with NPC count. (Was used to nail the chase_on_area zombie bug —
## kept wired so the next mystery is one constant flip away.)
const DEBUG_NPC: bool = false

## How fast a RETURNING NPC moves vs its normal speed. Leashed mobs need
## to outrun any reasonable kiting pace, otherwise a ranged player can
## drag them home in slow motion while still in their max chase range.
const RETURN_SPEED_MULTIPLIER: float = 1.4

## % of max HP regenerated per second while RETURNING. At 0.25 a mob at
## near-zero HP fully heals over ~4s of walking. Reads visibly on the bar
## without being instant.
const RETURN_REGEN_RATE: float = 0.25
## Monsters only regenerate after this long with no chase/attack/damage activity.
## THE one gate on every heal a hostile gets: no mob and no boss recovers a single
## point while a fight is live (or was live within the window) — stepping out of a
## mechanic, kiting past the leash, or dying to a boss no longer refills it. A
## scripted encounter can switch the heal off outright with
## [member regenerates_out_of_combat], for the phases this window still misreads.
const OUT_OF_COMBAT_REGEN_DELAY_MS: int = 10000

# Regen is a RESET, not a passive trickle: the ONLY place a hostile heals is the
# walk home (RETURNING) plus the top-off on arrival, and only once the out-of-
# combat window above has fully elapsed. An idling mob below full HP therefore
# routes itself back through RETURNING — see _process_idle_recovery — which also
# covers the sniped-from-outside-detection case the old idle trickle used to patch.

## A RETURNING mob is deliberately deaf (no aggro, no re-target) until it's home,
## so it must never be able to walk forever. The return march steers directly with
## no pathfinding — a mob that chased around a corner CAN end up shouldering a wall
## — and a permanently-returning mob in a dungeon room is an uncompletable run.
## Past this, it finishes the reset wherever it's standing and goes back on duty.
const RETURN_TIMEOUT_MS: int = 8000

## A mob holds still (AI suspended via action_root_until_ms) for this long on spawn / respawn so the
## summon burst reads on a still body instead of a mob blinking in mid-stride.
const SPAWN_FREEZE_S: float = 0.5



## Toggle in the inspector to render the leash + detection rings around
## this NPC. The script is @tool so the circles appear in-editor as soon
## as you flick this on — no need to run the scene. The setter calls
## queue_redraw so it updates the moment you tick the box.
@export var debug_draw_ranges: bool = false:
	set(value):
		debug_draw_ranges = value
		queue_redraw()

## Emitted server-side whenever this NPC takes damage from a real attacker.
## Other HostileNpcs inside this one's detection_area subscribe via
## body_entered, so a pack reacts as a unit when one of them gets hit.
## Decoupled via signal so we never need a direct "list of allies" array
## that has to be maintained / cleaned up.
signal was_attacked(attacker: Character)

## Data-driven definition. REQUIRED: every HostileNpc instance must point at an
## EnemyTypeResource. All combat/AI fields below are populated from it at
## _ready, so per-instance inspector tweaks are deliberately not supported —
## edit the .tres if you want to change behaviour, and every spawn of that
## archetype picks up the change. Per-instance overrides invite the exact
## "enemy_type says 'mobs' but the kill registers as 'bandit'" confusion we
## just cleaned up.
@export var enemy_data: EnemyTypeResource

## ContentRegistry `enemy_types` slug of this NPC's archetype. Setting it resolves
## [member enemy_data] from the registry — lets a dynamically-spawned NPC (e.g. a
## guild guard) carry its archetype over the wire as a short slug instead of a
## resource path. Applied BEFORE add_child on both sides so _ready sees
## enemy_data. Authored mobs set enemy_data directly and leave this empty.
var enemy_type_slug: StringName = &"":
	set(value):
		enemy_type_slug = value
		if value != &"":
			var data: EnemyTypeResource = ContentRegistryHub.load_by_slug(&"enemy_types", value) as EnemyTypeResource
			if data != null:
				enemy_data = data

## Owning guild / faction (0 = none). When > 0 this NPC is a guild defender: it
## ignores players tagged into that guild and is single-life (despawns on death,
## no respawn). Set on spawn by the flag (server-only — clients just render).
var owner_guild_id: int = 0

## Server-only aggro trigger. Built programmatically in _ready (server)
## from max_distance_from_spawn × DETECTION_RADIUS_FACTOR — no scene
## wiring, no client-side cost. The radius is the only meaningful tuning
## knob here; if you ever want a non-circular detection (cone, vision),
## swap the CollisionShape2D's shape after construction.
var detection_area: Area2D

# --- Driven by enemy_data (do NOT @export, see class docstring above) ---
# Their defaults below act only as fallbacks if enemy_data is somehow missing
# (we assert against that in _apply_enemy_data), so authoring lives entirely
# in the .tres files under characters/npc/types/.

## Identifier used by quest KILL objectives (e.g. &"slime"). Enemies sharing a
## type count toward the same objective.
var enemy_type: StringName
var max_health: float = 50.0
var attack_damage: float = 8.0
## Seconds between auto-attacks while in range.
var attack_cooldown: float = 1.5
var armor: float = 0.0
var mr: float = 0.0
## Optional weapon. If set, the enemy equips it and fires its ability at the
## target (reusing the same projectiles players use). If null, the enemy is a
## melee AoE attacker. Exported as a PER-NODE OVERRIDE: leave empty to use the
## EnemyTypeResource's weapon; set it on a placed node to arm just that one
## (an archer in a melee camp) without touching the shared .tres.
@export var weapon: WeaponItem
var xp_reward: int = 25
## False strips this body's MATERIAL payout — weapon-mastery XP, and with
## xp_reward/loot already zeroed alongside it, everything a kill hands over.
## Dungeon trash and boss-summoned adds set it (see RoomNode.make_dungeon_mob):
## the payoff there is clearing the room, not farming a boss's summons.
##
## PROGRESSION credit is deliberately NOT covered by this flag. A goblin is a
## goblin however it got here, so quest / daily / Slayer counters still tick —
## Slayer just pays its task's authored fallback rate instead of the derived one
## (SlayerTaskService._xp_per_kill), which is the reward suppression this flag is
## for, applied to the one number that would otherwise leak through.
var grants_skill_xp: bool = true
## player_id -> total damage dealt this life (cleared on respawn). Persistent id
## so a reconnect still shares the kill. Drives RewardService.
var _contributors: Dictionary[int, float] = {}
## Whether this mob respawns after death (driven by enemy_data.respawns). False =
## single-life: the body is removed, no return (dungeon mobs, one-off bosses).
var respawns: bool = true
## False switches off BOTH out-of-combat heals — the walk home and the top-off on
## arrival — for this body only, leaving its bar wherever the fight left it.
##
## For SCRIPTED encounters, where the fight is not "is anyone hitting me". The
## out-of-combat window is a good rule for an open-world mob: stop fighting a
## boar for ten seconds and you have disengaged. Inside a staged fight it reads
## the room wrong — a phase can legitimately send the whole group away from the
## boss (Ossuran's frozen phase sends them to a brazier, and his own cast root
## means he does not follow), and ten seconds of that is not a disengage, it is
## the mechanic working. Refilling the bar there erases twenty minutes of a
## group's run for playing the phase correctly.
##
## Safe to leave off for the whole run because a staged encounter owns the body's
## lifetime: it despawns and respawns the boss on reset (see OssuranArena.stop),
## so nothing is left standing at 4% for the next group — which is the case the
## out-of-combat reset exists for.
var regenerates_out_of_combat: bool = true

## Emitted on death, server-side. The CONTEXT that spawned the mob wires the
## consequence — a dungeon connects its boss's `died` → clear; a world-boss event
## connects it → its own handler. Keeps death-consequences OUT of the mob class.
signal died(killer: Character)

## Leash radius used to mean "infinite" — set when enemy_data.leashes is false so
## the mob commits and fights to the death instead of walking home.
const NO_LEASH_DISTANCE: int = 1_000_000
## Seconds before a killed enemy respawns at its spawn point.
var respawn_delay: float = 5.0
var loot: Array[LootDrop]
var move_speed: int = 20
## Outgoing damage multiplier (soft enrage). 1.0 = authored. Applied in Character.take_damage.
var damage_dealt_mult: float = 1.0
## Distance to the player at which the NPC switches from CHASE to ATTACK.
var distance_to_attack: int = 20
## If the NPC strays this far from its spawn, it disengages and returns.
var max_distance_from_spawn: int = 300
## Aggro radius — how far the mob "sees". Must be smaller than the leash
## so the mob can reach anything it spots before the leash trips. Driven
## by enemy_data.detection_radius.
var detection_radius: int = 150
## Start chasing as soon as a player steps inside detection_area.
var chase_on_area: bool = false
## Idle stroll around spawn. Copied from enemy_data; 0 disables wander.
var wander_radius: float = 0.0
## Last time this mob was in active combat (chase/attack/damaged/dealt damage).
## Regen (idle + return) waits OUT_OF_COMBAT_REGEN_DELAY_MS after this.
var _last_combat_activity_ms: int = 0
## When the current RETURNING march began — bounds it via RETURN_TIMEOUT_MS.
var _return_since_ms: int = 0
var wander_pause_min_s: float = 1.5
var wander_pause_max_s: float = 4.0
## Idle wander scratch — not synced; clients see position/anim only.
var _wander_target: Vector2 = Vector2.ZERO
var _has_wander_target: bool = false
var _wander_pause_until_ms: int = 0
## Soft stuck detector: if we keep colliding without closing on the target,
## abandon that leg and pick another point.
var _wander_stuck_frames: int = 0
## Opt out of pack assist (driven by enemy_data.is_lone). See EnemyTypeResource.
var is_lone: bool = false
## Composable server-side behaviors (docs/hostile_npc_refactor.md P1): built
## in _apply_enemy_data from enemy_data.behaviors + legacy-field synthesis.
## Behaviors are SHARED resources — their per-mob runtime scratch lives in
## [member behavior_state].
var behaviors: Array[MobBehavior] = []
## What this mob does on its swing timer (refactor P2). Built in
## _apply_enemy_data from enemy_data.attacks, or synthesized (weapon →
## WeaponAttack, else MeleeAttack) when none are authored. Shared resources,
## like behaviors — per-mob scratch lives in [member behavior_state].
var attacks: Array[MobAttack] = []
## Per-mob runtime scratch for shared behavior/attack resources (resource -> Dictionary).
var behavior_state: Dictionary = {}
## The behavior currently driving the state machine (set by a successful
## try_start; the behavior hands control back by setting a chassis state).
var _state_owner: MobBehavior


## Copy archetype fields onto this instance. Called once at _ready so the rest
## of HostileNpc can keep reading its local fields unchanged.
func _apply_enemy_data() -> void:
	assert(enemy_data != null, "HostileNpc requires an enemy_data resource — see characters/npc/types/.")
	enemy_type = enemy_data.enemy_type
	var base_name: String = enemy_data.display_name
	var lvl: int = enemy_data.resolved_combat_level()
	display_name = "%s (Lv %d)" % [base_name, lvl] if not base_name.is_empty() else "Enemy (Lv %d)" % lvl
	max_health = enemy_data.max_health
	attack_damage = enemy_data.attack_damage
	attack_cooldown = enemy_data.attack_cooldown
	armor = enemy_data.armor
	mr = enemy_data.mr
	if weapon == null: # node-level override wins; resource is the default
		weapon = enemy_data.weapon
	xp_reward = enemy_data.xp_reward
	respawn_delay = enemy_data.respawn_delay
	loot = enemy_data.loot
	move_speed = enemy_data.move_speed
	damage_dealt_mult = 1.0
	distance_to_attack = enemy_data.distance_to_attack
	max_distance_from_spawn = enemy_data.max_distance_from_spawn
	respawns = enemy_data.respawns
	# Boss bodies are discoverable by group, so the HUD boss bar can find the
	# encounter's boss WITHOUT it being the player's combat target (a scripted
	# fight has whole stages where nobody is hitting it). Runs on both peers —
	# the bar that needs this is client-side.
	if enemy_data.is_boss:
		add_to_group(&"boss_bodies")
	# A non-leashing mob (bosses; trash in bounded dungeon rooms) commits — an
	# effectively-infinite leash so the distance check never walks it home.
	if not enemy_data.leashes:
		max_distance_from_spawn = NO_LEASH_DISTANCE
	detection_radius = enemy_data.detection_radius
	chase_on_area = enemy_data.chase_on_area
	is_lone = enemy_data.is_lone
	wander_radius = enemy_data.wander_radius
	wander_pause_min_s = enemy_data.wander_pause_min_s
	wander_pause_max_s = enemy_data.wander_pause_max_s
	# Composable behaviors (docs/hostile_npc_refactor.md). The legacy flat
	# lunge fields are gone — every archetype authors behaviors directly.
	behaviors = []
	for behavior: MobBehavior in enemy_data.behaviors:
		if behavior != null:
			behaviors.append(behavior)
	# Swing-timer attacks (refactor P2). No authored attacks = the classic
	# default: the mounted weapon's ability if armed, else the melee AoE.
	# (weapon already resolved above, node-level override included.)
	attacks = []
	for attack: MobAttack in enemy_data.attacks:
		if attack != null:
			attacks.append(attack)
	if attacks.is_empty():
		if weapon != null:
			attacks.append(WeaponAttack.new())
		else:
			attacks.append(MeleeAttack.new())
	if enemy_data.skin != null:
		skin_id = 0 # disable id-based skin; we're driving it directly
		# animated_sprite (from Character) is @onready — already assigned by the
		# time _ready (and therefore this) runs.
		animated_sprite.sprite_frames = enemy_data.skin
	# Visual size (a boss reads bigger) — SPRITE only for the CharacterBody2D
	# nav capsule (a scaled node can't close to melee range). HurtBox + click
	# area DO grow with the sprite so player swings/projectiles can connect.
	if enemy_data.visual_scale != 1.0:
		animated_sprite.scale *= enemy_data.visual_scale
	# Bar + nameplate placement keys off the DRAWN size, not visual_scale — a
	# big-framed skin at 1.0x is still a big sprite, and gating this on
	# visual_scale alone left its bar buried in the art. Identical for every
	# 64px skin (see body_scale).
	var drawn: float = body_scale()
	if drawn != 1.0:
		# A big sprite swallows the head-bar — lift it clear of the enlarged sprite
		# and scale it up so a boss reads as a boss. Scale around the bar's own
		# centre so it stays horizontally centred over the mob.
		var lift: float = 55.0 * (drawn - 1.0)
		progress_bar.offset_top -= lift
		progress_bar.offset_bottom -= lift
		progress_bar.pivot_offset = Vector2(
			(progress_bar.offset_right - progress_bar.offset_left) * 0.5,
			(progress_bar.offset_bottom - progress_bar.offset_top) * 0.5
		)
		progress_bar.scale = Vector2.ONE * drawn
		# Keep the nameplate stacked above the lifted bar (DisplayNameLabel parks
		# near y=0 by default — under a tall boss sprite it disappears into the art).
		if display_name_label != null:
			display_name_label.position.y -= lift
	_scale_hurtbox_to_sprite()
	_scale_body_to_sprite()
	# Bosses keep a permanent over-head HP bar with remaining points — players need
	# the read for a long fight. Regular trash still auto-hides on idle. Widen the
	# bar so 4-digit remaining HP (e.g. 7500) isn't clipped by the 32px default.
	if enemy_data.is_boss:
		health_bar_auto_hide = false
		if progress_bar != null:
			progress_bar.offset_left = -28.0
			progress_bar.offset_right = 28.0
			if hp_label != null:
				hp_label.add_theme_font_size_override(&"font_size", 9)

var container: ReplicatedPropsContainer
var enemy_state: EnemyState = EnemyState.IDLE:
	set(value):
		# Stamp each fresh RETURNING so _process_return can bound the march (see
		# RETURN_TIMEOUT_MS). Cheap and side-effect-free on clients.
		if value == EnemyState.RETURNING and enemy_state != EnemyState.RETURNING:
			_return_since_ms = Time.get_ticks_msec()
		enemy_state = value
		# Client: a mob that dies mid-windup must not ghost-play its scheduled
		# dash — abort the smoother's scripted motion the moment DEAD (or its
		# intercepted cousin REVIVING) syncs in.
		if (value == EnemyState.DEAD or value == EnemyState.REVIVING) \
				and _net_smoother != null and not multiplayer.is_server():
			_net_smoother.cancel_motion()
		if (value == EnemyState.DEAD or value == EnemyState.REVIVING) \
				and not multiplayer.is_server():
			_set_hostile_hover(false)

var possible_targets: Array[Player]
var targeted_player: Player
## TAUNT (Heavy Weapons' Mighty Roar): while this is live, our aggro belongs to
## [member taunt_source] and nothing may re-target or drop it — see
## [method is_taunted]. This is the whole point of a tank: without a hard lock,
## a boss re-picks by proximity/damage the moment anyone out-threats the tank,
## which is exactly what the roar exists to stop.
var taunt_source: Player
## Wall-clock ms the taunt expires at, or [constant TAUNT_UNTIL_DEATH] for a
## capstone roar that holds until one of us dies.
var taunt_until_ms: int = 0
var spawn_position: Vector2
## Cache for [method body_scale] — measuring it decodes an image, so it is done
## once per body and never on the hot path.
var _body_scale: float = -1.0

var _prop_id: int
var _position_fid: int
var _anim_fid: int
var _flipped_fid: int
var _state_fid: int
var _health_fid: int
var _health_max_fid: int
## When (Time.get_ticks_msec) a dead enemy should respawn.
var _respawn_at_ms: int
## When the next auto-attack is allowed.
var _next_attack_ms: int
## Client: true while a one-shot attack/special SpriteFrames clip is playing so
## incoming :anim locomotion travels don't stomp the action mid-swing.
var _skin_action_playing: bool = false
## Bumps each rp_play_skin_anim so a stale watchdog timer can't clear a newer clip.
var _skin_action_token: int = 0
## The skin's authored playback rate, captured before a stretched clip changes it
## so it can always be put back. -1 = not captured yet.
var _skin_base_speed: float = -1.0
## Client: the skin this body spawned with, kept so a phase-2 swap can be undone
## on respawn. A boss that died frozen must come back in its opening form.
var _skin_base_frames: SpriteFrames = null
## Client: cursor is over this mob's click-box (blocks click-to-move, not combat).
var _hostile_hovered: bool = false


func _ready() -> void:
	# Editor mode (we're @tool for the debug-draw export): skip everything
	# runtime, just nudge a redraw so the inspector toggle takes effect.
	if Engine.is_editor_hint():
		queue_redraw()
		return
	# Pull archetype values from enemy_data BEFORE Character._ready reads any
	# stats — so a data-driven NPC's @exports already reflect the resource.
	_apply_enemy_data()
	# Client dynamics spawn with Stats defaulting every key to 0. Until the first
	# health sync pair arrives, CombatTargetController treats HEALTH<=0 as dead —
	# which made boss enrage adds (and any fresh dynamic) look untargetable even
	# though the server body was fine. Seed from the archetype; the sync pair
	# overwrites with the live (difficulty-scaled) values a tick later.
	if not multiplayer.is_server() and enemy_data != null:
		stats_component.set_stat(Stat.HEALTH_MAX, enemy_data.max_health)
		stats_component.set_stat(Stat.HEALTH, enemy_data.max_health)
	# Character._ready wires the client-side health bar (stat_changed -> ProgressBar);
	# without this the NPC's bar is never initialised or connected. On the server it
	# returns immediately.
	super._ready()
	# Equip the weapon on both server (to fire/deal damage) and client (visual + to
	# replay the shot). Done before the stat init below so the explicit NPC stats win.
	_equip_weapon()
	assert(get_parent() is ReplicatedPropsContainer, "HostileNPC must be a child of ReplicatedPropContainer.")
	if not multiplayer.is_server():
		# Client-side diagnostic: log every HEALTH / HEALTH_MAX value that
		# comes off the synchronizer wire, so we can see whether the bar
		# being empty reflects what the server actually sent. Server-side
		# transitions live in their own [SRV NPC ...] prints.
		if DEBUG_NPC:
			stats_component.stats.stat_changed.connect(_debug_client_stat_changed)
		_apply_ally_bar_tint()
		refresh_nameplate_color()
		# Drive SpriteFrames via the shared AnimationTree (idle/run/death method
		# tracks). Friendly NPCs already flip this on; hostiles previously left
		# the tree inactive / never kicked the first travel, so skins sat on
		# frame 0 with no playback — most obvious on large bosses like the golem.
		if animation_tree != null:
			animation_tree.active = true
		if animated_sprite != null and animated_sprite.sprite_frames != null \
				and animated_sprite.sprite_frames.has_animation(&"idle"):
			animated_sprite.play(&"idle")
		if locomotion_state_machine != null:
			locomotion_state_machine.travel(&"locomotion_idle")
		# Boss HP bar stays up from spawn (health_bar_auto_hide cleared in
		# _apply_enemy_data) — Character._ready may have hidden it already.
		if enemy_data != null and enemy_data.is_boss and progress_bar != null:
			progress_bar.show()
			progress_bar.modulate.a = 1.0
		# Re-evaluate if the local player's guild changes (so a guard that spawned
		# before you tagged in updates without a relog).
		if is_instance_valid(ClientState):
			ClientState.active_guild_id_changed.connect(_on_local_guild_changed)
		# Mobs stream at 10 Hz (props channel), half the player broadcast rate — the
		# interpolation delay needs 2 samples in flight, so double the default.
		net_smooth_delay_ms = 200
		_build_client_click_area()
		set_physics_process(false)
		return
	
	# Build the detection trigger here so the scene is lean (no Area2D node
	# shipped to clients for nothing) and the radius can be derived from
	# the leash distance — single source of truth, can't drift.
	_build_detection_area()
	detection_area.body_entered.connect(_on_body_entered)
	detection_area.body_exited.connect(_on_body_exited)

	spawn_position = global_position
	container = get_parent()

	_prop_id = container.child_id_of_node(self)
	if _prop_id < 0:
		container._bake_static_map()
		_prop_id = container.child_id_of_node(self)
	if _prop_id < 0:
		push_error(
			"HostileNPC '%s' has no ReplicatedProps child id under %s — motion/anims will not sync."
			% [name, str(container.get_path())]
		)
	_position_fid = PathRegistry.ensure_id(^":position")
	_anim_fid = PathRegistry.ensure_id(^":anim")
	_flipped_fid = PathRegistry.ensure_id(^":flipped")
	_state_fid = PathRegistry.ensure_id(":enemy_state")
	_health_fid = PathRegistry.ensure_id("StatsComponent:stats:health")
	_health_max_fid = PathRegistry.ensure_id("StatsComponent:stats:health_max")

	# Zone difficulty: InstanceResource.enemy_health_mult scales every hostile in
	# the instance. Applied to max_health itself (not just the stat) so the derived
	# combat_skill_xp follows the real HP — a softened zone pays out in proportion
	# instead of turning into the cheapest XP in the game.
	max_health *= _zone_health_mult()

	# Server-authoritative combat stats.
	stats_component.set_stat(Stat.HEALTH_MAX, max_health)
	stats_component.set_stat(Stat.HEALTH, max_health)
	stats_component.set_stat(Stat.AD, attack_damage)
	# AP mirrors AD so a magic weapon (wand bolt scales off AP) hits with the
	# same tuned attack_damage as any other armament — mob power is ONE number.
	stats_component.set_stat(Stat.AP, attack_damage)
	stats_component.set_stat(Stat.ARMOR, armor)
	stats_component.set_stat(Stat.MR, mr)

	# Push the full initial state (position especially) in the SPAWN tick, so a freshly-spawned mob
	# is placed correctly on clients immediately instead of sitting at the container origin until
	# its first physics frame. Without this, a spawn VFX fired right after spawn lands at (0,0).
	_process_synchronization()
	# Deferred so dungeon/world-boss spawners can attach first; map-placed bosses
	# still get a brain if none was provided.
	call_deferred(&"_ensure_boss_brain")


## [member InstanceResource.enemy_health_mult] for the instance we spawned in, or
## 1.0 outside one. Walks HostileNpc → ReplicatedPropsContainer → Map →
## ServerInstance and duck-types the last hop: common/ code must not reference
## server-only types (same reason Character._broadcast_hit_feedback walks by hand).
##
## Bosses are exempt: a zone knob is for pacing its trash, and a finale is tuned as
## its own fight (the Bandit Captain's 4k HP is the encounter, not the zone).
func _zone_health_mult() -> float:
	if enemy_data != null and enemy_data.is_boss:
		return 1.0
	var maybe_map: Node = container.get_parent() if container != null else null
	var maybe_instance: Node = maybe_map.get_parent() if maybe_map != null else null
	if maybe_instance == null:
		return 1.0
	var ires: InstanceResource = maybe_instance.get(&"instance_resource") as InstanceResource
	if ires == null or ires.enemy_health_mult <= 0.0:
		return 1.0
	return ires.enemy_health_mult


func _ensure_boss_brain() -> void:
	if not multiplayer.is_server() or enemy_data == null or not enemy_data.is_boss:
		return
	# Identity check — spawners used to add an unnamed BossController (@Node@N),
	# which a name lookup would miss and then double-attach.
	for child: Node in get_children():
		if child is BossController:
			return
	var brain: BossController = BossController.new()
	brain.name = "BossController"
	brain.boss = self
	add_child(brain)


func _on_local_guild_changed(_new_id: int) -> void:
	_apply_ally_bar_tint()


## Client-only: a guild guard's HP bar reads blue to guildmates (ally) and red to
## everyone else; ally guards also stay visible. Regular mobs keep the default
## hostile color from Character._ready. Idempotent (re-runs on guild change).
func _apply_ally_bar_tint() -> void:
	if multiplayer.is_server() or owner_guild_id <= 0:
		return
	var is_ally: bool = is_instance_valid(ClientState) and ClientState.active_guild_id == owner_guild_id
	set_health_bar_fill(BAR_COLOR_ALLY if is_ally else BAR_COLOR_HOSTILE)
	if is_ally:
		health_bar_auto_hide = false # ally guards stay visible (not damage-gated)
		progress_bar.show()


## Hostiles stay white until Right-click → Attack paints them red.
func refresh_nameplate_color() -> void:
	if multiplayer.is_server() or display_name_label == null:
		return
	if get_instance_id() == Character.combat_target_instance_id:
		set_nameplate_color(NAME_COLOR_TARGET)
	else:
		set_nameplate_color(NAME_COLOR_PLAYER)


## Server-set: while this timestamp is in the future the body holds position — a
## BossController commits it to a telegraphed cast instead of strolling out of its
## own danger ring. Generic, like the lunge windup's root but driven from outside
## the state machine.
var action_root_until_ms: int = 0


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not multiplayer.is_server():
		return

	# Rooted for a telegraphed cast — or STUNNED (Pinning Arrow): hold position and do
	# nothing. DEAD still processes so death isn't deferred behind the wind-up.
	# Still sync: a boss cast can last >1s and players keep hitting it — skipping
	# sync froze the over-head HP bar for the whole wind-up. Force IDLE (not RUN)
	# so a rooted body reads planted instead of sprinting in place.
	if enemy_state != EnemyState.DEAD and (
			Time.get_ticks_msec() < action_root_until_ms or is_stunned()):
		_mark_combat_activity()
		velocity = Vector2.ZERO
		if anim != Character.Animations.IDLE:
			anim = Character.Animations.IDLE
		_process_synchronization()
		return

	match enemy_state:
		EnemyState.RETURNING:
			_process_return()
		EnemyState.IDLE:
			_process_idle()
		EnemyState.CHASE:
			_process_chase()
		EnemyState.ATTACK:
			_process_attack()
		EnemyState.DEAD:
			_process_death()
		EnemyState.LUNGE_WINDUP, EnemyState.LUNGING, EnemyState.REVIVING:
			# Behavior-owned states (docs/hostile_npc_refactor.md): whoever
			# took over (try_start, or an on_death intercept) drives them
			# until it hands control back.
			_mark_combat_activity()
			if _state_owner != null:
				_state_owner.process_state(self)
			else:
				enemy_state = EnemyState.CHASE # orphaned state — recover

	_find_targets()
	_process_animations()
	_process_synchronization()


func _on_body_entered(body: Node) -> void:
	# Ally-pack assist: when another HostileNpc enters detection range,
	# subscribe to their was_attacked signal so we aggro the attacker
	# alongside them. Lone archetypes (is_lone) neither call for help nor
	# answer — so early trash like goblins can be fought one at a time.
	if body is HostileNpc and body != self:
		if is_lone or (body as HostileNpc).is_lone:
			return
		if not (body as HostileNpc).was_attacked.is_connected(_on_ally_attacked):
			(body as HostileNpc).was_attacked.connect(_on_ally_attacked)
		return

	if body is not Player: return
	if not _is_hostile_to(body): return # Defenders ignore their own guild.

	if possible_targets.has(body):
		possible_targets.set(possible_targets.find(body, 0), body)
	else:
		possible_targets.append(body)

	# CRITICAL: don't yank a dead NPC out of DEAD state into CHASE. Without
	# this, a player walking back into the detection area during the respawn
	# timer flips enemy_state → CHASE, _process_death never runs, is_dead and
	# HEALTH=0 get stuck forever, and every subsequent take_damage early-
	# returns. That's the "zombie NPC" symptom (empty bar, no kill credit,
	# happens only for chase_on_area=true mobs). _find_targets already has
	# the same DEAD guard — this one was just missing.
	if DEBUG_NPC and enemy_state == EnemyState.DEAD and chase_on_area:
		printerr("[SRV NPC %s] body_entered while DEAD — guard prevented zombie" % enemy_type)
	if chase_on_area and not targeted_player and enemy_state != EnemyState.DEAD \
			and _is_target_valid(body as Player):
		targeted_player = body
		enemy_state = EnemyState.CHASE
		if DEBUG_NPC:
			printerr("[SRV NPC %s] body_entered → CHASE (target=%s)" % [enemy_type, body.name])


func _on_body_exited(body: Node) -> void:
	if body is HostileNpc and body != self:
		if (body as HostileNpc).was_attacked.is_connected(_on_ally_attacked):
			(body as HostileNpc).was_attacked.disconnect(_on_ally_attacked)
		return

	if body is not Player: return
	if body == targeted_player: return

	possible_targets.erase(body)


## A nearby ally got hit by [param attacker]. If we're free to engage,
## switch target to the attacker so a pack of mobs aggros together when
## one of them is poked. Skipped while RETURNING / DEAD so leash + respawn
## flows stay clean, and skipped if we already have a target so we don't
## thrash between attackers.
func _on_ally_attacked(attacker: Character) -> void:
	if is_dead:
		return
	if is_taunted():
		return
	if enemy_state == EnemyState.DEAD or enemy_state == EnemyState.RETURNING:
		return
	if targeted_player != null:
		return
	if attacker is Player and not (attacker as Player).is_dead and _is_hostile_to(attacker as Player):
		targeted_player = attacker as Player
		enemy_state = EnemyState.CHASE


## Sentinel [member taunt_until_ms] meaning "no timer — this taunt ends only when
## the mob dies or the taunter does".
const TAUNT_UNTIL_DEATH: int = -1
## Distance at which a taunt snaps regardless of its timer — see [method is_taunted].
## Comfortably past any arena, so it only ever fires on a teleport/respawn.
const TAUNT_BREAK_PX: float = 700.0


## Server: force this mob's aggro onto [param source] and HOLD it there for
## [param duration_s] seconds (0 = until either of us dies). Re-roaring refreshes.
## Sets chase_on_area so a passive/skiller-safe archetype answers a roar too — a
## taunt the boss's trash ignores is not a taunt.
func apply_taunt(source: Player, duration_s: float) -> void:
	if not multiplayer.is_server() or is_dead or source == null:
		return
	if enemy_state == EnemyState.DEAD or not _is_target_valid(source) or not _is_hostile_to(source):
		return
	taunt_source = source
	taunt_until_ms = (
		TAUNT_UNTIL_DEATH if duration_s <= 0.0
		else Time.get_ticks_msec() + int(duration_s * 1000.0)
	)
	chase_on_area = true
	if not possible_targets.has(source):
		possible_targets.append(source)
	targeted_player = source
	if enemy_state != EnemyState.ATTACK:
		enemy_state = EnemyState.CHASE


## True while a roar still owns our aggro. A dead / warped-out / disconnected
## taunter clears it (via _is_target_valid), so the lock can never strand a mob
## staring at a corpse — the roar is a leash on the mob, not on the fight.
func is_taunted() -> bool:
	if taunt_source == null or taunt_until_ms == 0:
		return false
	if taunt_until_ms != TAUNT_UNTIL_DEATH and Time.get_ticks_msec() >= taunt_until_ms:
		_clear_taunt()
		return false
	if not _is_target_valid(taunt_source) or not _is_hostile_to(taunt_source):
		_clear_taunt()
		return false
	# A respawn puts the taunter alive again on the other side of the map, and
	# _is_target_valid cannot tell that from a tank who simply backed up. Without
	# this the mob would march across the world holding a taunt on a corpse's
	# replacement — the same "prey teleported" case _target_escaped exists for.
	if global_position.distance_to(taunt_source.global_position) > TAUNT_BREAK_PX:
		_clear_taunt()
		return false
	return true


func _clear_taunt() -> void:
	taunt_source = null
	taunt_until_ms = 0


## Re-lock onto the taunter if a roar is live. Called from every path that would
## otherwise DROP or SWITCH the target (leash, ally-call, retaliation, target
## loss); returns true when it took the target back, so the caller bails out.
func _hold_taunt() -> bool:
	if not is_taunted():
		return false
	targeted_player = taunt_source
	if enemy_state != EnemyState.ATTACK:
		enemy_state = EnemyState.CHASE
	return true


func _find_targets() -> void:
	if _hold_taunt(): return
	if targeted_player: return
	# is_dead also covers REVIVING (down but not out) — a body on the ground
	# doesn't acquire targets; its behavior re-targets when it stands up.
	if is_dead: return
	if enemy_state == EnemyState.RETURNING or enemy_state == EnemyState.DEAD: return
	# Passive / skiller-safe mobs (chase_on_area=false): never auto-aggro just
	# because a player walked nearby. They only engage when hit (take_damage)
	# or when a pack-mate is attacked (_on_ally_attacked).
	if not chase_on_area:
		return

	# Self-heal the cached list against the physics truth first: a player who never
	# LEFT the area after we dropped them is invisible to us otherwise. stop_chase
	# erases the old target, and body_entered only fires on a boundary CROSSING — so
	# a player we de-aggroed (leash, respawn) while they stood in range never gets
	# re-added. That's the long-standing "can't re-aggro by standing there, but
	# hitting me works (take_damage sets the target directly)" bug.
	_resync_possible_targets()

	# First living player still in range (skips dead/freed entries). Re-acquires
	# players who were already inside the area after a respawn.
	for candidate: Player in possible_targets:
		if _is_target_valid(candidate) and _is_hostile_to(candidate):
			targeted_player = candidate
			enemy_state = EnemyState.CHASE
			return


## Fold any player currently overlapping our detection area back into
## possible_targets. Additions only — body_exited handles removals. Cheap (a
## handful of bodies) and only runs while we're hunting (no target, not returning).
func _resync_possible_targets() -> void:
	if detection_area == null:
		return
	for body: Node2D in detection_area.get_overlapping_bodies():
		if body is Player and _is_hostile_to(body) and not possible_targets.has(body):
			possible_targets.append(body)


## Defenders are hostile to everyone EXCEPT players tagged into their owning
## guild. Regular mobs are hostile to all players.
func _is_hostile_to(player: Player) -> bool:
	if owner_guild_id <= 0:
		return true # Ordinary mob — hostile to every player.
	if player == null or player.player_resource == null:
		return true
	return player.player_resource.active_guild_id != owner_guild_id


## Valid = a living player still in THIS instance. Catches warp-outs: a warped
## player is reparented to another instance (different viewport, or briefly no
## parent mid-transfer), so the guard drops the target and heads home instead of
## chasing into the void.
func _is_target_valid(player: Player) -> bool:
	return is_instance_valid(player) and player.is_inside_tree() \
			and not player.is_dead and player.get_viewport() == get_viewport() \
			and not player.is_in_npc_dialogue()


func abandon_current_target() -> void:
	_abandon_target()


## A player can't MOVE more than a couple of px per physics tick — a bigger jump
## means they TELEPORTED (death respawn, warp, /goto, spar start...). Server-side
## death + respawn happens within one frame, so is_dead is never observably true;
## perceiving the position discontinuity is the intuitive, mechanism-agnostic way
## to notice "my prey vanished" instead of marching across the map to the respawn.
const TARGET_TELEPORT_BREAK_PX: float = 60.0
var _tracked_target: Player
var _tracked_target_position: Vector2


func _target_escaped() -> bool:
	if targeted_player != _tracked_target:
		# New target — start tracking from wherever they are now.
		_tracked_target = targeted_player
		_tracked_target_position = targeted_player.global_position
		return false
	var jump: float = _tracked_target_position.distance_to(targeted_player.global_position)
	_tracked_target_position = targeted_player.global_position
	return jump > TARGET_TELEPORT_BREAK_PX


# --- Behavior client visuals -------------------------------------------------
# (Lunge LOGIC lives in behaviors/lunge_behavior.gd — refactor P1. These rp_
# handlers stay here: they're client-side visual primitives resolved on the
# mob node by the container's op replay.)

## Client-side dash playback: the interpolation buffer renders mobs
## net_smooth_delay_ms in the past — invisible at walk speed, visibly LATE for
## a 5x-speed dash. The dash is deterministic (straight, heading + landing
## locked at windup start, constant speed), so it's sent TOGETHER with the
## windup telegraph and scheduled start_delay_ms out: the local dash begins
## exactly when the local telegraph expires (one clock — coherent to the
## eye), played in real time via the smoother's scripted-motion override.
## Buffered samples resume at touchdown; the snap rule covers a wall-blocked
## early landing; the enemy_state setter cancels on death.
func rp_dash(from_position: Vector2, to_position: Vector2, duration_ms: int, start_delay_ms: int) -> void:
	if multiplayer.is_server():
		return
	# Ensure the smoother exists (a mob can dash before its first position
	# sample on a late-joining client); the from-sample is where it stands.
	net_apply_position(from_position)
	_net_smoother.play_motion(from_position, to_position, duration_ms, start_delay_ms)

## Client-visual: the red dodge corridor from this mob to the locked landing
## spot — shows WHO is charging and the exact strip of ground to vacate.
## [param from_position] overrides where the corridor starts. Vector2.INF (the
## default) keeps the body's own position, which is what a lunge wants; a beam
## fired from the raised fist passes its muzzle so the marked strip is the strip
## the server actually hit-tests.
func rp_lunge_telegraph(
		to_position: Vector2, radius: float, duration: float,
		from_position: Vector2 = Vector2.INF, element: int = -1
	) -> void:
	if multiplayer.is_server():
		return
	var telegraph: AttackTelegraph = AttackTelegraph.new()
	telegraph.radius = radius
	telegraph.duration = duration
	if element >= 0:
		telegraph.color = ElementalTelegraph.PALETTE[clampi(
			element, 0, ElementalTelegraph.Element.size() - 1)][0]
	telegraph.top_level = true # pinned to the world, not to the moving wolf
	add_child(telegraph)
	var origin: Vector2 = global_position if from_position == Vector2.INF else from_position
	telegraph.global_position = origin
	telegraph.line_to = to_position - origin


## Client-visual: a FILLING danger ring (CastTelegraph) for a telegraphed boss
## slam — it fills + sweeps a clock-wedge over [param duration] so players read
## exactly when the hit lands, then vanishes as the impact takes over. World-
## pinned at the cast origin (the boss is rooted during the wind-up anyway).
func rp_cast_telegraph(center: Vector2, radius: float, duration: float) -> void:
	if multiplayer.is_server():
		return
	var tele: CastTelegraph = CastTelegraph.new()
	tele.radius = radius
	tele.duration = duration
	tele.top_level = true
	add_child(tele)
	tele.global_position = center


## Client-visual: the ground shockwave (SlamImpact) when a boss slam lands —
## expanding rings + debris radiating from the impact point. The "already
## happened" counterpart to the filling cast telegraph.
func rp_slam_impact(center: Vector2, radius: float) -> void:
	if multiplayer.is_server():
		return
	var impact: SlamImpact = SlamImpact.new()
	impact.max_radius = radius
	impact.color = Color(1.0, 0.5, 0.3, 0.9)
	impact.debris = 8
	impact.ring_count = 2
	impact.top_level = true
	add_child(impact)
	impact.global_position = center


## Client-visual: play a one-shot SpriteFrames clip (attack / special) on this
## mob's skin. Pauses the AnimationTree so the locomotion method-tracks don't
## stomp the action mid-play, then resumes idle/run from the synced anim enum.
## [param fill_s] stretches the clip to occupy that many seconds. A boss cast is
## usually LONGER than its clip — a 0.5s transform under a 3s Killing Frost
## channel left the body standing idle for two and a half seconds mid-spell — so
## the caller passes its wind-up and the clip is slowed to cover it exactly.
## 0 (default) plays at the authored rate, which is what a swing wants.
func rp_play_skin_anim(anim_name: StringName, fill_s: float = 0.0) -> void:
	if multiplayer.is_server() or animated_sprite == null:
		return
	var frames: SpriteFrames = animated_sprite.sprite_frames
	if frames == null:
		return
	# Fall back to the swing when the requested clip is not on this skin. Bosses
	# ask for "special" on every cast, but several shipped skins never had one —
	# so their slams have been playing NOTHING, silently, since the clip lookup
	# just returned. A skin with neither clip still no-ops; that is missing art,
	# not a missing code path.
	if not frames.has_animation(anim_name):
		if anim_name != &"attack" and frames.has_animation(&"attack"):
			anim_name = &"attack"
		else:
			return
	if _skin_base_speed < 0.0:
		_skin_base_speed = maxf(0.01, animated_sprite.speed_scale)
	_skin_action_playing = true
	_skin_action_token += 1
	var token: int = _skin_action_token
	if animation_tree != null:
		animation_tree.active = false
	# Natural length at the authored rate, then the stretch (never a squeeze: a
	# cast shorter than its clip keeps the clip and just gets cut off).
	var fps: float = maxf(1.0, frames.get_animation_speed(anim_name) * _skin_base_speed)
	var clip_s: float = float(frames.get_frame_count(anim_name)) / fps
	if fill_s > clip_s:
		animated_sprite.speed_scale = _skin_base_speed * (clip_s / fill_s)
		clip_s = fill_s
	else:
		animated_sprite.speed_scale = _skin_base_speed
	# Restart even if the same clip just finished (otherwise a second swing can
	# no-op when the sprite is still sitting on the last attack frame).
	animated_sprite.play(anim_name)
	if animated_sprite.animation_finished.is_connected(_on_skin_action_finished):
		animated_sprite.animation_finished.disconnect(_on_skin_action_finished)
	animated_sprite.animation_finished.connect(_on_skin_action_finished, CONNECT_ONE_SHOT)
	# Watchdog: a same-frame locomotion play() (AnimationTree DEFERRED method
	# track at an idle/run loop boundary) can swallow animation_finished for this
	# clip and leave the tree switched off forever — frozen sprite, no death.
	get_tree().create_timer(clip_s + 0.25).timeout.connect(
		func() -> void:
			if _skin_action_playing and _skin_action_token == token:
				_on_skin_action_finished(),
		CONNECT_ONE_SHOT
	)


func _on_skin_action_finished() -> void:
	if not _skin_action_playing:
		return
	_cancel_skin_action()
	# Re-kick locomotion from the current synced anim (IDLE/RUN/DEATH).
	_set_anim(anim)


## Drop out of a one-shot NOW: clear the flag, invalidate any pending watchdog,
## put the authored playback rate back, and hand the sprite to the AnimationTree.
## Does not travel — the caller decides what plays next.
func _cancel_skin_action() -> void:
	_skin_action_playing = false
	_skin_action_token += 1
	if animated_sprite != null and _skin_base_speed >= 0.0:
		animated_sprite.speed_scale = _skin_base_speed
	if animation_tree != null:
		animation_tree.active = true


func _set_anim(new_anim: Animations) -> void:
	# Keep the synced enum current, but don't travel locomotion over a one-shot
	# (same-tick :anim IDLE pairs used to erase rp_play_skin_anim swings).
	if _skin_action_playing and new_anim != Animations.DEATH:
		anim = new_anim
		return
	# DEATH interrupts a one-shot immediately. It already fell through the guard
	# above, but travelling while rp_play_skin_anim still has the AnimationTree
	# switched OFF does nothing: the corpse would hold its cast pose until the
	# watchdog fired — up to a full stretched cast later. Cancel first, then travel.
	if _skin_action_playing:
		_cancel_skin_action()
	match new_anim:
		Animations.IDLE:
			locomotion_state_machine.travel(&"locomotion_idle")
		Animations.RUN:
			locomotion_state_machine.travel(&"locomotion_run")
		Animations.DEATH:
			locomotion_state_machine.travel(&"locomotion_death")
	anim = new_anim


## Client-visual: a short laser blast along a world corridor (Mecha Golem). The
## server already applied damage; this is the beam VFX on top of the telegraph.
## [param _duration] is kept for the replicated call signature but no longer
## used — the clip now decides its own lifetime (see below).
func rp_laser_beam(from: Vector2, to: Vector2, _duration: float) -> void:
	if multiplayer.is_server():
		return
	var laser_frames: SpriteFrames = load(
		"res://source/common/gameplay/combat/vfx/mecha_laser.tres"
	) as SpriteFrames
	if laser_frames == null:
		return
	var mid: Vector2 = (from + to) * 0.5
	var beam_len: float = from.distance_to(to)
	var sc: float = maxf(0.35, beam_len / 300.0)
	# NO explicit duration. The mecha_laser sheet spends its first ~10 frames
	# charging and only becomes a beam near the end, so the old
	# `duration: maxf(0.2, duration)` (0.4s from the controller, against a 0.8s
	# clip) freed the effect BEFORE the beam frames were ever drawn — the laser
	# was a charge orb and nothing else. Omitting it lets SpriteEffect free itself
	# on animation_finished, i.e. after the beam has actually been seen.
	var fx: SpriteEffect = SpriteEffect.spawn(self, laser_frames, {
		"scale": Vector2(sc, sc * 0.55),
		"z_index": 2,
		"speed_scale": 1.25,
	})
	if fx == null:
		return
	fx.top_level = true
	fx.global_position = mid
	fx.rotation = (to - from).angle()


## Client-visual: a thrown arm-cannon bolt the player must sidestep. Cosmetic —
## the server's Projectile owns the hit.
func rp_arm_projectile(direction: Vector2, speed: float, lifetime: float) -> void:
	if multiplayer.is_server():
		return
	_spawn_arm_bolt(direction, speed, lifetime, 0.0, false)


## Server: fire a damaging arm bolt and echo the cosmetic flight to clients.
func fire_arm_projectile(direction: Vector2, speed: float, lifetime: float, damage: float) -> void:
	if not multiplayer.is_server():
		return
	_spawn_arm_bolt(direction, speed, lifetime, damage, true)
	replicate_visual(&"rp_arm_projectile", [direction, speed, lifetime])


## Shared arm-bolt factory (server damage + client cosmetic). [param deal_damage]
## true only on the authoritative peer.
func _spawn_arm_bolt(
		direction: Vector2,
		speed: float,
		lifetime: float,
		damage: float,
		deal_damage: bool
	) -> void:
	var bolt: Projectile = preload(
		"res://source/common/gameplay/items/weapons/wand/bolt.tscn"
	).instantiate() as Projectile
	bolt.direction = direction.normalized()
	bolt.speed = speed
	bolt.lifetime = lifetime
	bolt.damage = damage if deal_damage else 0.0
	bolt.damage_type = CombatHit.DAMAGE_PHYSICAL
	bolt.source = self
	bolt.top_level = true
	# The arm cannon borrows the bolt scene for its FLIGHT, not its look: drop the arcane
	# body (BoltVisual) and fly the stone arm instead.
	var body: Node = bolt.get_node_or_null(^"Visual")
	if body != null:
		body.queue_free()
	var tex: Texture2D = load(
		"res://assets/sprites/characters/mecha_stone_golem/arm_projectile.png"
	) as Texture2D
	if tex != null:
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = tex
		sprite.scale = Vector2(0.22, 0.22)
		bolt.add_child(sprite)
	add_child(bolt)
	bolt.global_position = global_position + direction.normalized() * 28.0


# ---------------------------------------------------------------------------
# Boss spell VFX (client-only). Each is spawned by BossController via
# replicate_visual, always as a top_level node so it stays pinned to the WORLD
# point the server hit-tested instead of sliding with the boss body. The sheets
# come from source/common/gameplay/combat/vfx/ — loaded lazily rather than
# preloaded because the server runs this same script and never draws any of it.
# ---------------------------------------------------------------------------

const _VFX_DIR: String = "res://source/common/gameplay/combat/vfx/"


## Cache-free loader — a miss returns null and every caller no-ops rather than
## crashing a client mid-fight over a cosmetic.
func _vfx(name: String) -> SpriteFrames:
	return load(_VFX_DIR + name + ".tres") as SpriteFrames


## Frame size every "how big is this mob" rule is calibrated against. A 64px
## skin drawn at visual_scale 1.0 is the unit.
const REFERENCE_FRAME_PX: float = 64.0


## How large this body READS, relative to an ordinary 64px mob. This — not
## [member EnemyTypeResource.visual_scale] — is what a "bosses get a bigger
## allowance" rule should key off.
##
## visual_scale is a multiplier on the ART, so it only doubles as a size proxy
## while every skin is a 64px frame. Malacor is 144px at 1.0x: drawn the same
## size as a 64px skin at 2.25x, but every visual_scale test would read him as an
## ordinary mob — no aim-assist bonus, no melee reach bonus, no bar lift, and a
## player walking to the ORIGIN of a sprite half a screen wide.
##
## Floored at visual_scale so this can never SHRINK an existing allowance: for
## every shipped skin the drawn art is smaller than 64 * visual_scale (the trpg
## sheets are 20px of content in a 100px frame), so the floor wins and behaviour
## is identical. Only a skin drawn BIGGER than its visual_scale implies — the
## broken case — moves.
func body_scale() -> float:
	if _body_scale > 0.0:
		return _body_scale
	var vs: float = 1.0
	if enemy_data != null:
		vs = maxf(0.1, enemy_data.visual_scale)
	_body_scale = vs
	var frames: SpriteFrames = enemy_data.skin if enemy_data != null else null
	if frames == null or not frames.has_animation(&"idle") \
			or frames.get_frame_count(&"idle") <= 0:
		return _body_scale
	# Measure the DRAWN art, not the frame: a frame is mostly padding on some
	# sheets, and padding is not size.
	var tex: AtlasTexture = frames.get_frame_texture(&"idle", 0) as AtlasTexture
	if tex == null or tex.atlas == null:
		return _body_scale
	var img: Image = tex.atlas.get_image()
	if img == null:
		return _body_scale
	var used: Rect2i = img.get_region(Rect2i(tex.region)).get_used_rect()
	if used.size.y > 0:
		_body_scale = maxf(vs, float(used.size.y) * vs / REFERENCE_FRAME_PX)
	return _body_scale


## Where a spell leaves the body: the raised fist.
##
## Deliberately NOT the HandOffset/RightHandSpot rig. That rig is authored for
## mounting weapons on a 1x player and _apply_enemy_data never scales it, so on a
## 1.4x boss it lands inside the torso. This is measured off the ART instead —
## the fist sits +16px right of frame centre, and the AnimatedSprite2D is drawn at
## offset (0, -30) — then scaled by visual_scale, which is what actually moves the
## drawn fist. Server and client run the identical formula, so a beam is DRAWN
## from the same point its damage is measured from.
const MUZZLE_LOCAL: Vector2 = Vector2(16.0, -30.0)
## The tip of the STAFF in the cast_staff thrust frame (+25, +7 from frame centre,
## plus the sprite's own -30 offset). A spell fired from a staff has to leave the
## staff — anchored at the fist it reads as the effect appearing beside him.
const STAFF_MUZZLE_LOCAL: Vector2 = Vector2(25.0, -23.0)


## [param from_staff] picks the staff tip over the fist. The CALLER says which,
## because it chose the pose; inspecting the current clip here would be a
## frame-timing race against the animation.
func muzzle_position(from_staff: bool = false) -> Vector2:
	var s: float = 1.0
	if enemy_data != null:
		s = maxf(0.1, enemy_data.visual_scale)
	var local: Vector2 = STAFF_MUZZLE_LOCAL if from_staff else MUZZLE_LOCAL
	var dir: float = -1.0 if flipped else 1.0
	return global_position + Vector2(local.x * dir, local.y) * s


## Client-visual: a charge building in the raised fist through a cast wind-up —
## the tell that the boss is powering something up rather than just posing.
## [param element] matches ElementalTelegraph (0 fire / 1 frost / 2 storm).
func rp_hand_charge(element: int, duration: float, from_staff: bool = false) -> void:
	if multiplayer.is_server():
		return
	# Compact 128x128 sheets only. lash_cast is 128x256 — a tall pillar of flame
	# designed to rise from the ground — so centring it on a staff head draped the
	# effect over the whole boss.
	var sheet: String = "lash_burst"
	var tint: Color = Color(1.0, 0.72, 0.35)
	if element == 2:
		sheet = "static_ring"
		tint = Color(0.78, 0.62, 1.0)
	elif element == 1:
		sheet = "frost_burst"
		tint = Color(0.7, 0.92, 1.0)
	var frames: SpriteFrames = _vfx(sheet)
	if frames == null:
		return
	var fx: SpriteEffect = SpriteEffect.spawn(self, frames, {
		"loop": true,
		"duration": duration,
		"scale": Vector2(0.38, 0.38),
		"z_index": 3,
		"speed_scale": 1.6,
		"modulate": tint,
	})
	if fx == null:
		return
	# NOT top_level: the charge rides the body, so it tracks the boss if it is
	# shoved or slides during the wind-up.
	var local: Vector2 = STAFF_MUZZLE_LOCAL if from_staff else MUZZLE_LOCAL
	fx.position = Vector2(local.x * (-1.0 if flipped else 1.0), local.y) \
		* (enemy_data.visual_scale if enemy_data != null else 1.0)


## Client-visual: the rich wind-up marker for a boss cast. [param element] and
## [param mode] are ElementalTelegraph's enums as ints (0=fire/1=frost/2=storm,
## 0=danger/1=safe) — enums cross the wire as plain ints.
func rp_elem_telegraph(
		center: Vector2, radius: float, duration: float, element: int, mode: int
	) -> void:
	if multiplayer.is_server():
		return
	var tele: ElementalTelegraph = ElementalTelegraph.new()
	tele.radius = radius
	tele.duration = duration
	# Assign the ints straight across (an enum IS an int here) and clamp, rather
	# than `as`-casting: a bad cast would leave the field null and the telegraph
	# would silently draw nothing while the server still lands the hit.
	tele.element = clampi(element, 0, ElementalTelegraph.Element.size() - 1)
	tele.mode = clampi(mode, 0, ElementalTelegraph.Mode.size() - 1)
	tele.top_level = true
	add_child(tele)
	tele.global_position = center


## Client-visual: one meteor of the Ember Rain. The comet screams in from
## above-right and the blast fires the instant it lands, so the explosion is the
## frame the server's damage window opens on — the fall IS the countdown.
func rp_meteor_fall(target: Vector2, fall_s: float, blast_radius: float) -> void:
	if multiplayer.is_server():
		return
	var comet: SpriteFrames = _vfx("fireball_comet")
	if comet == null:
		_meteor_boom(target, blast_radius)
		return
	var fx: SpriteEffect = SpriteEffect.spawn(self, comet, {
		"loop": true,
		"duration": fall_s + 0.08,
		"scale": Vector2(1.1, 1.1),
		"z_index": 4,
	})
	if fx == null:
		_meteor_boom(target, blast_radius)
		return
	fx.top_level = true
	fx.global_position = target + Vector2(170.0, -250.0)
	var tween: Tween = fx.create_tween()
	tween.tween_property(fx, "global_position", target, fall_s)
	# Fire the blast off a SCENE timer, not off the tween's completion. The tween
	# lives on the comet, and the comet frees itself on its own lifetime — if that
	# ever lands first the callback dies with it and a meteor deals damage with no
	# explosion at all. The timer is owned by the mob and cannot be cancelled by
	# the comet's lifecycle.
	get_tree().create_timer(fall_s).timeout.connect(
		_meteor_boom.bind(target, blast_radius), CONNECT_ONE_SHOT)


func _meteor_boom(target: Vector2, blast_radius: float) -> void:
	var boom: SpriteFrames = _vfx("fire_explosion")
	if boom != null:
		var fx: SpriteEffect = SpriteEffect.spawn(self, boom, {
			"scale": Vector2.ONE * (blast_radius * 2.4 / 128.0),
			"z_index": 3,
		})
		if fx != null:
			fx.top_level = true
			fx.global_position = target
	# Scorch ring under the fireball so the ground reads burnt, not just lit.
	var impact: SlamImpact = SlamImpact.new()
	impact.max_radius = blast_radius
	impact.color = Color(1.0, 0.55, 0.2, 0.9)
	impact.debris = 6
	impact.ring_count = 2
	impact.top_level = true
	add_child(impact)
	impact.global_position = target


## Client-visual: the phase-2 detonation — a frost burst on the body plus a pale
## shockwave ring, big enough to sell "the arena just changed".
func rp_frost_nova(center: Vector2, radius: float) -> void:
	if multiplayer.is_server():
		return
	var burst: SpriteFrames = _vfx("frost_burst")
	if burst != null:
		var fx: SpriteEffect = SpriteEffect.spawn(self, burst, {
			"scale": Vector2.ONE * (radius * 2.3 / 128.0),
			"z_index": 3,
		})
		if fx != null:
			fx.top_level = true
			fx.global_position = center
	var impact: SlamImpact = SlamImpact.new()
	impact.max_radius = radius
	impact.color = Color(0.6, 0.9, 1.0, 0.95)
	impact.debris = 10
	impact.ring_count = 3
	impact.top_level = true
	add_child(impact)
	impact.global_position = center


## Client-visual: Killing Frost landing — spikes erupt in a ring AROUND the safe
## circle, staggered outward so the freeze visibly sweeps in rather than popping
## on in one frame. Nothing is drawn inside [param safe_radius]: the clean patch
## is the mechanic.
func rp_ice_spikes(center: Vector2, safe_radius: float, count: int) -> void:
	if multiplayer.is_server():
		return
	var spikes: SpriteFrames = _vfx("frost_spikes")
	if spikes == null:
		return
	for ring: int in 2:
		var r: float = safe_radius + 46.0 + float(ring) * 62.0
		var n: int = maxi(3, count + ring * 2)
		for i: int in n:
			var angle: float = TAU * float(i) / float(n) + float(ring) * 0.4
			var at: Vector2 = center + Vector2.from_angle(angle) * r
			var delay: float = float(ring) * 0.12 + randf() * 0.06
			get_tree().create_timer(delay).timeout.connect(
				_pop_ice_spike.bind(at, spikes))


func _pop_ice_spike(at: Vector2, spikes: SpriteFrames) -> void:
	var fx: SpriteEffect = SpriteEffect.spawn(self, spikes, {
		"scale": Vector2(0.55, 0.55),
		"z_index": 1,
		"speed_scale": 1.15,
	})
	if fx == null:
		return
	fx.top_level = true
	fx.global_position = at


## Client-visual: a lightning chain welded from segment sprites. [param points]
## is the server's resolved arc path (boss → first target → next → …), so what
## players see is exactly who got hit and in what order.
func rp_chain_lightning(points: PackedVector2Array) -> void:
	if multiplayer.is_server() or points.size() < 2:
		return
	var bolt: SpriteFrames = _vfx("arc_bolt")
	var ring: SpriteFrames = _vfx("static_ring")
	for i: int in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var span: float = a.distance_to(b)
		if span <= 1.0:
			continue
		if bolt != null:
			# arc_bolt's cell is 256 wide; stretch along the span, keep it thin.
			var fx: SpriteEffect = SpriteEffect.spawn(self, bolt, {
				"scale": Vector2(span / 256.0, 0.42),
				"z_index": 3,
				"speed_scale": 1.4,
			})
			if fx != null:
				fx.top_level = true
				fx.global_position = (a + b) * 0.5
				fx.rotation = (b - a).angle()
		# A burst on each struck target so the chain has punctuation.
		if ring != null and i > 0:
			var hit: SpriteEffect = SpriteEffect.spawn(self, ring, {
				"scale": Vector2(0.7, 0.7), "z_index": 3, "speed_scale": 1.3,
			})
			if hit != null:
				hit.top_level = true
				hit.global_position = a


## Client-visual: the Cinder Lash — a beam that SWEEPS through an arc instead of
## firing down one fixed line. Built as a pivot at the boss with the beam parked
## half a length out along +X, then the pivot is tweened: rotating the sprite
## about its own centre would spin the beam in place instead of sweeping it.
func rp_sweep_beam(
		origin: Vector2, angle_from: float, angle_to: float, length: float, duration: float
	) -> void:
	if multiplayer.is_server():
		return
	var beam: SpriteFrames = _vfx("lash_beam")
	if beam == null:
		return
	var pivot: Node2D = Node2D.new()
	pivot.top_level = true
	add_child(pivot)
	pivot.global_position = origin
	pivot.rotation = angle_from
	var fx: SpriteEffect = SpriteEffect.spawn(pivot, beam, {
		"loop": true,
		"duration": duration + 0.12,
		"scale": Vector2(length / 256.0, 0.7),
		"z_index": 3,
		"speed_scale": 1.5,
		"modulate": Color(1.0, 0.72, 0.35),  # lightning sheet burning as fire
	})
	if fx != null:
		fx.position = Vector2(length * 0.5, 0.0)
	var tween: Tween = pivot.create_tween()
	tween.tween_property(pivot, "rotation", angle_to, duration)
	tween.tween_callback(pivot.queue_free)


func _process_animations() -> void:
	match enemy_state:
		EnemyState.RETURNING:
			if anim != Character.Animations.RUN:
				anim = Character.Animations.RUN
		EnemyState.IDLE:
			# Strolling idle uses RUN so clients see walk clips while wandering.
			var idle_anim: Character.Animations = (
				Character.Animations.RUN if velocity.length_squared() > 1.0
				else Character.Animations.IDLE
			)
			if anim != idle_anim:
				anim = idle_anim
		EnemyState.CHASE:
			if anim != Character.Animations.RUN:
				anim = Character.Animations.RUN
		EnemyState.ATTACK:
			# Attacking on the move reads as RUN; planted reads as IDLE.
			var attack_anim: Character.Animations = (
				Character.Animations.RUN if velocity.length_squared() > 1.0
				else Character.Animations.IDLE
			)
			if anim != attack_anim:
				anim = attack_anim
		EnemyState.LUNGE_WINDUP:
			if anim != Character.Animations.IDLE:
				anim = Character.Animations.IDLE
		EnemyState.LUNGING:
			if anim != Character.Animations.RUN:
				anim = Character.Animations.RUN


func _process_synchronization() -> void:
	if _prop_id < 0 and container != null:
		_prop_id = container.child_id_of_node(self)
	container.mark_child_prop(_prop_id, _position_fid, position, true)
	container.mark_child_prop(_prop_id, _anim_fid, anim, true)
	container.mark_child_prop(_prop_id, _flipped_fid, flipped, true)
	container.mark_child_prop(_prop_id, _state_fid, enemy_state, true)
	container.mark_child_prop(_prop_id, _health_fid, stats_component.get_stat(Stat.HEALTH), true)
	container.mark_child_prop(_prop_id, _health_max_fid, stats_component.get_stat(Stat.HEALTH_MAX), true)


## Face the active target so run/attack clips read directionally on clients.
func _face_target() -> void:
	if targeted_player == null or not is_instance_valid(targeted_player):
		return
	var face_left: bool = targeted_player.global_position.x < global_position.x
	if flipped != face_left:
		flipped = face_left


## A wounded idle mob doesn't heal where it stands — once the fight has been over
## for OUT_OF_COMBAT_REGEN_DELAY_MS it walks home and recovers there. Applies to
## EVERY hostile, committed bosses included: a boss that wipes a party resets like
## any other mob instead of sitting at 4% HP forever (or, worse, topping itself up
## while a player is still hitting it) — unless the body has opted out entirely
## via [member regenerates_out_of_combat]. Returns true when it took over the
## state.
func _process_idle_recovery() -> bool:
	if not _can_out_of_combat_regen():
		return false
	if stats_component.get_stat(Stat.HEALTH) >= stats_component.get_stat(Stat.HEALTH_MAX):
		return false
	# Already parked on the spawn point: RETURNING resolves it to a full bar on its
	# very first frame (distance < 10) — no walk, no special case here.
	enemy_state = EnemyState.RETURNING
	velocity = Vector2.ZERO
	_clear_wander_leg(Time.get_ticks_msec(), false)
	return true


func _mark_combat_activity() -> void:
	_last_combat_activity_ms = Time.get_ticks_msec()


func _can_out_of_combat_regen() -> bool:
	if not regenerates_out_of_combat:
		return false
	return Time.get_ticks_msec() - _last_combat_activity_ms >= OUT_OF_COMBAT_REGEN_DELAY_MS


## Idle = the out-of-combat recovery check + optional short strolls around spawn
## (wander_radius > 0). Combat / return / behavior states never call this —
## chase_on_area and hit-to-aggro still work unchanged. Direct steering (no A*);
## wall hits abandon the current leg so goblins don't pin against trees forever.
func _process_idle() -> void:
	if _process_idle_recovery():
		return
	if wander_radius <= 0.0:
		velocity = Vector2.ZERO
		return

	var now: int = Time.get_ticks_msec()
	if now < _wander_pause_until_ms:
		velocity = Vector2.ZERO
		return

	if _has_wander_target and global_position.distance_to(_wander_target) <= 10.0:
		_clear_wander_leg(now, true)
		return

	if not _has_wander_target:
		_pick_wander_target()
		if not _has_wander_target:
			_wander_pause_until_ms = now + 1000
			velocity = Vector2.ZERO
			return

	var direction: Vector2 = global_position.direction_to(_wander_target)
	# Idle stroll — slower than chase so packs read as milling, not hunting.
	velocity = direction * float(move_speed) * 0.55
	if absf(direction.x) > 0.05:
		flipped = direction.x < 0.0
	var before: Vector2 = global_position
	move_and_slide()
	if get_slide_collision_count() > 0 and before.distance_to(global_position) < 0.4:
		_wander_stuck_frames += 1
		if _wander_stuck_frames >= 12:
			_clear_wander_leg(now, true)
	else:
		_wander_stuck_frames = 0


func _clear_wander_leg(now: int, pause: bool) -> void:
	_has_wander_target = false
	_wander_stuck_frames = 0
	velocity = Vector2.ZERO
	if pause:
		var lo: float = maxf(0.4, wander_pause_min_s)
		var hi: float = maxf(lo, wander_pause_max_s)
		_wander_pause_until_ms = now + int(randf_range(lo, hi) * 1000.0)


func _pick_wander_target() -> void:
	_has_wander_target = false
	_wander_stuck_frames = 0
	if wander_radius <= 0.0:
		return
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	if space == null:
		return
	# Stay inside a fraction of the leash so wander never trips RETURNING.
	var max_r: float = minf(wander_radius, float(max_distance_from_spawn) * 0.55)
	if max_r < 12.0:
		return
	for _attempt: int in 8:
		var angle: float = randf() * TAU
		var dist: float = randf_range(max_r * 0.35, max_r)
		var candidate: Vector2 = spawn_position + Vector2.from_angle(angle) * dist
		var ray := PhysicsRayQueryParameters2D.create(global_position, candidate)
		ray.collision_mask = PhysicsLayers.SOLID_GROUND_MASK # world solids + decoration (walls / water / void / scenery)
		ray.exclude = [get_rid()]
		if not space.intersect_ray(ray).is_empty():
			continue
		var point := PhysicsPointQueryParameters2D.new()
		point.position = candidate
		point.collision_mask = PhysicsLayers.SOLID_GROUND_MASK
		point.collide_with_areas = false
		point.exclude = [get_rid()]
		if not space.intersect_point(point, 1).is_empty():
			continue
		_wander_target = candidate
		_has_wander_target = true
		return


func _process_return() -> void:
	# Move toward spawn at the boosted return speed — outpaces typical
	# player movement so leashed mobs can't be re-kited.
	var direction: Vector2 = global_position.direction_to(spawn_position)
	velocity = direction * move_speed * RETURN_SPEED_MULTIPLIER
	move_and_slide()

	# Heal-on-the-walk only after a real out-of-combat gap — otherwise kiting
	# just outside a mechanic starts a 25%/s refill while the fight is still on.
	var hmax: float = stats_component.get_stat(Stat.HEALTH_MAX)
	var current_h: float = stats_component.get_stat(Stat.HEALTH)
	if current_h < hmax and _can_out_of_combat_regen():
		var dt: float = get_physics_process_delta_time()
		var regen: float = hmax * RETURN_REGEN_RATE * dt
		stats_component.set_stat(Stat.HEALTH, minf(hmax, current_h + regen))

	var distance_from_spawn: float = global_position.distance_to(spawn_position)
	if distance_from_spawn < 10: # minimum distance from spawn.
		_finish_return(hmax)
		return
	# Wall-jammed (or spawn point since made unreachable): give up on the walk
	# rather than stay a deaf, un-aggroable body forever.
	if Time.get_ticks_msec() - _return_since_ms > RETURN_TIMEOUT_MS:
		_finish_return(hmax)


## End the march home: top the bar off and go back on duty. The top-off is the
## leash RESET — but ONLY out of combat. A player who kites a boss past its leash
## and keeps hitting it all the way home used to get a free full bar the instant it
## touched the spawn point; now the body just idles wounded until the window is
## clear, at which point _process_idle_recovery sends it straight back through here.
func _finish_return(hmax: float) -> void:
	if stats_component.get_stat(Stat.HEALTH) < hmax and _can_out_of_combat_regen():
		stats_component.set_stat(Stat.HEALTH, hmax)
	_clear_wander_leg(Time.get_ticks_msec(), true)
	enemy_state = EnemyState.IDLE


func _process_chase() -> void:
	_mark_combat_activity()
	if not _is_target_valid(targeted_player):
		_abandon_target()
		return
	if _target_escaped():
		stop_chase()
		return

	_face_target()
	var direction: Vector2 = global_position.direction_to(targeted_player.global_position)
	velocity = direction * move_speed
	move_and_slide()

	var distance_from_spawn: float = global_position.distance_to(spawn_position)
	if distance_from_spawn > max_distance_from_spawn:
		stop_chase()
		return

	var distance_from_player: float = global_position.distance_to(targeted_player.global_position)
	if distance_from_player < distance_to_attack:
		enemy_state = EnemyState.ATTACK
		return

	# Composable behaviors: the first one that wants this window takes over
	# the state machine (e.g. the lunge commits to its windup).
	var now: int = Time.get_ticks_msec()
	for behavior: MobBehavior in behaviors:
		if behavior.try_start(self, distance_from_player, now):
			_state_owner = behavior
			return


## Inside ATTACK state the mob keeps advancing until this fraction of its
## attack range, then plants — see _process_attack.
const ATTACK_ADVANCE_STOP_FRACTION: float = 0.65


func _process_attack() -> void:
	_mark_combat_activity()
	if not _is_target_valid(targeted_player):
		_abandon_target()
		return
	if _target_escaped():
		stop_chase()
		return

	# Same leash check the chase has — without this, a ranged player can
	# pull the mob to the edge of max_distance_from_spawn, then stand still
	# at attack range and farm forever because the mob never re-checks the
	# distance while in ATTACK state.
	var distance_from_spawn: float = global_position.distance_to(spawn_position)
	if distance_from_spawn > max_distance_from_spawn:
		stop_chase()
		return

	var distance_from_player: float = global_position.distance_to(targeted_player.global_position)
	if distance_from_player > distance_to_attack:
		enemy_state = EnemyState.CHASE
		return

	_face_target()
	# Attack starts at distance_to_attack, but keep CLOSING IN while firing
	# until comfortably inside range — mobs shoot on the move like players do
	# instead of freezing at the range boundary. Oversized bosses use a larger
	# plant radius so they keep walking across their big sprite instead of
	# looking glued to the spawn point while meleeing.
	var plant_at: float = distance_to_attack * ATTACK_ADVANCE_STOP_FRACTION
	if enemy_data != null and enemy_data.visual_scale > 1.0:
		plant_at = maxf(plant_at, 18.0 * enemy_data.visual_scale)
	if distance_from_player > plant_at:
		velocity = global_position.direction_to(targeted_player.global_position) * move_speed
		move_and_slide()
	else:
		velocity = Vector2.ZERO

	# Auto-attack on cooldown: attack_cooldown is the GLOBAL swing rate; each
	# swing goes to the first attack resource whose own recharge is up and
	# whose target exists (array order = priority — see MobAttack).
	var now: int = Time.get_ticks_msec()
	if now >= _next_attack_ms:
		for attack: MobAttack in attacks:
			if attack.try_fire(self, now):
				_next_attack_ms = now + int(attack_cooldown * 1000.0)
				break


## Players this mob can strike right now: everyone the detection area is tracking,
## PLUS its active target. take_damage can set targeted_player WITHOUT a
## body_entered (a player who re-engaged after respawning inside our detection
## radius — so body_entered never re-fires — or a sniper from beyond it), and
## stop_chase erases the old target from possible_targets on a respawn-teleport.
## Without folding the target back in, the mob would telegraph but never connect.
func _strike_candidates() -> Array[Player]:
	var candidates: Array[Player] = possible_targets.duplicate()
	if targeted_player != null and not candidates.has(targeted_player):
		candidates.append(targeted_player)
	return candidates


## Client-visual: flash the melee-range circle. Called via the container's rp_ op.
func rp_attack(radius: float) -> void:
	if multiplayer.is_server():
		return
	var telegraph: AttackTelegraph = AttackTelegraph.new()
	telegraph.radius = radius
	add_child(telegraph)


## Client-visual: a SpawnEffect summon burst centered on this mob — fired on spawn + respawn so an
## appearing mob has presence instead of popping in. A SEPARATE node (renders fine), not a tween on
## the mob's own sprite (which doesn't render — see docs/replicated_props_vfx.md).
func rp_spawn_effect() -> void:
	if multiplayer.is_server():
		return
	add_child(SpawnEffect.new())
	# A body phasing in is always its OPENING form — drop any phase-2 skin swap
	# left over from the fight it just lost.
	rp_swap_skin("")
	# Rise out of the ground if this skin ships an emerge clip (the death collapse
	# played backwards). Guarded on has_animation rather than letting
	# rp_play_skin_anim's fallback run: every other mob would swing on spawn.
	if animated_sprite != null and animated_sprite.sprite_frames != null \
			and animated_sprite.sprite_frames.has_animation(&"emerge"):
		rp_play_skin_anim(&"emerge", SPAWN_FREEZE_S)


## Client-visual: replace the body's SpriteFrames mid-fight (a boss phase form).
## An empty [param path] restores the skin it spawned with.
##
## Works because the swap keeps every CLIP NAME identical — the locomotion
## AnimationTree drives idle/run/death by name, so it never learns the art
## changed and no state machine needs touching.
func rp_swap_skin(path: String) -> void:
	if multiplayer.is_server() or animated_sprite == null:
		return
	if _skin_base_frames == null:
		_skin_base_frames = animated_sprite.sprite_frames
	var next: SpriteFrames = _skin_base_frames
	if not path.is_empty():
		next = load(path) as SpriteFrames
		if next == null:
			return
	if next == animated_sprite.sprite_frames:
		return
	# Keep the clip and its progress across the swap, or the body visibly resets
	# to frame 0 of idle in the middle of whatever it was doing.
	var clip: StringName = animated_sprite.animation
	var frame_i: int = animated_sprite.frame
	var progress: float = animated_sprite.frame_progress
	animated_sprite.sprite_frames = next
	if next.has_animation(clip):
		animated_sprite.animation = clip
		animated_sprite.set_frame_and_progress(mini(frame_i, next.get_frame_count(clip) - 1), progress)




## Replay one of this npc's rp_ visual methods on every client. Lets an external
## orchestrator (a BossController) drive the body's telegraphs without reaching
## into its private prop id. Server-side; no-op if not yet baked into a container.
func replicate_visual(method: StringName, args: Array) -> void:
	if container == null:
		return
	if _prop_id < 0:
		_prop_id = container.child_id_of_node(self)
	if _prop_id < 0:
		return
	container.queue_op(_prop_id, method, args)


## Per-SPAWN skill-XP override (0 = fall through to the archetype). Set by a
## spawner that inflates max_health for difficulty but must NOT let the payout
## inflate with it — a party-scaled Boss Hunt boss pays its AUTHORED rate, so a
## four-player run can't farm 3x the mastery/slayer XP a solo run does.
## Deliberately a per-instance field: writing enemy_data.combat_skill_xp_override
## would rewrite the shared EnemyTypeResource for every spawn of the archetype.
var skill_xp_override: int = 0


## Weapon-mastery / Slayer XP this body is worth on death.
##
## Prefers the authored override on its EnemyTypeResource; otherwise derives from
## the LIVE stat block rather than the resource's, so a mob whose health was
## scaled up by apply_difficulty() still pays out for the harder kill.
func combat_skill_xp() -> int:
	if skill_xp_override > 0:
		return skill_xp_override
	if enemy_data != null and enemy_data.combat_skill_xp_override > 0:
		return enemy_data.combat_skill_xp_override
	return EnemyTypeResource.combat_skill_xp_for(max_health, armor)


## Scale this mob's combat stats for a harder run (dungeon Hard mode): multiply max
## health (and refill to it) + attack power. Generic — any spawner can call it after
## the mob's data has been applied.
func apply_difficulty(health_mult: float, damage_mult: float) -> void:
	var max_h: float = stats_component.get_stat(Stat.HEALTH_MAX) * health_mult
	apply_max_health(max_h)
	stats_component.set_stat(Stat.AD, stats_component.get_stat(Stat.AD) * damage_mult)
	stats_component.set_stat(Stat.AP, stats_component.get_stat(Stat.AP) * damage_mult)


## Pin max (and current) health to an absolute value — dungeon finales that
## party-scale HP instead of stacking multipliers.
func apply_max_health(hp: float) -> void:
	max_health = hp
	stats_component.set_stat(Stat.HEALTH_MAX, hp)
	stats_component.set_stat(Stat.HEALTH, hp)


## Client-visual: replay the weapon shot so the projectile flies on every client.
func rp_shoot(direction: Vector2) -> void:
	if multiplayer.is_server():
		return
	var mounted: Weapon = equipment_component.mounted_nodes.get(&"weapon")
	if mounted:
		mounted.auto_attack(direction)


## Client-visual: replay a registry ability cast (the sorcerer's heal bolt) so
## its projectile flies on every client — client-side projectiles are cosmetic
## by design (only the server's applies the effect). Resolved by slug so the op
## stays readable in logs.
func rp_cast_ability(ability_slug: StringName, direction: Vector2) -> void:
	if multiplayer.is_server():
		return
	var cast: AbilityResource = ContentRegistryHub.load_by_slug(&"abilities", ability_slug) as AbilityResource
	if cast != null:
		cast.auto_use(self, direction)


## Client-visual: a lingering hazard disc (spore cloud) pinned where the mob
## died — the damage is the server's HazardZone; this is only what it looks
## like. top_level so a later respawn teleport doesn't drag the cloud along.
func rp_hazard_zone(at: Vector2, radius: float, duration_s: float) -> void:
	if multiplayer.is_server():
		return
	var cloud: HazardCloudVisual = HazardCloudVisual.new()
	cloud.radius = radius
	cloud.duration_s = duration_s
	cloud.top_level = true
	add_child(cloud)
	cloud.global_position = at


func _debug_client_stat_changed(stat_name: StringName, value: float) -> void:
	if stat_name == &"health" or stat_name == &"health_max":
		print("[CLI NPC %s] sync %s → %.1f" % [enemy_type, stat_name, value])


## Spawn the detection-trigger Area2D as a child, sized to detection_radius
## (data-driven via EnemyTypeResource). Server-only; clients never see this.
func _build_detection_area() -> void:
	detection_area = Area2D.new()
	detection_area.name = "DetectionArea"
	# Default collision mask matches the existing scene's behaviour (all
	# layers, server filters body_entered down to Player). If you want to
	# narrow it for perf, set detection_area.collision_mask before adding.
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = float(detection_radius)
	shape.shape = circle
	detection_area.add_child(shape)
	add_child(detection_area)


# ---------------------------------------------------------------------------
# Debug visualisation
# ---------------------------------------------------------------------------

func _draw() -> void:
	if not debug_draw_ranges:
		return
	# In editor we don't have enemy_data applied yet, so fall back to the
	# resource if one is assigned. Otherwise use whatever the local vars
	# currently hold (script default or @export set on the scene root).
	var leash: float = float(max_distance_from_spawn)
	var detect_r: float = float(detection_radius)
	if Engine.is_editor_hint() and enemy_data != null:
		leash = float(enemy_data.max_distance_from_spawn)
		detect_r = float(enemy_data.detection_radius)

	# Red (inner) = detection — "danger close", entering this ring trips
	# aggro. Yellow (outer) = leash — once the mob's chase crosses this
	# ring, it disengages and returns. Inner-red matches the player
	# intuition of "red = where the mob will jump on me".
	draw_circle(Vector2.ZERO, leash, Color(1, 0.9, 0.2, 0.08))
	draw_arc(Vector2.ZERO, leash, 0, TAU, 64, Color(1, 0.9, 0.2, 0.6), 1.0)
	draw_circle(Vector2.ZERO, detect_r, Color(1, 0.2, 0.2, 0.10))
	draw_arc(Vector2.ZERO, detect_r, 0, TAU, 48, Color(1, 0.2, 0.2, 0.6), 1.0)


## Equips the configured weapon (server + client) by setting the slot, which mounts it.
func _equip_weapon() -> void:
	if weapon == null or weapon.slot == null:
		return
	equipment_component.slots.set(weapon.slot.key, int(weapon.get_meta(&"id", 0)))


## Called by Character.take_damage when health hits zero (server-only).
func die(killer: Character) -> void:
	# Death hooks (refactor P4): run BEFORE anything commits — an intercepting
	# behavior (second wind) revives with zero credit/state leakage, since
	# neither DEAD state, rewards, nor the died signal have fired yet. The
	# rest ride the moment for side effects (spore cloud) and let it proceed.
	# has_method guard: a behavior whose script didn't load (stale editor,
	# broken .tres) must NEVER abort die() mid-way — that's the unkillable
	# 0-HP zombie. Death always completes unless a hook DELIBERATELY says so.
	for behavior: MobBehavior in behaviors:
		if behavior != null and behavior.has_method(&"on_death") \
				and behavior.on_death(self, killer):
			return
	if DEBUG_NPC:
		printerr("[SRV NPC %s] die() killer=%s HP=%.1f state→DEAD respawn_in=%.1fs" % [
			enemy_type,
			String(killer.name) if killer else "null",
			stats_component.get_stat(Stat.HEALTH),
			respawn_delay
		])
	enemy_state = EnemyState.DEAD
	anim = Character.Animations.DEATH
	velocity = Vector2.ZERO
	targeted_player = null
	_clear_taunt()
	# Keep possible_targets so players still standing in the area are re-acquired on
	# respawn (body_entered won't re-fire for someone who never left).
	_respawn_at_ms = Time.get_ticks_msec() + int(respawn_delay * 1000.0)
	RewardService.distribute(self, _contributors, killer)
	died.emit(killer)


## Style wards (world bosses): Physical Ward wants sword/hammer/bow, Arcane Ward
## wants wand/book. Wrong category is reduced, not zero.
func incoming_damage_factor(
	attacker: Character,
	damage_type: StringName = CombatHit.DAMAGE_PHYSICAL
) -> float:
	var factor: float = super.incoming_damage_factor(attacker, damage_type)

	# Scripted encounters (Ossuran) gate damage by COMBAT STYLE and by phase
	# invulnerability. Checked before the style ward and independently of it:
	# the parser handles non-player damage itself (it passes styleless hits
	# through untouched), so unlike the ward below it must not be short-circuited
	# on `attacker is not Player` — a phase-immune boss has to be immune to a
	# damage-over-time tick as well as to a sword.
	var parser: AttackParser = _attack_parser()
	if parser != null:
		factor *= parser.damage_factor(attacker, 0.0, damage_type)

	if attacker is not Player:
		return factor
	var brain: BossController = _boss_brain()
	if brain == null:
		return factor
	return factor * brain.style_ward_factor(attacker as Player)


func _boss_brain() -> BossController:
	for child: Node in get_children():
		if child is BossController:
			return child as BossController
	return null


## The scripted-encounter damage gate, if this body has one. Attached as a child
## by [OssuranArena] on spawn — same pattern as [BossController] above, so a
## plain mob pays one null child-scan and nothing else.
func _attack_parser() -> AttackParser:
	for child: Node in get_children():
		if child is AttackParser:
			return child as AttackParser
	return null


## Server-side override that:
## 1. Calls super to actually apply the damage.
## 2. Emits was_attacked so nearby pack-mates aggro the attacker.
## 3. Engages an IDLE mob that's been hit from outside detection range
##    (a far-away snipe wouldn't trigger CHASE through detection_area).
## 4. Pre/post logs gated on DEBUG_NPC for future bug triage.
func take_damage(amount: float, attacker: Character = null, damage_type: StringName = CombatHit.DAMAGE_PHYSICAL, effect_kind: StringName = &"") -> void:
	# Ally protection: a guild guard ignores damage from its own guild's members.
	# Blocking here (before super) means no HP loss, no death, and no hit feedback
	# (numbers/flash/sound all hang off the HP-decrease push).
	if owner_guild_id > 0 and attacker is Player:
		var ap: Player = attacker
		if ap.player_resource != null and ap.player_resource.active_guild_id == owner_guild_id:
			return

	if not GameMode.is_world_server():
		super.take_damage(amount, attacker, damage_type, effect_kind)
		return

	# Participation: tally each player's damage BEFORE applying it, so a killing
	# blow is already counted when super → die() distributes the reward.
	# Keyed by persistent player_id (not peer) so a reconnect still shares the kill.
	if not is_dead and amount > 0.0 and attacker is Player and (attacker as Player).player_resource != null:
		var contributor_id: int = int((attacker as Player).player_resource.player_id)
		if contributor_id > 0:
			_contributors[contributor_id] = _contributors.get(contributor_id, 0.0) + amount

	var was_alive: bool = not is_dead
	var pre_h: float = 0.0
	if DEBUG_NPC:
		pre_h = stats_component.get_stat(Stat.HEALTH)
		printerr("[SRV NPC %s] take_damage(%.1f) pre: HP=%.1f is_dead=%s state=%d attacker=%s" % [
			enemy_type, amount, pre_h, is_dead, enemy_state,
			String(attacker.name) if attacker else "null"
		])

	super.take_damage(amount, attacker, damage_type, effect_kind)
	if amount > 0.0:
		_mark_combat_activity()

	if DEBUG_NPC:
		var post_h: float = stats_component.get_stat(Stat.HEALTH)
		if pre_h == post_h:
			printerr("[SRV NPC %s] take_damage(%.1f) NO-OP: HP unchanged (likely is_dead guard)" % [enemy_type, amount])
		else:
			printerr("[SRV NPC %s] take_damage(%.1f) post: HP=%.1f → %.1f is_dead=%s state=%d" % [
				enemy_type, amount, pre_h, post_h, is_dead, enemy_state
			])

	# Engagement triggers — only when the hit actually landed on a living
	# mob. Even if super killed us in the same call, was_alive captures the
	# pre-state so allies still get a "your buddy died fighting <attacker>"
	# notification and aggro the killer. Zero-damage calls (gather-tool arcs
	# that historically still queried HurtBoxes) must NOT pull aggro.
	if not was_alive or attacker == null or amount <= 0.0:
		return
	# Pack-call: nearby HostileNpcs in detection_area pick this up.
	was_attacked.emit(attacker)
	# Self-engagement: a far-away snipe can't reach us through detection_area
	# (the attacker stays outside the ring) — so the take_damage path is
	# the only place we get to react. Don't re-target if we're already
	# chasing / attacking someone; don't break RETURNING / DEAD.
	if is_dead:
		return
	if enemy_state == EnemyState.RETURNING or enemy_state == EnemyState.DEAD:
		return
	# A roar outranks retaliation: the whole point is that the DPS can hit the
	# boss without pulling it off the tank.
	if is_taunted():
		return
	if targeted_player != null:
		return
	if attacker is Player and not (attacker as Player).is_dead and _is_hostile_to(attacker as Player):
		targeted_player = attacker as Player
		enemy_state = EnemyState.CHASE


## Drops the current target and heads home (used when the target dies or is lost).
## A committed mob never leashes home MID-FIGHT — it holds its ground and its
## current HP, re-aggroing via _find_targets the moment a player is back in reach,
## so you can't shed a boss by stepping over an invisible line. Only once the
## fight has been over for the full OUT_OF_COMBAT_REGEN_DELAY_MS does
## _process_idle_recovery walk it home to reset.
##
## Commitment is either authored (enemy_data.leashes == false: bosses) OR stamped
## at spawn by [method RoomNode.make_dungeon_mob] / boss enrage adds, which set
## [member max_distance_from_spawn] to [constant NO_LEASH_DISTANCE]. Checking only
## the resource left dungeon/summoned trash (yeti adds, etc.) still leashing home
## and refusing to re-aggro mid-fight.
func _is_committed() -> bool:
	if max_distance_from_spawn >= NO_LEASH_DISTANCE:
		return true
	return enemy_data != null and not enemy_data.leashes


## Server: force-aggro the nearest living hostile player in this instance. Used by
## boss enrage summons so passive archetypes (chase_on_area=false world trash)
## still join the fight the moment they spawn instead of idling until hit.
func engage_nearest_player() -> void:
	if not multiplayer.is_server() or is_dead:
		return
	chase_on_area = true
	_resync_possible_targets()
	var best: Player = null
	var best_d: float = INF
	for candidate: Player in possible_targets:
		if not _is_target_valid(candidate) or not _is_hostile_to(candidate):
			continue
		var d: float = global_position.distance_squared_to(candidate.global_position)
		if d < best_d:
			best_d = d
			best = candidate
	# Detection area may still be empty on the spawn frame (physics hasn't
	# flushed overlaps yet) — fall back to every player in the instance.
	if best == null and container != null:
		var map: Node = container.get_parent()
		var instance: Node = map.get_parent() if map != null else null
		if instance != null:
			var roster: Variant = instance.get("players_by_peer_id")
			if roster is Dictionary:
				for peer_id: Variant in roster:
					var p: Player = roster[peer_id] as Player
					if not _is_target_valid(p) or not _is_hostile_to(p):
						continue
					var d2: float = global_position.distance_squared_to(p.global_position)
					if d2 < best_d:
						best_d = d2
						best = p
	if best == null:
		return
	if not possible_targets.has(best):
		possible_targets.append(best)
	targeted_player = best
	enemy_state = EnemyState.CHASE


func _abandon_target() -> void:
	if _hold_taunt():
		return
	targeted_player = null
	enemy_state = EnemyState.IDLE if _is_committed() else EnemyState.RETURNING


func _process_death() -> void:
	if Time.get_ticks_msec() < _respawn_at_ms:
		return
	# Single-life mobs — guild defenders AND any enemy_data.respawns == false
	# (dungeon mobs, one-off bosses) — despawn instead of respawning. All are
	# dynamic props.
	if owner_guild_id > 0 or not respawns:
		container.despawn_dynamic(_prop_id)
		return
	if DEBUG_NPC:
		printerr("[SRV NPC %s] _process_death respawn START: HP=%.1f HP_MAX=%.1f is_dead=%s state=%d" % [
			enemy_type, stats_component.get_stat(Stat.HEALTH), stats_component.get_stat(Stat.HEALTH_MAX), is_dead, enemy_state
		])
	# Respawn at the original spot, full health, idle.
	global_position = spawn_position
	# Defensive: re-derive HEALTH_MAX from the archetype if it got into a
	# bad (zero) state somewhere. Without this, a HEALTH_MAX=0 leaves the
	# NPC at HEALTH=0 after respawn — visible as the "zombie NPC" bug where
	# the bar reads empty client-side and any hit immediately re-kills the
	# mob in take_damage. Cheap and idempotent in the healthy path.
	var hmax: float = stats_component.get_stat(Stat.HEALTH_MAX)
	if hmax <= 0.0:
		# common/ can't reference ServerLog (source/server/* is stripped from
		# the client export filter). printerr lands in stderr → journalctl
		# picks it up on the live box, which is where you'd look anyway.
		printerr("NPC %s respawned with HEALTH_MAX=%f, restoring to archetype max_health=%d" % [enemy_type, hmax, max_health])
		hmax = float(max_health)
		stats_component.set_stat(Stat.HEALTH_MAX, hmax)
	stats_component.set_stat(Stat.HEALTH, hmax)

	# Diagnostic for "zombie NPC: bar empty, can't damage" — you confirmed
	# HEALTH_MAX is intact and only HEALTH is 0 on the bar. So the question
	# is whether the server wrote HEALTH=hmax here and got eaten somewhere,
	# or whether write itself didn't take. Print the post-write value so
	# the next repro shows which side of the boundary the issue is on.
	var post_h: float = stats_component.get_stat(Stat.HEALTH)
	if post_h <= 0.0:
		printerr("NPC %s respawn: HEALTH wrote=%f got=%f HEALTH_MAX=%f — zombie forming" % [enemy_type, hmax, post_h, stats_component.get_stat(Stat.HEALTH_MAX)])
	is_dead = false
	_clear_wander_leg(Time.get_ticks_msec(), true)
	enemy_state = EnemyState.IDLE
	_contributors.clear() # fresh life — past damage no longer counts for rewards
	behavior_state.clear() # fresh scratch too: lunge cooldowns, spent second winds…
	# Push the respawn position NOW (the freeze below skips the normal per-frame sync) so the spawn
	# FX lands on the mob at its spawn point, not at wherever it happened to die.
	_process_synchronization()
	# Summon burst + brief hold so a respawned mob phases in instead of blinking + instantly chasing.
	action_root_until_ms = Time.get_ticks_msec() + int(SPAWN_FREEZE_S * 1000.0)
	replicate_visual(&"rp_spawn_effect", [])
	if DEBUG_NPC:
		printerr("[SRV NPC %s] _process_death respawn END: HP=%.1f is_dead=%s state=%d" % [
			enemy_type, stats_component.get_stat(Stat.HEALTH), is_dead, enemy_state
		])


## Client-only click target for Attack (left-click / tap) and the context menu
## (right-click).
func _build_client_click_area() -> void:
	if has_node(^"ClickArea"):
		return
	var area: ClickableArea = ClickableArea.new()
	area.name = "ClickArea"
	var collision: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	var volume: Vector2 = _combat_volume_size()
	rect.size = volume
	collision.shape = rect
	collision.position = Vector2(0.0, -volume.y * 0.5)
	area.add_child(collision)
	add_child(area)
	area.clicked.connect(_on_client_clicked)
	area.right_clicked.connect(_on_client_right_clicked)
	area.mouse_entered.connect(_set_hostile_hover.bind(true))
	area.mouse_exited.connect(_set_hostile_hover.bind(false))
	area.tree_exiting.connect(_set_hostile_hover.bind(false))


## The WALK collider (the little 12x8 box at the feet) is the same size for a
## slime and for a boss, so a boss walked until its feet touched a wall and the
## other ~130px of drawn body sat inside it — reading as "the boss is in the
## wall". Widen the walk box with the drawn body so a large body stops further
## out.
##
## BOSSES ONLY. Trash keeps the stock box: two thirds of the roster is drawn at
## some scale or other, and quietly growing every one of their colliders risks
## a mob wedging in a corridor it has always fitted through. Bosses fight in
## open rooms, which is where the problem actually shows.
##
## Capped at 2x (24x16, still under one 16px tile).
const MAX_BODY_COLLIDER_SCALE: float = 2.0


func _scale_body_to_sprite() -> void:
	if enemy_data == null or not enemy_data.is_boss:
		return
	var shape_node: CollisionShape2D = get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		return
	var factor: float = clampf(body_scale(), 1.0, MAX_BODY_COLLIDER_SCALE)
	if is_equal_approx(factor, 1.0):
		return # keep the shared shape resource untouched
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12.0, 8.0) * factor
	shape_node.shape = rect


## Grow the shared HurtBox to match the (optionally enlarged) sprite. Nav body
## stays tiny so the mob can still path into melee range.
func _scale_hurtbox_to_sprite() -> void:
	var shape_node: CollisionShape2D = get_node_or_null(^"HurtBox/CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		return
	var volume: Vector2 = _combat_volume_size()
	var base: Vector2 = Vector2(16.0, 32.0)
	# Skip no-op for normal-sized trash (keeps shared shape resource intact).
	if volume.x <= base.x * 1.15 and volume.y <= base.y * 1.15:
		return
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = volume
	shape_node.shape = rect
	shape_node.position = Vector2(0.0, -volume.y * 0.5)


## Hit / click volume from idle frame × visual_scale (falls back to a padded
## default so tiny skins don't shrink below the stock hurtbox).
func _combat_volume_size() -> Vector2:
	var vs: float = 1.0
	if enemy_data != null:
		vs = maxf(1.0, enemy_data.visual_scale)
	var frame: Vector2 = Vector2(48.0, 64.0)
	if animated_sprite != null and animated_sprite.sprite_frames != null:
		var frames: SpriteFrames = animated_sprite.sprite_frames
		var anim: StringName = &"idle" if frames.has_animation(&"idle") else animated_sprite.animation
		if frames.has_animation(anim):
			var tex: Texture2D = frames.get_frame_texture(anim, 0)
			if tex != null:
				frame = tex.get_size()
	# Cover most of the drawn sprite — Mecha Golem (~65×64 @ 2.2×) → ~120×127.
	var sized: Vector2 = Vector2(frame.x * vs * 0.85, frame.y * vs * 0.9)
	return Vector2(maxf(36.0, sized.x), maxf(48.0, sized.y))


func _on_client_clicked() -> void:
	if is_dead or enemy_state == EnemyState.DEAD or enemy_state == EnemyState.REVIVING:
		return
	if not is_instance_valid(ClientState) or ClientState.local_player == null:
		return
	ClientState.local_player.start_hostile_attack(self)
	get_viewport().set_input_as_handled()


func _set_hostile_hover(on: bool) -> void:
	if not GameMode.is_client() or on == _hostile_hovered:
		return
	if on and (is_dead or enemy_state == EnemyState.DEAD or enemy_state == EnemyState.REVIVING):
		return
	_hostile_hovered = on
	if is_instance_valid(ClientState):
		ClientState.world_hostiles_hovered += 1 if on else -1


func _on_client_right_clicked() -> void:
	if is_dead or not is_instance_valid(ClientState):
		return
	ClientState.hostile_context_requested.emit(self)


## If npc is engaged (chasing or attacking), stops and starts returning to
## the spawn position. Accepts ATTACK too so the new leash check in
## _process_attack can route through here without re-implementing the
## possible_targets / target cleanup.
func stop_chase() -> void:
	if enemy_state != EnemyState.CHASE and enemy_state != EnemyState.ATTACK: return
	# A roared mob does not leash off the tank. Kiting it out of its own leash
	# ring was the cheapest way to shed a taunt, which would have made the roar
	# strictly worse than walking backwards.
	if _hold_taunt():
		return
	enemy_state = EnemyState.IDLE if _is_committed() else EnemyState.RETURNING
	possible_targets.erase(targeted_player)
	targeted_player = null
