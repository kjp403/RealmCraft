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

	var boss: HostileNpc = spawn_container.spawn_dynamic(
		ReplicatedPropsContainer.SCENE_HOSTILE_NPC,
		spawn_container.to_local(position),
		{"enemy_type_slug": slug}
	) as HostileNpc
	if boss == null:
		return "Failed to spawn the world boss (slug '%s', is it registered?)." % slug

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
	boss.replicate_visual(&"rp_spawn_effect", [])

	_active_boss = boss
	_event_instance = instance
	boss.died.connect(_on_world_boss_died)

	# Server-wide rally — name WHERE it is so players can actually find it.
	var where: String = "the world"
	if instance != null and instance.instance_resource != null:
		where = String(instance.instance_resource.instance_name)
	# (The combat music cue is fired by the boss's own BossController on spawn.)
	_announce("A world boss has risen in %s: %s! Rally and bring it down. Everyone who fights shares the spoils." % [where, boss.display_name])
	return "" # success — the server-wide announce IS the admin's confirmation (skip the echo)


## Admin abort: dispel the active world boss WITHOUT distributing rewards (use when a
## fight bugs out). A real kill still rewards everyone via RewardService. Server-only.
static func end_world_boss() -> String:
	if not is_instance_valid(_active_boss):
		return "No world boss is active."
	var boss: HostileNpc = _active_boss
	var boss_name: String = boss.display_name
	_active_boss = null # clear first so the died handler can't also fire

	# Remove the body cleanly (replicated to clients). Despawn does NOT emit `died`,
	# so no rewards are handed out — this is an abort, not a kill.
	if boss.container != null:
		var child_id: int = boss.container.child_id_of_node(boss)
		if child_id >= 0:
			boss.container.despawn_dynamic(child_id)
		else:
			boss.queue_free()
	else:
		boss.queue_free()

	_announce("%s has been dispelled by an admin." % boss_name)
	# Abort = boss removed without a death, so the brain's victory cue never fires —
	# tell clients to drop the combat track and return to area music.
	BossController.push_boss_music(_event_instance, "end")
	_event_instance = null
	return "" # success — the dispel announce above is the confirmation (skip the echo)


## Boss down: the rewards were already split by RewardService inside
## HostileNpc.die(), so here we just trumpet the win server-wide and clear the slot.
static func _on_world_boss_died(_killer: Character) -> void:
	var boss_name: String = _active_boss.display_name if is_instance_valid(_active_boss) else "The world boss"
	# (The victory sting is fired by the boss's own BossController on its death signal.)
	_announce("%s has fallen! The spoils are shared among all who fought it." % boss_name)
	_active_boss = null
	_event_instance = null


## System message to every connected player across all instances — a world event
## concerns the whole server. Same reach as /broadcast.
static func _announce(text: String) -> void:
	var ws: WorldServer = WorldServer.curr
	if ws == null or _event_instance == null:
		return
	for peer_id: int in ws.connected_players:
		var pr: PlayerResource = ws.connected_players[peer_id]
		if pr != null:
			ws.chat_service.push_system_to_player(_event_instance, pr.player_id, text)
