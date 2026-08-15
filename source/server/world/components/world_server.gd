class_name WorldServer
extends BaseMultiplayerEndpoint
## Server autoload. Keep it clean and minimal.
## Should only care about connection and authentication stuff.

@export var database: WorldDatabase
@export var world_manager: WorldManagerClient
@export var world_clock: WorldClock
@export var chat_service: ChatService

## The full-DB backup (WAL checkpoint TRUNCATE + whole-file copy) is the heaviest
## periodic op and its cost grows with DB size, so it runs on a MULTIPLE of the save
## interval instead of every save. Player saves flush every 60s (cheap per player,
## keeps the crash/rollback window short); the backup folds in every Nth save.
## With keep_last=10 the retained history stretches to ~5 h.
## See docs/netcode_perf_audit.md.
const PERIODIC_SAVE_INTERVAL_SEC: float = 60.0
const BACKUP_EVERY_N_SAVES: int = 30  # 30 × 60s = 30 min
var _periodic_save_count: int = 0

var token_list: Dictionary[String, PlayerResource]
## Gateway-provided client IP for each pending auth token (Caddy X-Real-IP).
var token_client_ips: Dictionary[String, String]
## {peer_id: client_ip} for currently connected peers.
var peer_client_ips: Dictionary[int, String]

## {peer_id: PlayerResource}
var connected_players: Dictionary[int, PlayerResource]
## {player_id: peer_id}
var player_id_to_peer_id: Dictionary[int, int]

static var curr: WorldServer


func start_world_server() -> void:
	world_manager.token_received.connect(
		func(auth_token: String, _username: String, character_id: int, client_ip: String = ""):
			# Reconnect must never mint a session from a stale DB row while the
			# live peer still holds newer in-memory progress (XP/loot/etc.).
			var player: PlayerResource = _takeover_or_load_player(character_id)
			token_list[auth_token] = player
			if not client_ip.is_empty():
				token_client_ips[auth_token] = client_ip
	)

	var configuration: Dictionary = ConfigFileUtils.load_section(
		"world-server",
		CmdlineUtils.get_parsed_args().get("config", "res://data/config/world_config.cfg")
	)
	if configuration.has("error"):
		# Error case
		pass
	else:
		create(Role.SERVER, configuration.bind_address, configuration.port)

	chat_service.setup_with_db(database.db)
	$InstanceManager.start_instance_manager()

	# Periodic save + backup. 60s keeps crash/disconnect rollback short without
	# writing every combat tick. Full DB backups still run on BACKUP_EVERY_N_SAVES.
	var save_timer: Timer = Timer.new()
	save_timer.name = "PeriodicSaveTimer"
	save_timer.wait_time = PERIODIC_SAVE_INTERVAL_SEC
	save_timer.autostart = true
	save_timer.timeout.connect(_on_periodic_save)
	add_child(save_timer)

	# Network/tick profiler report — one aggregate [NET] line per second across the
	# whole world process (docs/netcode_perf_audit.md, F0). Cheap; toggle the output
	# with NetProfiler.enabled. This is the measurement backbone for load testing.
	var net_report_timer: Timer = Timer.new()
	net_report_timer.name = "NetProfilerTimer"
	net_report_timer.wait_time = 1.0
	net_report_timer.autostart = true
	net_report_timer.timeout.connect(
		func() -> void: NetProfiler.report_and_reset(connected_players.size(), 1.0)
	)
	add_child(net_report_timer)


## Snapshot a connected player's live location into lb_stats so it persists via
## stats_json (no schema change) and login can resume them where they left off.
## Private dungeon runs dissolve on disconnect — stamp the tavern hub instead so
## login never charges a shared copy of the dungeon map mid-course.
func _stamp_location(peer_id: int, player: PlayerResource) -> void:
	if player == null or instance_manager == null:
		return
	var inst: ServerInstance = instance_manager.find_instance_for_peer(peer_id)
	if inst == null:
		return
	if inst.instance_resource is DungeonResource:
		player.current_instance = InstanceManagerServer.TAVERN_INSTANCE_NAME
		player.lb_stats["last_instance"] = InstanceManagerServer.TAVERN_INSTANCE_NAME
		player.lb_stats.erase("last_x")
		player.lb_stats.erase("last_y")
		return
	player.current_instance = inst.instance_resource.instance_name
	var node: Player = inst.get_player(peer_id)
	if node != null:
		player.last_position = node.global_position
	player.lb_stats["last_instance"] = player.current_instance
	player.lb_stats["last_x"] = player.last_position.x
	player.lb_stats["last_y"] = player.last_position.y


## If [param character_id] is already online, flush that live PlayerResource to
## disk, detach it from the old peer, and reuse it for the new auth token.
## Otherwise load a fresh row from the DB. Prevents reconnect from restoring a
## periodic-save snapshot that is minutes behind the live session.
func _takeover_or_load_player(character_id: int) -> PlayerResource:
	var existing_peer: int = int(player_id_to_peer_id.get(character_id, 0))
	if existing_peer == 0:
		return database.get_player_resource(character_id)

	var live: PlayerResource = connected_players.get(existing_peer)
	if live == null:
		player_id_to_peer_id.erase(character_id)
		return database.get_player_resource(character_id)

	# Bank session time + stamp location before flush so the takeover save is
	# as complete as a normal disconnect flush.
	if live.session_start_ms > 0:
		@warning_ignore("integer_division")
		var session_seconds: int = (Time.get_ticks_msec() - live.session_start_ms) / 1000
		if session_seconds > 0:
			live.lb_stats["played_seconds"] = int(live.lb_stats.get("played_seconds", 0)) + session_seconds
		live.session_start_ms = 0
	live.lb_stats["last_seen_ms"] = int(Time.get_unix_time_from_system() * 1000.0)
	_stamp_location(existing_peer, live)
	if not PendingChestLoot.is_empty(live.pending_chest_loot):
		PendingChestLoot.flush_to_bank(live)
	database.save_player(live)

	# Detach before kicking so _on_peer_disconnected is a no-op for this peer
	# (avoids a second save of a half-torn-down session, and avoids clobber).
	player_id_to_peer_id.erase(character_id)
	connected_players.erase(existing_peer)
	peer_client_ips.erase(existing_peer)
	live.current_peer_id = 0
	BlockList.clear_player(character_id)

	SparringService.on_peer_disconnected(existing_peer)
	DungeonService.on_peer_disconnected(existing_peer)
	RateLimiter.forget(existing_peer)
	if world_manager != null:
		world_manager.player_disconnected.rpc_id(1, live.account_name)

	var game_mp: MultiplayerAPI = multiplayer_api
	if game_mp != null and game_mp.multiplayer_peer != null:
		game_mp.multiplayer_peer.disconnect_peer(existing_peer)

	ServerLog.info(
		"Reconnect takeover: flushed + detached player #%d from peer %d." % [character_id, existing_peer]
	)
	return live


func _on_periodic_save() -> void:
	# Refresh last-seen for everyone online so a crash only loses at most one
	# save interval of it (the authoritative stamp is on disconnect).
	var now_unix_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	for pid: int in connected_players:
		var p: PlayerResource = connected_players[pid]
		if p != null:
			p.lb_stats["last_seen_ms"] = now_unix_ms
			_stamp_location(pid, p)
	var saved: int = database.save_all_connected(connected_players)
	# The backup (checkpoint + full-file copy) only runs every Nth save — see
	# BACKUP_EVERY_N_SAVES. Shutdown / master-triggered saves back up separately.
	_periodic_save_count += 1
	if _periodic_save_count % BACKUP_EVERY_N_SAVES != 0:
		ServerLog.info("Periodic save: %d player(s) flushed." % saved)
		return
	var ok: bool = database.backup_database()
	ServerLog.info("Periodic save: %d player(s) flushed, backup %s." % [saved, "ok" if ok else "FAILED"])


## Best-effort save on a window-manager close (editor run / windowed build).
## NOTE: Godot headless does NOT deliver _notification on SIGINT/SIGTERM, so this
## does NOT fire on `systemctl stop` (verified). The reliable production save path
## is master-triggered (master_save / master_restart, RPC-driven so it's signal-
## free) — the deploy calls /v1/save_all before stopping. This handler stays only
## for the interactive/windowed case; it's harmless and never the sole safety net.
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	if database == null:
		return
	var saved: int = database.save_all_connected(connected_players)
	var ok: bool = database.backup_database()
	ServerLog.info("Shutdown save: %d player(s) flushed, backup %s." % [saved, "ok" if ok else "FAILED"])


func _connect_multiplayer_api_signals(api: SceneMultiplayer) -> void:
	api.peer_connected.connect(_on_peer_connected)
	api.peer_disconnected.connect(_on_peer_disconnected)
	
	api.peer_authenticating.connect(_on_peer_authenticating)
	api.peer_authentication_failed.connect(_on_peer_authentication_failed)
	api.set_auth_callback(_authentication_callback)


func _on_peer_connected(peer_id: int) -> void:
	ServerLog.info("Peer %d connected." % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	ServerLog.info("Peer %d disconnected." % peer_id)
	# Resolve the player first. Reconnect takeover may have already detached
	# this peer — in that case skip save/teardown so we don't clobber the
	# live resource now owned by the new session.
	var player: PlayerResource = connected_players.get(peer_id)
	if player == null:
		SparringService.on_peer_disconnected(peer_id)
		DungeonService.on_peer_disconnected(peer_id)
		RateLimiter.forget(peer_id)
		return

	# Sparring: if mid-match, end it before we tear down so the survivor gets
	# the win + teleport instead of being stranded in the arena.
	SparringService.on_peer_disconnected(peer_id)
	# Dungeon: sweep them from any lobby queue / live run so the group + run maps
	# don't keep a phantom member (and the private instance can free when empty).
	DungeonService.on_peer_disconnected(peer_id)
	# Drop rate-limit counters so a reconnect starts with a clean window.
	RateLimiter.forget(peer_id)

	world_manager.player_disconnected.rpc_id(1, player.account_name)

	# Bank the elapsed session time before persisting. Stored as a flat key on
	# lb_stats so it rides existing stats_json serialization (no schema change).
	if player.session_start_ms > 0:
		@warning_ignore("integer_division")
		var session_seconds: int = (Time.get_ticks_msec() - player.session_start_ms) / 1000
		if session_seconds > 0:
			player.lb_stats["played_seconds"] = int(player.lb_stats.get("played_seconds", 0)) + session_seconds

	# Last-seen stamp (unix ms). Rides lb_stats/stats_json like played_seconds —
	# no schema change; profile.get buckets it into coarse "last seen" text.
	player.lb_stats["last_seen_ms"] = int(Time.get_unix_time_from_system() * 1000.0)

	# Persist where they logged out so next login resumes here (see _stamp_location
	# and InstanceManagerServer._on_peer_connected). Runs before the instance despawn.
	_stamp_location(peer_id, player)

	# Chest staging leftovers go to the bank so disconnect never voids loot.
	if not PendingChestLoot.is_empty(player.pending_chest_loot):
		PendingChestLoot.flush_to_bank(player)

	database.save_player(player)

	player_id_to_peer_id.erase(player.player_id)
	BlockList.clear_player(player.player_id)

	player.current_peer_id = 0
	connected_players.erase(peer_id)
	peer_client_ips.erase(peer_id)


func _on_peer_authenticating(peer_id: int) -> void:
	print("Peer: %d is trying to authenticate." % peer_id)
	multiplayer.send_auth(peer_id, "data_from_server".to_ascii_buffer())


func _on_peer_authentication_failed(peer_id: int) -> void:
	print("Peer: %d failed to authenticate." % peer_id)


func _authentication_callback(peer_id: int, data: PackedByteArray) -> void:
	# Cast as String if not returns empty String
	var auth_token: String = bytes_to_var(data) as String
	# The token is a one-time bearer credential. Log the peer, never the secret.
	print("Peer: %d supplied world authentication data." % peer_id)
	if is_valid_authentication_token(auth_token):
		var pending: PlayerResource = token_list[auth_token]
		var client_ip: String = _resolve_client_ip(peer_id, str(token_client_ips.get(auth_token, "")))
		token_client_ips.erase(auth_token)
		# Account bans block world entry entirely (character switch can't dodge).
		if pending != null and BanList.is_banned(pending.account_name):
			print("Peer: %d rejected — account banned (%s)." % [peer_id, pending.account_name])
			token_list.erase(auth_token)
			peer.disconnect_peer(peer_id)
			return
		if IpBanList.is_banned(client_ip):
			print("Peer: %d rejected — IP banned (%s)." % [peer_id, client_ip])
			token_list.erase(auth_token)
			peer.disconnect_peer(peer_id)
			return
		multiplayer.complete_auth(peer_id)
		connected_players[peer_id] = pending
		connected_players[peer_id].current_peer_id = peer_id
		# Stamp the session start so the played_seconds counter can advance on
		# disconnect. Reset on every fresh login.
		connected_players[peer_id].session_start_ms = Time.get_ticks_msec()
		player_id_to_peer_id[connected_players[peer_id].player_id] = peer_id
		if not client_ip.is_empty():
			peer_client_ips[peer_id] = client_ip
			if pending != null:
				IpBanList.remember_account_ip(pending.account_name, client_ip)
		# Hydrate the per-player block-list cache so chat filtering is a
		# dictionary lookup, not a JSON parse per message.
		BlockList.set_for(connected_players[peer_id].player_id, connected_players[peer_id].blocked_ids)
		token_list.erase(auth_token)
		data_push.rpc_id.call_deferred(peer_id, &"player_id.set", {"player_id": connected_players[peer_id].player_id})
		data_push.rpc_id.call_deferred(peer_id, &"active_guild_id.set", {"active_guild_id": connected_players[peer_id].active_guild_id})
		# Wardstone mirror: lets sealed portals render + explain locally with zero
		# round trips (docs/wardstones.md). Re-pushed on every grant. Backfill
		# first: finales turned in before the system shipped still owe their stone.
		QuestService.backfill_wardstones(connected_players[peer_id])
		data_push.rpc_id.call_deferred(peer_id, &"wardstones.set", {"wardstones": connected_players[peer_id].wardstones})
		# Profession levels for client-side skill checks (craft UI, skill gates).
		# Full skills.get shape is heavier; gates only need levels at login.
		var skill_levels: Dictionary = {}
		for skill_name: StringName in connected_players[peer_id].skills:
			skill_levels[String(skill_name)] = int(
				(connected_players[peer_id].skills[skill_name] as Dictionary).get("level", 1)
			)
		data_push.rpc_id.call_deferred(peer_id, &"skills.levels", {"levels": skill_levels})
		QuestService.push_character_flags(connected_players[peer_id], peer_id)
	else:
		peer.disconnect_peer(peer_id)


func is_valid_authentication_token(auth_token: String) -> bool:
	if token_list.has(auth_token):
		return true
	return false


## Best-known client IP for a connected peer (gateway X-Real-IP preferred).
func get_peer_client_ip(peer_id: int) -> String:
	return str(peer_client_ips.get(peer_id, ""))


## Disconnect every connected peer whose recorded client IP matches [param ip].
## Returns how many peers were kicked.
func disconnect_peers_with_ip(ip: String, notice: String = "") -> int:
	var needle: String = IpBanList.normalize_ip(ip)
	if needle.is_empty():
		return 0
	var kicked: int = 0
	for pid: int in peer_client_ips.keys():
		if IpBanList.normalize_ip(str(peer_client_ips[pid])) != needle:
			continue
		var player: PlayerResource = connected_players.get(pid)
		if player != null and not notice.is_empty() and chat_service != null:
			chat_service.push_system_to_player(null, player.player_id, notice)
		peer.disconnect_peer.call_deferred(pid)
		kicked += 1
	return kicked


## Prefer the gateway-provided IP when the WebSocket peer address is loopback
## (normal behind Caddy). Falls back to the socket address otherwise.
func _resolve_client_ip(peer_id: int, token_ip: String) -> String:
	var socket_ip: String = ""
	if peer is WebSocketMultiplayerPeer:
		socket_ip = (peer as WebSocketMultiplayerPeer).get_peer_address(peer_id)
	if IpBanList.is_usable_ip(token_ip):
		return IpBanList.normalize_ip(token_ip)
	if IpBanList.is_usable_ip(socket_ip):
		return IpBanList.normalize_ip(socket_ip)
	var fallback: String = token_ip if not token_ip.is_empty() else socket_ip
	return IpBanList.normalize_ip(fallback)


@export var instance_manager: InstanceManagerServer

var data_handlers: Dictionary[StringName, DataRequestHandler]


func _ready() -> void:
	# Publish the live world-server singleton. Common-side code reaches it as the
	# typed `WorldServer.curr` (the export plugin stubs this static, so naming the
	# class in common/ stays client-export-safe).
	curr = self


## If no instance_id is provided, will use all peers connected in the world.
func propagate_rpc(callable: Callable, instance_id: String = "") -> void:
	var instance: ServerInstance = instance_manager.get_instance_server_by_id(instance_id)
	if instance:
		for peer_id: int in instance.connected_peers:
			callable.rpc_id(peer_id)
	else:
		for peer_id: int in instance_manager.world_server.connected_players:
			callable.rpc_id(peer_id)


## Recall payoff (called via WorldServer.curr from RecallAbility.channel_complete): send
## [param player] home to the town hub. Delegates to the InstanceManager by peer,
## which resolves the current instance authoritatively and reuses the warper/jail
## travel path.
func recall_player(player: Player) -> void:
	if player == null or player.player_resource == null:
		return
	instance_manager.recall_player(int(player.player_resource.current_peer_id))


@rpc("any_peer", "call_remote", "reliable", 1)
func _data_request(
	request_id: int,
	type: StringName,
	args: Dictionary = {},
	instance_id: String = ""
) -> void:
	const DATA_REQUEST_HANDLERS_PATH: String = "res://source/server/world/components/data_request_handlers/"
	var peer_id: int = multiplayer.get_remote_sender_id()
	var instance: ServerInstance = instance_manager.get_instance_server_by_id(instance_id)

	if not instance:
		instance = instance_manager.default_instance.charged_instances[0]

	if not data_handlers.has(type):
		var path: String = DATA_REQUEST_HANDLERS_PATH + type + ".gd"
		if not ResourceLoader.exists(path):
			return
		var script: GDScript = load(path)
		if not script:
			return

		var handler = script.new() as DataRequestHandler
		if not handler:
			return
		data_handlers[type] = handler

	_data_response.rpc_id(
		peer_id,
		request_id,
		type,
		data_handlers[type].data_request_handler(peer_id, instance, args)
	)


@rpc("authority", "call_remote", "reliable", 1)
func _data_response(request_id: int, type: String, data: Dictionary) -> void:
	# Client only
	pass


@rpc("authority", "call_remote", "reliable", 1)
func data_push(type: StringName, data: Dictionary) -> void:
	# Client only
	pass
