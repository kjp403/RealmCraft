class_name QuestBossService
## Server-only: a quest giver sends ONE player into a private arena to fight the
## story boss. Sibling of DungeonService / BossHuntService — private
## prepare_instance, not a shared WarpInteraction shard. Solo only.
##
## Leave / death / recall dump the player back at the giver. Retry is allowed
## until the matching KILL objective is complete.

const ARENA_INSTANCE: StringName = &"quest_boss_arena"
const EJECT_DELAY_S: float = 6.0

# peer_id -> { instance, origin_instance, origin_pos, enemy_type, slug }
static var _by_peer: Dictionary[int, Dictionary] = {}
# private instance node name -> peer_id
static var _instance_to_peer: Dictionary[String, int] = {}
# peer_ids currently being auto-ejected after a kill (skip the "left" toast).
static var _ejecting: Dictionary[int, bool] = {}


## True when [param instance] is a live story-boss arena.
static func is_quest_boss_instance(instance: Node) -> bool:
	return instance != null and _instance_to_peer.has(str(instance.name))


## True when [param instance] is still an active run's return point. Keeps
## instance_manager.unload_unused_instances from freeing the open-world biome
## shard a solo fight started in — that shard's connected_peers hits zero the
## moment the player is switched into the private arena, so without this it
## could be reaped mid-fight (its 20s idle timer is far shorter than most boss
## fights). eject_to_origin then found origin invalid and dumped the player at
## Guild Hall instead of back at the quest giver.
static func is_pinned_origin(instance: Node) -> bool:
	for run: Dictionary in _by_peer.values():
		if run.get("origin_instance", null) == instance:
			return true
	return false


## Recall from a story fight should land at the giver, not Guild Hall.
## Returns true when this peer was in an arena and the eject was scheduled.
static func redirect_recall(peer_id: int) -> bool:
	if not _by_peer.has(peer_id):
		return false
	eject_to_origin(peer_id)
	return true


## Start a private one-life fight for [param player] against [param enemy_slug].
## Caller has already range-checked and gated the quest. Server-only.
static func start_fight(
	player: Player,
	from_instance: Node,
	origin_pos: Vector2,
	enemy_slug: StringName
) -> bool:
	if WorldServer.curr == null or player == null or from_instance == null:
		return false
	if player.player_resource == null:
		return false
	var peer_id: int = int(player.player_resource.current_peer_id)
	if peer_id <= 0:
		return false
	if _by_peer.has(peer_id):
		return false
	var arena_res: InstanceResource = _arena_resource()
	if arena_res == null:
		push_warning("QuestBossService: no '%s' instance resource." % ARENA_INSTANCE)
		return false
	var instance_manager: Node = WorldServer.curr.instance_manager
	var instance: Node = instance_manager.prepare_instance(arena_res)
	_by_peer[peer_id] = {
		"instance": instance,
		"origin_instance": from_instance,
		"origin_pos": origin_pos,
		"enemy_type": enemy_slug,
	}
	_instance_to_peer[str(instance.name)] = peer_id
	instance.ready.connect(
		func() -> void: _enter_fight(peer_id, enemy_slug),
		CONNECT_ONE_SHOT
	)
	instance_manager.add_child(instance, true)
	return true


static func _enter_fight(peer_id: int, enemy_slug: StringName) -> void:
	var run: Dictionary = _by_peer.get(peer_id, {})
	if run.is_empty() or WorldServer.curr == null:
		return
	var instance: Node = run.get("instance", null)
	if instance == null:
		return
	var instance_manager: Node = WorldServer.curr.instance_manager
	var current: Node = instance_manager.find_instance_for_peer(peer_id)
	if current == null:
		_forget(peer_id)
		return
	var player: Player = current.get_player(peer_id) as Player
	if player == null:
		_forget(peer_id)
		return
	instance_manager.player_switch_instance(instance, 0, player, current)
	player.restore_full()
	WorldServer.curr.get_tree().create_timer(1.5).timeout.connect(
		func() -> void:
			if not _by_peer.has(peer_id):
				return
			var arena_node: QuestBossArena = _arena_node(instance)
			if arena_node != null:
				arena_node.begin(enemy_slug)
			var title: String = _boss_title(enemy_slug)
			WorldServer.curr.data_push.rpc_id(peer_id, &"quest_boss.entered", {
				"boss": title,
			}),
		CONNECT_ONE_SHOT
	)


## Story boss died — linger, then send the player back to the giver.
static func on_boss_killed(instance: Node) -> void:
	if instance == null or WorldServer.curr == null:
		return
	var peer_id: int = _instance_to_peer.get(str(instance.name), 0)
	if peer_id <= 0:
		return
	var run: Dictionary = _by_peer.get(peer_id, {})
	var title: String = _boss_title(StringName(str(run.get("enemy_type", &""))))
	WorldServer.curr.data_push.rpc_id(peer_id, &"quest_boss.cleared", {"boss": title})
	_ejecting[peer_id] = true
	WorldServer.curr.get_tree().create_timer(EJECT_DELAY_S).timeout.connect(
		func() -> void: eject_to_origin(peer_id),
		CONNECT_ONE_SHOT
	)


## Send the peer back to the giver (or Guild Hall if that instance is gone).
static func eject_to_origin(peer_id: int) -> void:
	if WorldServer.curr == null:
		return
	var run: Dictionary = _by_peer.get(peer_id, {})
	if run.is_empty():
		return
	var arena: Node = run.get("instance", null)
	var origin: Node = run.get("origin_instance", null)
	var origin_pos: Vector2 = run.get("origin_pos", Vector2.ZERO)
	var instance_manager: Node = WorldServer.curr.instance_manager
	var current: Node = instance_manager.find_instance_for_peer(peer_id)
	var player: Player = current.get_player(peer_id) as Player if current != null else null
	if player != null:
		player.restore_full()
		if player.is_dead:
			player.revive()
	var arena_node: QuestBossArena = _arena_node(arena)
	if arena_node != null:
		arena_node.stop()
	# Forget before a hub fallback so recall_player does not redirect back here.
	if is_instance_valid(origin) and origin != current:
		instance_manager.teleport_peer_to(peer_id, origin, origin_pos)
		on_player_left(peer_id, arena)
	else:
		on_player_left(peer_id, arena)
		instance_manager.recall_player(peer_id)


## A player left the arena (recall, death eject, exit pad, /goto). No-op for any
## other instance. Server-only.
static func on_player_left(peer_id: int, left_instance: Node) -> void:
	if left_instance == null:
		return
	var key: String = str(left_instance.name)
	if _instance_to_peer.get(key, 0) != peer_id:
		return
	if WorldServer.curr != null and not _ejecting.get(peer_id, false):
		WorldServer.curr.data_push.rpc_id(peer_id, &"quest_boss.left", {})
	_forget(peer_id)


static func on_peer_disconnected(peer_id: int) -> void:
	if _by_peer.has(peer_id):
		var run: Dictionary = _by_peer[peer_id]
		_forget(peer_id)
		var arena_node: QuestBossArena = _arena_node(run.get("instance", null))
		if arena_node != null:
			arena_node.stop()


static func _forget(peer_id: int) -> void:
	var run: Dictionary = _by_peer.get(peer_id, {})
	var instance: Node = run.get("instance", null)
	if instance != null:
		_instance_to_peer.erase(str(instance.name))
	_by_peer.erase(peer_id)
	_ejecting.erase(peer_id)


static func _arena_resource() -> InstanceResource:
	if WorldServer.curr == null:
		return null
	return WorldServer.curr.instance_manager.instance_collection.get(ARENA_INSTANCE, null)


static func _arena_node(instance: Node) -> QuestBossArena:
	if instance == null or instance.get("instance_map") == null:
		return null
	for child: Node in instance.instance_map.get_children():
		if child is QuestBossArena:
			return child as QuestBossArena
	return null


static func _boss_title(slug: StringName) -> String:
	if slug.is_empty():
		return "the boss"
	var et: EnemyTypeResource = ContentRegistryHub.load_by_slug(&"enemy_types", slug) as EnemyTypeResource
	if et != null and not et.display_name.is_empty():
		return et.display_name
	return String(slug).capitalize()
