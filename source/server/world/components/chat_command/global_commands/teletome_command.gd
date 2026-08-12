extends ChatCommand
## Pull a player to your position — and unlike /summon, it works when they are
## OFFLINE. This is the rescue tool for "I'm stuck in the scenery and relogging
## doesn't help": relogging normally restores the player to the exact spot they
## logged out from (see InstanceManagerServer._on_peer_connected), so a player
## wedged inside geometry is stuck across sessions and cannot fix it themselves.
##
## Online target  → teleported immediately, same as /summon.
## Offline target → their saved login location is rewritten to the admin's spot,
##                  so the next time they log in they land next to you instead
##                  of back inside the wall. Persisted through lb_stats
##                  (last_instance/last_x/last_y), the same three keys
##                  WorldServer._stamp_location writes on disconnect.
##
## An offline @account resolves to a single character where it can. Accounts
## with several characters fall back to the most recently played one (that is
## the one that was stuck) and the confirmation names it, so an admin who wanted
## a different character can redo it with #id — run /chars <account> to list.
##
## Note: stand somewhere sane before using it. Whatever instance YOU are in is
## what gets recorded, so calling it from inside a dungeon stages the player
## into that dungeon.


func _init() -> void:
	command_name = "teletome"
	command_priority = 2 # admin+
	command_usage = "/teletome <self|@account|#id|name>   (works on offline players — they arrive at next login)"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 2:
		return "Usage: " + command_usage

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if target.online and target.peer_id == peer_id:
		return "You're already here."

	var ws: WorldServer = server_instance.world_server
	var me_inst: ServerInstance = ws.instance_manager.find_instance_for_peer(peer_id)
	var me: Player = me_inst.get_player(peer_id) if me_inst != null else null
	if me_inst == null or me == null:
		return "Couldn't locate you."

	if target.online:
		if not ws.instance_manager.teleport_peer_to(target.peer_id, me_inst, me.global_position):
			return "Teleport failed."
		ws.chat_service.push_system_to_player(
			server_instance, target.player_id, "An admin has teleported you to them."
		)
		return "Teleported %s to you." % target.label()

	# --- offline: rewrite where they will next log in ------------------------
	var res: PlayerResource = _offline_character(target, ws)
	if res == null:
		return (
			"No character found for %s. Try /chars <account> and target by #id."
			% target.label()
		)

	var destination: String = me_inst.instance_resource.instance_name
	res.current_instance = destination
	res.last_position = me.global_position
	res.lb_stats["last_instance"] = destination
	res.lb_stats["last_x"] = me.global_position.x
	res.lb_stats["last_y"] = me.global_position.y
	ws.database.save_player(res)

	# Jail routing runs before the saved-location restore on login, so say so
	# rather than letting the admin think the rescue silently failed.
	var caveat: String = ""
	if JailList.is_jailed(res.account_name):
		caveat = " NOTE: that account is jailed, so they'll go to the cell until /unjail."

	return (
		"%s is offline — staged to arrive at your position (%s, %d, %d) on next login.%s"
		% [
			res.display_name,
			destination,
			int(me.global_position.x),
			int(me.global_position.y),
			caveat,
		]
	)


## The character to rescue for an offline target. A #id or exact-name target
## already names one; a bare @account may own several, in which case the most
## recently played is the one that got stuck.
func _offline_character(target: CommandTarget.Result, ws: WorldServer) -> PlayerResource:
	if target.player_id > 0:
		return ws.database.get_player_resource(target.player_id)
	if target.account_name.is_empty():
		return null

	var characters: Dictionary = ws.database.store.get_account_characters(target.account_name)
	var best: PlayerResource = null
	var best_seen: int = -1
	for player_id: int in characters:
		var candidate: PlayerResource = ws.database.get_player_resource(player_id)
		if candidate == null:
			continue
		var seen: int = int(candidate.lb_stats.get("last_seen_ms", 0))
		if seen > best_seen:
			best_seen = seen
			best = candidate
	return best
