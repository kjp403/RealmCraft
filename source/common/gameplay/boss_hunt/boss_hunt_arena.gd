class_name BossHuntArena
extends Node2D
## The farm loop inside a Boss Hunt instance: spawn the contracted boss on
## [member boss_spawn], and when it dies, put another one there after the
## target's respawn delay. Runs until BossHuntService tears the instance down at
## the 30-minute mark.
##
## Server-authoritative — the whole script no-ops off the world server; the
## spawned body syncs itself through the map's ReplicatedPropsContainer like any
## other mob.
##
## Boss setup mirrors RoomNode._spawn_marker_mob (no-leash, no respawn, a
## BossController brain, party-scaled HP) with two deliberate differences: the
## body KEEPS its loot and XP (the whole mode is farming it), and it is stamped
## with [constant HUNT_LOOT_META] so RewardService banks the roll into each
## participant's Hunt Chest instead of scattering it on the floor.

## Metadata key RewardService looks for to route a kill's loot to the Hunt Chest.
const HUNT_LOOT_META: StringName = &"boss_hunt_loot"

## Where the boss appears. Author it near the middle of the room, away from the
## entrance so a fresh spawn can't land on a player who just walked in.
@export var boss_spawn: Marker2D

## The contract being farmed. Set by BossHuntService once the instance is ready.
var target: BossHuntTarget

## The living boss, or null between kills.
var _boss: HostileNpc = null
## ticks_msec at which the next boss spawns; 0 = not waiting on a respawn.
var _respawn_at_ms: int = 0
## Bosses killed so far — reported in the wrap-up.
var _kills: int = 0
var _running: bool = false


func _ready() -> void:
	set_process(false)


## Start the loop for [param contract]. Called by BossHuntService after every
## member has been switched into the instance.
func begin(contract: BossHuntTarget) -> void:
	if not GameMode.is_world_server() or contract == null:
		return
	target = contract
	_running = true
	_kills = 0
	set_process(true)
	_spawn_boss()


## Stop spawning and clear the field (instance teardown / timer expiry). The body
## is despawned THROUGH the container, not queue_free'd: the party is still
## standing there for the eject delay, and a locally-freed node would leave a
## ghost boss on every client.
func stop() -> void:
	_running = false
	set_process(false)
	_respawn_at_ms = 0
	if is_instance_valid(_boss):
		var map: Map = Map.of(self)
		var container: ReplicatedPropsContainer = map.replicated_props_container if map != null else null
		var child_id: int = container.child_id_of_node(_boss) if container != null else -1
		if child_id >= 0:
			container.despawn_dynamic(child_id)
		else:
			_boss.queue_free()
	_boss = null


func kills() -> int:
	return _kills


func _process(_delta: float) -> void:
	if not _running or _respawn_at_ms == 0:
		return
	if Time.get_ticks_msec() < _respawn_at_ms:
		return
	_respawn_at_ms = 0
	_spawn_boss()


## Players in this instance — the party-scaling input, re-read on every spawn so
## a boss that appears after someone leaves is sized for who's left.
##
## Counts every body present, INCLUDING the dead. Death respawns you in the arena
## a few seconds later, so scaling to "who happens to be standing" would let a
## party farm easier spawns by staggering their deaths across the respawn timer.
func _player_count() -> int:
	var instance: Node = _instance()
	if instance == null:
		return 1
	return maxi(1, instance.players_by_peer_id.size())


func _spawn_boss() -> void:
	if not _running or target == null or target.enemy_type == null:
		return
	var map: Map = Map.of(self)
	if map == null or map.replicated_props_container == null:
		push_warning("BossHuntArena: no ReplicatedPropsContainer on the map — cannot spawn.")
		return
	var container: ReplicatedPropsContainer = map.replicated_props_container
	var at: Vector2 = boss_spawn.global_position if boss_spawn != null else global_position
	var mob: Node = container.spawn_dynamic(
		ReplicatedPropsContainer.SCENE_HOSTILE_NPC,
		container.to_local(at),
		{"enemy_type_slug": target.enemy_type.get_meta(&"slug", target.enemy_type.enemy_type)}
	)
	var npc: HostileNpc = mob as HostileNpc
	if npc == null:
		return

	# Single-life, no-leash — same commitment stamp a dungeon boss gets. The loop
	# owns respawning, so the body must never respawn itself on the archetype's
	# own timer (which would double up bosses).
	npc.respawns = false
	npc.max_distance_from_spawn = HostileNpc.NO_LEASH_DISTANCE
	# Loot routing flag, read in RewardService._reward.
	npc.set_meta(HUNT_LOOT_META, true)

	if not is_equal_approx(target.damage_mult, 1.0):
		npc.apply_difficulty(1.0, target.damage_mult)
	var party_hp: float = target.party_health(_player_count())
	if party_hp > 0.0:
		npc.apply_max_health(party_hp)

	# XP is HALVED (target.xp_mult) so the open-world kill stays the better one,
	# and both numbers come off the AUTHORED stat block — never the party-scaled
	# health bar above. Skill XP normally derives from live max_health, so without
	# the explicit override a four-player run would pay each member ~3x the
	# mastery/Slayer XP of a solo run purely for having a bigger boss.
	npc.xp_reward = maxi(0, roundi(float(npc.xp_reward) * target.xp_mult))
	npc.skill_xp_override = maxi(1, roundi(float(target.enemy_type.combat_skill_xp()) * target.xp_mult))

	var brain: BossController = BossController.new()
	brain.name = "BossController"
	brain.boss = npc
	npc.add_child(brain) # _ready() loads slam_damage from enemy_data...
	if target.slam_damage > 0.0:
		brain.slam_damage = target.slam_damage
	elif not is_equal_approx(target.damage_mult, 1.0):
		brain.slam_damage *= target.damage_mult # ...so scale it AFTER that load

	npc.action_root_until_ms = Time.get_ticks_msec() + int(HostileNpc.SPAWN_FREEZE_S * 1000.0)
	npc.replicate_visual(&"rp_spawn_effect", [])

	_boss = npc
	# Both callbacks are bound to THIS body and ignored once it is no longer the
	# current boss. Corpses outlive their respawn delay, so an unbound tree_exited
	# from the previous kill would land after the next boss is already up and arm a
	# second respawn on top of a living one — two bosses in the room.
	npc.died.connect(_on_boss_died.bind(npc), CONNECT_ONE_SHOT)
	# tree_exited covers a despawn with no death signal (a body freed mid-fight);
	# without it the loop would wait forever on a boss that no longer exists.
	npc.tree_exited.connect(_on_boss_gone.bind(npc))
	BossHuntService.on_boss_spawned(_instance(), npc)


func _on_boss_died(_killer: Character, npc: HostileNpc) -> void:
	if npc != _boss:
		return
	_kills += 1
	BossHuntService.on_boss_killed(_instance(), _kills)
	_arm_respawn()


func _on_boss_gone(npc: HostileNpc) -> void:
	# Only the "vanished without dying" case needs handling — a real kill already
	# armed the respawn through _on_boss_died.
	if not _running or npc != _boss:
		return
	_arm_respawn()


func _arm_respawn() -> void:
	_boss = null
	if not _running:
		return
	var delay: float = maxf(1.0, target.respawn_delay_s if target != null else 12.0)
	_respawn_at_ms = Time.get_ticks_msec() + int(delay * 1000.0)


## BossHuntArena → Map → ServerInstance.
func _instance() -> Node:
	var map: Map = Map.of(self)
	return map.get_parent() if map != null else null
