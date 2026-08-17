class_name QuestBossArena
extends Node2D
## One-life story-boss spawn inside a private quest arena. Server-authoritative.
## Unlike BossHuntArena this does not respawn and does not bank Hunt Chest loot.

@export var boss_spawn: Marker2D

var _boss: HostileNpc = null
var _running: bool = false
var _cleared: bool = false


func _ready() -> void:
	set_process(false)


func begin(enemy_slug: StringName) -> void:
	if not GameMode.is_world_server() or enemy_slug == &"":
		return
	_running = true
	_cleared = false
	_spawn_boss(enemy_slug)


func stop() -> void:
	_running = false
	if is_instance_valid(_boss):
		var map: Map = Map.of(self)
		var container: ReplicatedPropsContainer = map.replicated_props_container if map != null else null
		var child_id: int = container.child_id_of_node(_boss) if container != null else -1
		if child_id >= 0:
			container.despawn_dynamic(child_id)
		else:
			_boss.queue_free()
	_boss = null


func _spawn_boss(enemy_slug: StringName) -> void:
	var map: Map = Map.of(self)
	if map == null or map.replicated_props_container == null:
		push_warning("QuestBossArena: no ReplicatedPropsContainer — cannot spawn.")
		return
	var container: ReplicatedPropsContainer = map.replicated_props_container
	var at: Vector2 = boss_spawn.global_position if boss_spawn != null else global_position
	var mob: Node = container.spawn_dynamic(
		ReplicatedPropsContainer.SCENE_HOSTILE_NPC,
		container.to_local(at),
		{"enemy_type_slug": enemy_slug}
	)
	var npc: HostileNpc = mob as HostileNpc
	if npc == null:
		return
	npc.respawns = false
	npc.max_distance_from_spawn = HostileNpc.NO_LEASH_DISTANCE
	var brain: BossController = BossController.new()
	brain.name = "BossController"
	brain.boss = npc
	npc.add_child(brain)
	npc.action_root_until_ms = Time.get_ticks_msec() + int(HostileNpc.SPAWN_FREEZE_S * 1000.0)
	npc.replicate_visual(&"rp_spawn_effect", [])
	_boss = npc
	npc.died.connect(_on_boss_died.bind(npc), CONNECT_ONE_SHOT)


func _on_boss_died(_killer: Character, npc: HostileNpc) -> void:
	if npc != _boss or _cleared:
		return
	_cleared = true
	_boss = null
	QuestBossService.on_boss_killed(_instance())


func _instance() -> Node:
	var map: Map = Map.of(self)
	return map.get_parent() if map != null else null
