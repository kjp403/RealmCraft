class_name EventService
## Server-side orchestrator for admin-triggered live events. The first event is the
## WORLD BOSS — a beefed-up HostileNpc dropped into the live world that the whole
## server fights together.
##
## Participation rewards come FREE: a world boss is just a HostileNpc, so on death
## RewardService already splits its XP + loot across EVERY player who dealt
## meaningful damage (see reward_service.gd) — not just the last hitter. So this
## service only has to spawn the body, rally the server, and announce the result.
##
## Triggered from an in-game admin command (the master dashboard is owner-only),
## this is the seed of a broader admin event system: new event types can reuse the
## same spawn / announce / cleanup shape. Server-only; one event at a time.

## World-boss archetype — mecha_stone_golem (attack/special clips + laser/arm
## timing). world_boss.tres is a stone_golem reskin with no cast anims and
## zeroed laser/arm intervals, so it looked like a frozen statue in fights.
const WORLD_BOSS_SLUG: StringName = &"mecha_stone_golem"

## The live world boss + the instance it was rallied from (used for announces).
## Only one world boss at a time. Static — the trigger command and the death
## handler share them without needing an instance of this service.
static var _active_boss: HostileNpc = null
static var _event_instance: ServerInstance = null
## Slug of the last / current world boss — kept after death so /worldboss end can
## still sweep orphaned respawns from a pre-fix fight.
static var _active_slug: StringName = &""


## Spawn the world boss at [param position] inside [param spawn_container]'s map and
## rally the server. Returns an admin-facing feedback string. Server-only.
##
## [param slug] overrides the archetype so an in-development boss can be fought
## anywhere before it is committed to a map — any is_boss enemy type works, it
## gets the same BossController and the same shared-reward death handling.
static func start_world_boss(instance: ServerInstance, spawn_container: ReplicatedPropsContainer, position: Vector2, slug: StringName = WORLD_BOSS_SLUG) -> String:
	if not GameMode.is_world_server():
		return "World bosses can only be spawned on a world server."
	if is_instance_valid(_active_boss):
		return "A world boss (%s) is already active. Finish it first." % _active_boss.display_name
	if spawn_container == null:
		return "No spawn container here."
	# Validate the slug BEFORE spawning. An unregistered slug (a typo) still
	# spawns a body — HostileNpc just falls back to its scene defaults and you
	# get a nameless Lv 0 mob that then occupies the one boss slot until an
	# admin runs /worldboss end. Fail loudly here instead.
	var data: EnemyTypeResource = ContentRegistryHub.load_by_slug(&"enemy_types", slug) as EnemyTypeResource
	if data == null:
		return "No enemy type '%s' is registered.%s" % [slug, _slug_hint(slug)]
	if not data.is_boss:
		return "'%s' is not a boss enemy type — world bosses need is_boss." % slug

	var boss: HostileNpc = spawn_container.spawn_dynamic(
		ReplicatedPropsContainer.SCENE_HOSTILE_NPC,
		spawn_container.to_local(position),
		{"enemy_type_slug": slug}
	) as HostileNpc
	if boss == null:
		return "Failed to spawn the world boss (slug '%s', is it registered?)." % slug

	# World bosses are a one-shot event. Archetypes like Ossuran ship
	# respawns=true (open-world farm cadence); leaving that on means the body
	# sits dead for respawn_delay then walks back — while this service already
	# cleared _active_boss on died, so /worldboss end says "none active".
	boss.respawns = false
	boss.max_distance_from_spawn = HostileNpc.NO_LEASH_DISTANCE

	# mecha_stone_golem.tres defines the fight (clips + Boss tuning). Bolt on
	# the same named BossController RoomNode / Hollow use — the name matters so
	# HostileNPC._ensure_boss_brain does not attach a second brain.
	var brain: BossController = BossController.new()
	brain.name = "BossController"
	brain.boss = boss
	boss.add_child(brain)

	# Summon burst + the emerge clip, the same entrance a dungeon spawn gets via
	# RoomNode. Without it a rallied world boss simply appears, mid-crowd, with no
	# beat for anyone to react to.
	boss.action_root_until_ms = Time.get_ticks_msec() + int(HostileNpc.SPAWN_FREEZE_S * 1000.0)
	boss.replicate_visual(&"rp_spawn_effect", [])

	_active_boss = boss
	_event_instance = instance
	_active_slug = slug
	boss.died.connect(_on_world_boss_died)

	# Server-wide rally — name WHERE it is so players can actually find it.
	var where: String = "the world"
	if instance != null and instance.instance_resource != null:
		where = String(instance.instance_resource.instance_name)
	# (The combat music cue is fired by the boss's own BossController on spawn.)
	_announce("A world boss has risen in %s: %s! Rally and bring it down. Everyone who fights shares the spoils." % [where, boss.display_name])
	return "" # success — the server-wide announce IS the admin's confirmation (skip the echo)


## Best-effort "did you mean?" for a mistyped world-boss slug — scans the
## enemy_types registry for the closest registered slug. Returns "" when nothing is
## close enough to be worth suggesting.
static func _slug_hint(slug: StringName) -> String:
	var registry: ContentRegistry = ContentRegistryHub.registry_of(&"enemy_types")
	if registry == null:
		return ""
	var best: StringName = &""
	var best_score: float = 0.0
	for id: int in registry.all_ids():
		var candidate: StringName = registry.slug_from_id(id)
		var score: float = String(slug).similarity(String(candidate))
		if score > best_score:
			best_score = score
			best = candidate
	if best_score < 0.7:
		return ""
	return " Did you mean '%s'?" % best


## Admin abort: dispel the active world boss WITHOUT distributing rewards (use when a
## fight bugs out). A real kill still rewards everyone via RewardService. Server-only.
## Also sweeps orphaned bodies of the last world-boss slug (a respawns=true
## archetype that walked back after died cleared _active_boss).
static func end_world_boss() -> String:
	if not GameMode.is_world_server():
		return "World bosses can only be ended on a world server."
	var cleared: int = 0
	var boss_name: String = ""
	if is_instance_valid(_active_boss):
		var boss: HostileNpc = _active_boss
		boss_name = boss.display_name
		_active_boss = null # clear first so the died handler can't also fire
		_despawn_boss_body(boss)
		BossController.push_boss_music(_event_instance, "end")
		cleared += 1
	# Orphans from a prior kill that respawned after tracking was cleared.
	cleared += _sweep_orphan_bosses(_active_slug)
	# Pre-fix leftovers (server restarted mid-orphan, or slug never stamped):
	# sweep the known world-bossable archetypes so /worldboss end always cleans up.
	if cleared <= 0:
		for slug: StringName in [&"ossuran", WORLD_BOSS_SLUG]:
			cleared += _sweep_orphan_bosses(slug)
	if cleared > 0:
		if boss_name.is_empty():
			boss_name = "The world boss"
		_announce("%s has been dispelled by an admin." % boss_name)
	_event_instance = null
	_active_slug = &""
	if cleared <= 0:
		return "No world boss is active."
	return "" # success — dispel announce above is the confirmation


## Boss down: the rewards were already split by RewardService inside
## HostileNpc.die(), so here we just trumpet the win server-wide, despawn the
## corpse (no delayed respawn), and clear the slot.
static func _on_world_boss_died(_killer: Character) -> void:
	var boss: HostileNpc = _active_boss
	var boss_name: String = boss.display_name if is_instance_valid(boss) else "The world boss"
	# (The victory sting is fired by the boss's own BossController on its death signal.)
	_announce("%s has fallen! The spoils are shared among all who fought it." % boss_name)
	# Despawn NOW — even if the archetype says respawns=true, a world-boss event
	# must not leave a 300s corpse that then walks back as an untracked farm mob.
	if is_instance_valid(boss):
		boss.respawns = false
		_despawn_boss_body(boss)
	_active_boss = null
	_event_instance = null
	# Keep _active_slug until /worldboss end or the next start so an orphan
	# that somehow respawned can still be swept.


static func _despawn_boss_body(boss: HostileNpc) -> void:
	if boss == null or not is_instance_valid(boss):
		return
	if boss.container != null:
		var child_id: int = boss.container.child_id_of_node(boss)
		if child_id >= 0:
			boss.container.despawn_dynamic(child_id)
			return
	boss.queue_free()


## Despawn any live HostileNpc matching [param slug] under every open instance.
## Used by /worldboss end to clean up bodies that respawned after tracking dropped.
static func _sweep_orphan_bosses(slug: StringName) -> int:
	if slug == &"" or WorldServer.curr == null or WorldServer.curr.instance_manager == null:
		return 0
	var removed: int = 0
	var mgr: InstanceManagerServer = WorldServer.curr.instance_manager
	for res: InstanceResource in mgr.instance_collection.values():
		for inst: ServerInstance in res.charged_instances:
			if inst == null or inst.instance_map == null:
				continue
			var container: ReplicatedPropsContainer = inst.instance_map.replicated_props_container
			if container == null:
				continue
			var doomed: Array[HostileNpc] = []
			for child_id: Variant in container.dynamic_nodes.keys():
				var dyn: Node = container.dynamic_nodes[child_id] as Node
				var npc: HostileNpc = dyn as HostileNpc
				if npc == null:
					continue
				var match_slug: StringName = npc.enemy_type
				if match_slug == &"" and npc.enemy_data != null:
					match_slug = npc.enemy_data.enemy_type
				if match_slug == slug or npc.enemy_type_slug == slug:
					doomed.append(npc)
			for npc2: HostileNpc in doomed:
				_despawn_boss_body(npc2)
				removed += 1
	return removed


## System message to every connected player across all instances — a world event
## concerns the whole server. Same reach as /broadcast.
static func _announce(text: String) -> void:
	var ws: WorldServer = WorldServer.curr
	if ws == null or ws.instance_manager == null:
		return
	for peer_id: int in ws.connected_players:
		var pr: PlayerResource = ws.connected_players[peer_id]
		if pr == null:
			continue
		var inst: ServerInstance = _event_instance
		if inst == null:
			inst = ws.instance_manager.find_instance_for_peer(peer_id)
		if inst != null:
			ws.chat_service.push_system_to_player(inst, pr.player_id, text)
