class_name CollectionLogNotifier
extends RefCounted
## Turns Collection Log signals into client pushes.
##
##     CollectionLogNotifier.attach(world_server)
##
## WHY THIS IS NOT IN THE MANAGER. CollectionLogManager lives in common/ and must
## stay headless — it runs on the world server, where no client UI class compiles,
## and it is instanced bare by every verifier in tools/. Giving it a WorldServer
## reference would put a server-only type in common/ and break both. So the
## manager emits and knows nothing; this listens and does the talking.
##
## Two pushes, deliberately different in reach:
##
##   collection_log.item   -> the ONE player who got the drop. A unique landing
##                            is their business and nobody else's.
##   chat.message          -> the whole world, once, the first time a character
##                            fills a log. Green-logging is rare enough to be
##                            worth interrupting strangers for; a per-item
##                            broadcast would be spam within an hour.
##
## Nothing here writes progress. If this file is never attached the log still
## records correctly and the menu still reads it — the player just does not get
## told at the moment it happens.

## Kept so the pushes can be reached without threading a reference through the
## signal payloads, which would put a server type in the manager's signature.
static var _server: Node = null


## Wire the manager's signals to this world's peers. Safe to call twice.
static func attach(world_server: Node) -> void:
	if world_server == null:
		return
	_server = world_server
	if not CollectionLogManager.item_logged.is_connected(_on_item_logged):
		CollectionLogManager.item_logged.connect(_on_item_logged)
	if not CollectionLogManager.log_completed.is_connected(_on_log_completed):
		CollectionLogManager.log_completed.connect(_on_log_completed)


static func detach() -> void:
	if CollectionLogManager.item_logged.is_connected(_on_item_logged):
		CollectionLogManager.item_logged.disconnect(_on_item_logged)
	if CollectionLogManager.log_completed.is_connected(_on_log_completed):
		CollectionLogManager.log_completed.disconnect(_on_log_completed)
	_server = null


## A new unique was credited. Push only to its owner.
##
## The item's NAME is not sent: the client already resolves slugs through
## ContentRegistryHub for the log menu and the loot feed, and sending the
## display name here would be a second source of truth that can disagree with
## the one the menu uses — and would ship the server's locale to every client.
static func _on_item_logged(
	player_res: PlayerResource, boss_id: StringName, item_id: StringName,
	unlocked: int, total: int
) -> void:
	var peer_id: int = _peer_of(player_res)
	if peer_id <= 0:
		return # offline or mid-handover; the menu will show it on next open
	_push(peer_id, &"collection_log.item", {
		"boss_id": String(boss_id),
		"slug": String(item_id),
		"unlocked": unlocked,
		"total": total,
	})


## A log went green for the first time. The owner gets the reward card; the
## world gets one announcement line.
static func _on_log_completed(
	player_res: PlayerResource, boss_id: StringName,
	green_log_title_text: String, _green_log_vfx: PackedScene
) -> void:
	var boss_log: BossCollectionLog = CollectionLogManager.find_log(boss_id)
	var boss_name: String = boss_log.boss_name if boss_log != null else String(boss_id)

	var peer_id: int = _peer_of(player_res)
	if peer_id > 0:
		_push(peer_id, &"collection_log.green", {
			"boss_id": String(boss_id),
			"boss_name": boss_name,
			"title": green_log_title_text,
		})

	# The announcement is built here rather than on each client so every player
	# sees the SAME sentence — a client-side string would drift the moment one
	# of them is running a different build.
	var line: String = "%s completed the %s collection log and earned « %s »." % [
		player_res.display_name if player_res != null else "Someone",
		boss_name, green_log_title_text,
	]
	_announce(line)


## One line to every connected peer on this world, from the server rather than
## from a player. Reuses the chat.message push the MOTD path uses, so it lands in
## the client's existing chat log with no new client plumbing.
static func _announce(text: String) -> void:
	if _server == null or not is_instance_valid(_server):
		return
	var connected: Dictionary = _server.get(&"connected_players")
	if connected == null:
		return
	for peer_id: Variant in connected:
		_push(int(peer_id), &"chat.message", {
			"text": text,
			"name": "Server",
			"id": 1,
			"channel": ChatConstants.CHANNEL_WORLD,
			"time_ms": int(Time.get_unix_time_from_system() * 1000.0),
		})


static func _peer_of(player_res: PlayerResource) -> int:
	if player_res == null:
		return 0
	return int(player_res.current_peer_id)


static func _push(peer_id: int, key: StringName, data: Dictionary) -> void:
	if _server == null or not is_instance_valid(_server) or peer_id <= 0:
		return
	_server.data_push.rpc_id(peer_id, key, data)
