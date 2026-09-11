class_name InstanceManagerServer
extends SubViewportContainer


const INSTANCE_COLLECTION_PATH: String = "res://source/common/gameplay/maps/instance/instance_collection/"
const GLOBAL_COMMANDS_PATH: String = "res://source/server/world/components/chat_command/global_commands/"
## Name of the InstanceResource used as the jail. Create a .tres with
## instance_name = "jail" to enable the jail system.
const JAIL_INSTANCE_NAME: String = "jail"
## Town hub the universal Recall sends players to (an InstanceResource's
## instance_name). Repointed to the tavern (2026-07-01) — it's the social hub +
## login spawn + portal room, so recall landing anywhere else undercuts it.
const RECALL_INSTANCE_NAME: String = "GuildHouse"
## Social hub players spawn at on every login AFTER their first (the tavern / guild house).
## A brand-new character's first-ever login starts in the jail cell instead — see
## _on_peer_connected.
const TAVERN_INSTANCE_NAME: String = "GuildHouse"

var loading_instances: Dictionary[InstanceResource, ServerInstance]
var instance_collection: Dictionary[String, InstanceResource]
var default_instance: InstanceResource

@export var world_server: WorldServer


func start_instance_manager() -> void:
	ServerInstance.world_server = world_server
	
	setup_global_commands_and_roles()

	set_instance_collection.call_deferred()
	world_server.multiplayer_api.peer_connected.connect(_on_peer_connected)

	# Timer which will call unload_unused_instances
	var timer: Timer = Timer.new()
	timer.wait_time = 20.0 # 20.0 is for testing, consider increasing it

	timer.autostart = true
	timer.timeout.connect(unload_unused_instances)
	add_sibling(timer)

	# Basing: territory tick — every owning guild earns +1 SG per held flag.
	# Lower this constant temporarily if you want to watch ticks land during testing.
	var territory_tick_timer: Timer = Timer.new()
	territory_tick_timer.wait_time = BasingService.TERRITORY_TICK_SECONDS
	territory_tick_timer.autostart = true
	territory_tick_timer.timeout.connect(func(): BasingService.tick_all_territories(world_server))
	add_sibling(territory_tick_timer)


func setup_global_commands_and_roles() -> void:
	var files: PackedStringArray = FileUtils.get_all_file_at(GLOBAL_COMMANDS_PATH, "*.gd")
	if files.is_empty():
		return
	
	var commands := ServerInstance.global_chat_commands
	# Names that must never become chat commands again (privilege bootstraps).
	var banned_names: PackedStringArray = [
		"selfadmin", "makeadmin", "giveadmin", "op", "sudo", "promote",
	]
	for file_path: String in files:
		var command = load(file_path).new()
		var cmd_name: String = str(command.command_name).strip_edges().to_lower()
		if cmd_name in banned_names:
			push_warning("Refusing to register banned command: /%s (%s)" % [cmd_name, file_path])
			continue
		# Anyone-runnable commands must not mutate server_roles (defense in depth
		# against a reintroduced /selfadmin-style bootstrap with priority 0).
		if int(command.command_priority) <= 0 and cmd_name.contains("admin"):
			push_warning(
				"Refusing open-priority admin-ish command: /%s (priority %s)"
				% [cmd_name, str(command.command_priority)]
			)
			continue
		commands.set(command.command_name, command)

	var roles := ServerInstance.global_role_definitions
	for role: String in roles:
		var role_data: Dictionary = roles[role]
		var role_commands: Array
		
		for command_name: String in commands:
			var command = commands[command_name]
			if command.command_priority <= role_data.get("priority", 0):
				role_commands.append(command_name)

		role_data['commands'] = role_commands


@rpc("authority", "call_remote", "reliable", 0)
func charge_new_instance(
	_map_path: String,
	_instance_id: String,
	_spawn_x: float = 0.0,
	_spawn_y: float = 0.0
) -> void:
	pass


func _rpc_charge(peer_id: int, map_path: String, instance_id: String, spawn: Vector2 = Vector2.ZERO) -> void:
	charge_new_instance.rpc_id(peer_id, map_path, instance_id, spawn.x, spawn.y)


## Resolve a joinable ServerInstance for login spawn. If the map is mid-load,
## wait for it (same pattern as warper queue_charge_instance) instead of
## returning null and stranding the peer on "Entering the world…".
func _instance_for_login(res: InstanceResource) -> ServerInstance:
	if not res.charged_instances.is_empty():
		return res.get_instance(0)
	if loading_instances.has(res):
		return loading_instances[res]
	return charge_instance(res)


## Deal with player respawn on login. Should replace this with proper map respawn logic later?
func _on_peer_connected(peer_id: int) -> void:
	place_peer(peer_id)


## Decide where [param peer_id] belongs and charge them into it. This is the login
## placement, factored out so [code]spawn.rescue[/code] can re-run exactly the same
## decision for a peer that ended up belonging to no instance at all — that is what
## a relog does for them, and it used to be the only thing that did.
## Returns false when no destination could be resolved.
func place_peer(peer_id: int) -> bool:
	if not world_server.connected_players.has(peer_id):
		return false
	var player_resource: PlayerResource = world_server.connected_players[peer_id]

	# Jailed players go straight to the jail instance, regardless of where they
	# logged out. If the jail map is missing (not authored yet), fall through
	# to normal spawn so we don't strand them in a black void.
	if JailList.is_jailed(player_resource.account_name):
		var jail_res: InstanceResource = instance_collection.get(JAIL_INSTANCE_NAME, null)
		if jail_res != null:
			var jail_inst: ServerInstance = _instance_for_login(jail_res)
			if jail_inst != null:
				_rpc_charge(peer_id, jail_res.map_path, jail_inst.name)
				jail_inst.queue_arrival(peer_id)
				return true

	# First-ever login? current_instance can't tell us — it's in-memory only (set on spawn,
	# shown on the dashboard, but never written to the DB). Instead read three values that ARE
	# persisted: a pristine new character is level 1 with zero experience and zero banked
	# playtime. Anything past that means they've played before — level/experience catch any
	# progression, played_seconds (banked into lb_stats on every disconnect) catches a character
	# that walked out of the cell without gaining XP. First login → the jail cell (lore:
	# condemned by the Capital; NOT JailList-jailed, so the cell's warper lets them walk straight
	# out — no lock, no forced tutorial). Every later login → the tavern (guild house) hub.
	var played_seconds: int = int(player_resource.lb_stats.get("played_seconds", 0))
	var is_first_login: bool = player_resource.level <= 1 and player_resource.experience <= 0 and played_seconds <= 0

	# Returning players resume where they logged out. last_instance/last_x/last_y are
	# persisted into lb_stats on save (rides stats_json — no schema change). Only
	# restore to an authored, known instance; skip the jail cell (jailed players were
	# already routed above) and first-time logins (they start in the cell).
	# Private dungeon runs dissolve on disconnect — never resume into a shared charge
	# of a DungeonResource map (mid-course spawn, no run bookkeeping / auto-eject).
	if not is_first_login:
		var saved_name: String = str(player_resource.lb_stats.get("last_instance", ""))
		if saved_name != "" and saved_name != JAIL_INSTANCE_NAME and instance_collection.has(saved_name):
			var saved_res: InstanceResource = instance_collection.get(saved_name)
			if saved_res != null and not (saved_res is DungeonResource):
				var saved_inst: ServerInstance = _instance_for_login(saved_res)
				if saved_inst != null:
					var saved_position := Vector2(
						float(player_resource.lb_stats.get("last_x", 0.0)),
						float(player_resource.lb_stats.get("last_y", 0.0))
					)
					_rpc_charge(peer_id, saved_res.map_path, saved_inst.name, saved_position)
					saved_inst.queue_arrival(peer_id, {"target_position": saved_position})
					return true

	var target_name: String = JAIL_INSTANCE_NAME if is_first_login else TAVERN_INSTANCE_NAME
	var target_res: InstanceResource = instance_collection.get(target_name, null)
	if target_res != null:
		var target_inst: ServerInstance = _instance_for_login(target_res)
		if target_inst != null:
			_rpc_charge(peer_id, target_res.map_path, target_inst.name)
			target_inst.queue_arrival(peer_id) # no target = the map's default spawn point (index 0)
			return true

	# Fallback: the tavern/jail map is missing or mid-load — land in the default overworld so
	# we never strand the player in a black void.
	if default_instance == null:
		push_error("InstanceManagerServer: no default_instance for peer %d" % peer_id)
		return false
	var fallback_inst: ServerInstance = _instance_for_login(default_instance)
	if fallback_inst == null:
		push_error("InstanceManagerServer: could not charge default_instance for peer %d" % peer_id)
		return false
	_rpc_charge(peer_id, default_instance.map_path, fallback_inst.name)
	fallback_inst.queue_arrival(peer_id)
	return true


func _on_player_entered_warper(player: Player, current_instance: ServerInstance, warper: Warper) -> void:
	# Jailed players can't traverse warpers — that's the whole point of jail.
	# We notify them once per attempt so they know it's intentional.
	if JailList.is_jailed(player.player_resource.account_name):
		world_server.chat_service.push_system_to_player(
			current_instance, player.player_resource.player_id,
			"You are jailed and cannot leave this area."
		)
		return

	var instance_index: int = -1 # Will be useful later
	var target_instance: ServerInstance
	var instance_resource: InstanceResource = warper.target_instance
	if not instance_resource:
		return

	if instance_resource.can_join_instance(player, instance_index):
		target_instance = instance_resource.get_instance()
		if target_instance:
			player_switch_instance(target_instance, warper.target_id, player, current_instance)
		else:
			queue_charge_instance(
				instance_resource,
				player_switch_instance.bind(warper.target_id, player, current_instance)
			)
	else:
		return


## Recall travel: send the peer to the town hub (RECALL_INSTANCE_NAME) at its
## default spawn (index 0). A faithful copy of send_player_to_jail — resolve the
## current instance authoritatively, charge the hub if it isn't live yet, then
## switch. Rolling our own current-instance lookup is what crashed recall before.
func recall_player(peer_id: int) -> void:
	# Story-boss arenas dump you back at the giver, not Guild Hall.
	if QuestBossService.redirect_recall(peer_id):
		return
	var res: InstanceResource = instance_collection.get(RECALL_INSTANCE_NAME, null)
	if res == null:
		return
	var current_inst: ServerInstance = find_instance_for_peer(peer_id)
	if current_inst == null:
		return
	var player: Player = current_inst.get_player(peer_id)
	if player == null:
		return
	# Already in the hub — recall still yanks you to its spawn point (the hub is a
	# big map), via the same same-instance teleport /goto uses.
	if current_inst.instance_resource == res:
		teleport_peer_to(peer_id, current_inst, current_inst.instance_map.get_spawn_position(0))
		return
	if res.charged_instances.is_empty():
		queue_charge_instance(res, player_switch_instance.bind(0, player, current_inst))
	else:
		player_switch_instance(res.get_instance(), 0, player, current_inst)


func queue_charge_instance(instance_resource: InstanceResource, callback: Callable) -> void:
	if loading_instances.has(instance_resource):
		loading_instances[instance_resource].ready.connect(
			callback.bind(loading_instances[instance_resource])
		)
		return
	var new_instance: ServerInstance = prepare_instance(instance_resource)
	new_instance.ready.connect(callback.bind(new_instance), CONNECT_ONE_SHOT)
	add_child(new_instance, true)


func player_switch_instance(
	target_instance: ServerInstance,
	warper_target_id: int,
	player: Player,
	current_instance: ServerInstance,
) -> void:
	var peer_id: int = player.name.to_int()
	# Settle the DESTINATION before taking the player out of the map they are in.
	# The map may not be in the tree yet: queue_charge_instance fires this off
	# ServerInstance.ready, and the map is added deferred, so the warper registry
	# can still be empty. Without the wait, the first player into a freshly charged
	# biome reads (0, 0) instead of the warper they aimed at.
	#
	# The wait used to sit AFTER the despawn below, which made a failed destination
	# unrecoverable: the player was already out of their old instance, so the abort
	# left them belonging to no map at all — the client sits parked, the avatar
	# never appears, and only a relog clears it. Deciding first means a bad
	# destination is a no-op and the player simply stays where they are.
	if not await target_instance.await_map_ready():
		ServerLog.warn(
			"Switch to '%s' aborted for peer %d — the instance has no map; staying put."
			% [target_instance.instance_resource.instance_name, peer_id]
		)
		return
	if current_instance.connected_peers.has(peer_id):
		current_instance.despawn_player(peer_id, false)
	else:
		return
	# Leaving an instance: drop the peer from a dungeon run (dissolves the group
	# when empty) and from any spar queue. Both no-op for an ordinary warp by
	# someone not in a run/queue.
	DungeonService.on_player_left(peer_id, current_instance)
	SparringService.on_player_left(peer_id, current_instance)
	# Boss Hunt was written with this hook but never wired in here, so ONLY the
	# exit station's boss_hunt.leave cleaned up. Leaving an arena any other way —
	# recall, a teleport, jail — left the contract alive: the HUD kept counting
	# down in the Guild Hall, and GroupService still held the player, so
	# handle_lobby_request refused the next contract with "in_run". That soft-
	# locked the mode until relog. No-op for a switch out of any non-hunt map.
	BossHuntService.on_player_left(peer_id, current_instance)
	QuestBossService.on_player_left(peer_id, current_instance)
	# Ossuran gate: drop the peer from the co-op group when they leave the private
	# arena (exit warp, death return, recall). No-op for any other map.
	OssuranGateService.on_player_left(peer_id, current_instance)
	var spawn_pos: Vector2 = target_instance.instance_map.get_spawn_position(warper_target_id)
	_rpc_charge(
		peer_id,
		target_instance.instance_resource.map_path,
		target_instance.name,
		spawn_pos
	)
	target_instance.queue_arrival(peer_id, {
		"player": player,
		"target_id": warper_target_id
	})


func charge_instance(instance_resource: InstanceResource) -> ServerInstance:
	if loading_instances.has(instance_resource):
		return
	var new_instance: ServerInstance = prepare_instance(instance_resource)
	add_child.call_deferred(new_instance, true)
	return new_instance


func prepare_instance(instance_resource: InstanceResource) -> ServerInstance:
	var instance: ServerInstance = ServerInstance.new()
	loading_instances[instance_resource] = instance
	instance.name = str(instance.get_instance_id())
	instance.instance_resource = instance_resource
	instance.player_entered_warper.connect(_on_player_entered_warper)
	instance.ready.connect(
		func():
			loading_instances.erase(instance_resource)
			instance_resource.charged_instances.append(instance),
		CONNECT_ONE_SHOT
	)
	instance.load_map(instance_resource.map_path)
	return instance


func set_instance_collection() -> void:
	for file_path: String in FileUtils.get_all_file_at(INSTANCE_COLLECTION_PATH, "*.tres"):
		if not file_path.ends_with(".tres"):
			continue
		# No type hint: in exports the custom-class loader isn't guaranteed
		# registered by the time this scan runs, so the hint "InstanceResource"
		# trips the resource loader. Load as untyped Resource and let the
		# embedded script class be resolved at assignment.
		var loaded: Resource = ResourceLoader.load(file_path)
		if loaded == null or not (loaded is InstanceResource):
			continue
		var instance_resource: InstanceResource = loaded
		if instance_resource.load_at_startup:
			charge_instance(instance_resource)
		if instance_resource.instance_name == "jail":
			default_instance = instance_resource
		instance_collection.set(instance_resource.instance_name, instance_resource)


## How many times the sweeper has declined to reclaim a map purely because
## somebody was walking into it. Every increment is one null spawn that would
## have happened on the old code. Grep the world log for "caught (" to read it.
static var arrivals_protected: int = 0


## Pure eligibility test for the sweeper below, split out from the node walk so
## it can be exercised without standing up a real ServerInstance
## (tools/verify_arrival_recovery.tscn). An instance is reclaimable only when it
## holds NOBODY — neither a player standing in the map nor one still walking in.
static func is_reapable(
	load_at_startup: bool,
	connected_peer_count: int,
	awaiting_peer_count: int,
	pinned: bool
) -> bool:
	if load_at_startup or pinned:
		return false
	return connected_peer_count == 0 and awaiting_peer_count == 0


func unload_unused_instances() -> void:
	print("Checking unload_unused_instances")
	for instance: ServerInstance in get_children():
		# Drop arrival slots whose peer has gone before they are counted, so a
		# client that quit or crashed mid-load cannot pin an empty map open.
		_prune_dead_arrivals(instance)
		var pinned: bool = (
			QuestBossService.is_pinned_origin(instance)
			# The Traveling Peddler charges its own biome and holds it for the
			# 30-minute window. Without this the sweeper would reclaim the empty
			# map on its next pass and the cart would never get placed in it.
			or PeddlerManager.holds_instance(instance)
		)
		if not is_reapable(
			instance.instance_resource.load_at_startup,
			instance.connected_peers.size(),
			instance.awaiting_peers.size(),
			pinned
		):
			# Was this instance saved ONLY by a pending arrival? Then we just
			# caught the null-spawn race in the act. Say so out loud.
			#
			# After a fix like this, silence is ambiguous — it reads the same as
			# "deployed wrong" or "wasn't the cause". A count that climbs is the
			# evidence the window is real and is being held open, and if null
			# spawns somehow continue anyway, a count that stays at zero says the
			# cause is somewhere else and points the next search away from here.
			if is_reapable(
				instance.instance_resource.load_at_startup,
				instance.connected_peers.size(),
				0,
				pinned
			):
				arrivals_protected += 1
				ServerLog.warn(
					"Held '%s' open for %d arriving peer(s) — the null-spawn race, caught (%d so far this session)."
					% [
						instance.instance_resource.instance_name,
						instance.awaiting_peers.size(),
						arrivals_protected,
					]
				)
			continue
		instance.instance_resource.charged_instances.erase(instance)
		instance.queue_free()


## Forget arrivals that are never going to complete: the peer has disconnected,
## or the slot has outlived [constant ServerInstance.ARRIVAL_TTL_MS].
##
## Both halves matter and they fail in opposite directions. Without the first, a
## client that quits mid-load holds an empty biome open. Without the second, so
## does a client that stays connected but never calls back — and THAT is the way
## this fix could have replaced a map that unloads too eagerly with one that
## never unloads at all.
##
## The Player node in an arrival slot was taken out of its old map by
## [method ServerInstance.despawn_player] and parented nowhere, so once the slot
## is dropped nothing else will ever free it — do it here.
func _prune_dead_arrivals(instance: ServerInstance) -> void:
	var expired: PackedInt64Array = instance.expired_arrivals()
	for peer_id: int in instance.awaiting_peers.keys():
		if world_server.connected_players.has(peer_id) and not expired.has(peer_id):
			continue
		_drop_arrival(instance, peer_id)


## Erase one arrival slot and free the orphaned Player it was holding.
func _drop_arrival(instance: ServerInstance, peer_id: int) -> void:
	if not instance.awaiting_peers.has(peer_id):
		return
	var stranded: Node = instance.awaiting_peers[peer_id].get("player", null) as Node
	if stranded != null and is_instance_valid(stranded) and stranded.get_parent() == null:
		stranded.queue_free()
	instance.awaiting_peers.erase(peer_id)


func get_instance_server_by_id(id: String) -> ServerInstance:
	if self.has_node(id):
		return self.get_node(id)
	return null


## Look up which ServerInstance a peer is currently in. O(instances) but
## instance counts are small (a few dozen at most), so this is fine for
## staff commands.
func find_instance_for_peer(peer_id: int) -> ServerInstance:
	for res: InstanceResource in instance_collection.values():
		for inst: ServerInstance in res.charged_instances:
			if inst.connected_peers.has(peer_id):
				return inst
	return null


## Recover a peer whose arrival never completed: the client has a map loaded and
## is asking to be spawned into it, but nothing answered. Its own re-asks
## (ready_to_enter_instance) are addressed to the destination ServerInstance, so
## they are useless in exactly the case that hurts — the instance is gone. This
## runs off the world server instead, which is always there.
##
## [param client_instance] is the instance id the CLIENT is holding, so we can
## tell "you missed the spawn for the right map" apart from "you are holding a
## map the server no longer associates you with"; an RPC to an instance node the
## client does not have would vanish the same way the first one did.
##
## Ordered cheapest-first. Returns the action taken, for the log and the reply.
func rescue_peer(peer_id: int, client_instance: String) -> String:
	# 1. Already spawned — the client just never received it. Re-deliver.
	var live: ServerInstance = find_instance_for_peer(peer_id)
	if live != null:
		# They are IN a map, so any arrival slot still naming them is stale, and
		# a stale slot now keeps its instance alive forever (see is_reapable).
		# This is the leak the rescue itself would otherwise introduce.
		_forget_arrivals(peer_id)
		var player: Player = live.get_player(peer_id)
		if client_instance == String(live.name) and player != null:
			live.resend_arrival(peer_id)
			return "resent_spawn"
		# The client is holding a different map than the one we have them in.
		_rpc_charge(
			peer_id,
			live.instance_resource.map_path,
			live.name,
			player.global_position if player != null else Vector2.ZERO
		)
		return "recharged_live"

	# 2. Still queued on an instance that is alive — re-send its charge. The
	#    arrival slot is left untouched, so the spawn lands where it was headed.
	for instance: ServerInstance in get_children():
		if not instance.awaiting_peers.has(peer_id):
			continue
		var slot: Dictionary = instance.awaiting_peers[peer_id]
		var spawn: Vector2 = Vector2.ZERO
		if slot.has("target_position"):
			spawn = slot["target_position"]
		elif instance.instance_map != null:
			spawn = instance.instance_map.get_spawn_position(int(slot.get("target_id", 0)))
		# Any OTHER instance still holding them is stale for the same reason.
		_forget_arrivals(peer_id, instance)
		_rpc_charge(peer_id, instance.instance_resource.map_path, instance.name, spawn)
		return "recharged_awaiting"

	# 3. Nothing holds them at all — the destination was torn down mid-arrival.
	#    Re-run the login placement, which is precisely what a relog does.
	_forget_arrivals(peer_id)
	return "replaced" if place_peer(peer_id) else "failed"


## Drop every arrival slot naming [param peer_id], except one on [param keep].
## A peer can only ever be walking into one map; more than one slot means an
## earlier arrival was superseded, and the extras would hold their instances
## open indefinitely now that the sweeper honours arrivals.
func _forget_arrivals(peer_id: int, keep: ServerInstance = null) -> void:
	for instance: ServerInstance in get_children():
		if instance == keep:
			continue
		_drop_arrival(instance, peer_id)


## Boss-arena / authored death eject: if the peer's current instance has
## [member InstanceResource.death_return_instance], switch them there (Castle
## Garden for The Hollow). Returns true when a cross-instance return was scheduled.
func send_player_death_return(peer_id: int) -> bool:
	var current_inst: ServerInstance = find_instance_for_peer(peer_id)
	if current_inst == null or current_inst.instance_resource == null:
		return false
	var dest_ref: InstanceResource = current_inst.instance_resource.death_return_instance
	if dest_ref == null:
		return false
	# Prefer the collection entry so we use the live charged_instances list.
	var dest: InstanceResource = instance_collection.get(
		String(dest_ref.instance_name), dest_ref
	) as InstanceResource
	if dest == null:
		dest = dest_ref
	var player: Player = current_inst.get_player(peer_id)
	if player == null:
		return false
	var warper_id: int = current_inst.instance_resource.death_return_warper_id
	# Already on the destination map — snap to its home spawn instead of no-op.
	if current_inst.instance_resource.instance_name == dest.instance_name:
		teleport_peer_to(peer_id, current_inst, current_inst.instance_map.get_spawn_position(warper_id))
		return true
	if dest.charged_instances.is_empty():
		queue_charge_instance(
			dest,
			player_switch_instance.bind(warper_id, player, current_inst)
		)
	else:
		player_switch_instance(dest.get_instance(), warper_id, player, current_inst)
	return true


## Move an online player straight to the jail instance. Mirrors the warper
## handler: synchronous switch if jail is already charged, else queue until
## the instance is ready. Silently no-ops if the jail map isn't authored yet.
## Returns true if a teleport was scheduled.
func send_player_to_jail(peer_id: int) -> bool:
	var jail_res: InstanceResource = instance_collection.get(JAIL_INSTANCE_NAME, null)
	if jail_res == null:
		push_warning("send_player_to_jail: no '%s' instance in collection." % JAIL_INSTANCE_NAME)
		return false

	var current_inst: ServerInstance = find_instance_for_peer(peer_id)
	if current_inst == null:
		return false
	var player: Player = current_inst.get_player(peer_id)
	if player == null:
		return false

	# Already in jail — nothing to do.
	if current_inst.instance_resource == jail_res:
		return false

	if jail_res.charged_instances.is_empty():
		queue_charge_instance(
			jail_res,
			player_switch_instance.bind(0, player, current_inst)
		)
	else:
		player_switch_instance(jail_res.get_instance(), 0, player, current_inst)
	return true


## Teleport an online player to an absolute position, in their current instance
## or another one. Used by /goto and /summon. Returns true if scheduled.
##
## Same instance: move server-side state (so other viewers see it) AND push an
## explicit teleport to the moved client — its LocalPlayer owns its position, so
## a state delta alone won't move it (it'd overwrite next input frame).
## Cross instance: despawn here and respawn at the position over there; the fresh
## spawn places the LocalPlayer correctly with no extra push.
func teleport_peer_to(peer_id: int, dest_instance: ServerInstance, dest_position: Vector2) -> bool:
	if dest_instance == null:
		return false
	var current_inst: ServerInstance = find_instance_for_peer(peer_id)
	if current_inst == null:
		return false
	var player: Player = current_inst.get_player(peer_id)
	if player == null:
		return false

	if current_inst == dest_instance:
		player.mark_just_teleported()
		player.state_synchronizer.set_by_path(^":position", dest_position)
		world_server.data_push.rpc_id(peer_id, &"player.teleport", {"position": dest_position})
		return true

	current_inst.despawn_player(peer_id, false)
	_rpc_charge(
		peer_id,
		dest_instance.instance_resource.map_path,
		dest_instance.name,
		dest_position
	)
	dest_instance.queue_arrival(peer_id, {"player": player, "target_position": dest_position})
	return true
