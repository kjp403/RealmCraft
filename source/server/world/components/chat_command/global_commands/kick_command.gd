extends ChatCommand
## Force-disconnect an online player. They can reconnect (use /ban to keep them out).


func _init() -> void:
	command_name = "kick"
	command_priority = 2 # admin+
	command_usage = "/kick <self|@account|#id> [reason]"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() < 2:
		return "Usage: " + command_usage

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if not target.online:
		return "%s is not online." % target.label()
	if target.peer_id == peer_id:
		return "You can't kick yourself."

	var ws: WorldServer = server_instance.world_server
	var admin: PlayerResource = ws.connected_players.get(peer_id)
	var staff_block: String = CommandPermissions.staff_moderation_block_reason(
		admin, target, server_instance
	)
	if not staff_block.is_empty():
		return staff_block

	var reason: String = " ".join(args.slice(2)) if args.size() > 2 else ""
	if not reason.is_empty():
		ws.chat_service.push_system_to_player(
			server_instance,
			target.player_id,
			"You have been kicked by an admin.\nReason: " + reason
		)
	else:
		ws.chat_service.push_system_to_player(
			server_instance,
			target.player_id,
			"You have been kicked by an admin."
		)

	# Defer so the system message has a tick to flush.
	ws.peer.disconnect_peer.call_deferred(target.peer_id)
	return "Kicked %s." % target.label()
