extends ChatCommand
## Ban an account from joining the world. Works online or offline.
## Disconnects them if they are currently connected.


func _init() -> void:
	command_name = "ban"
	command_priority = 2 # admin+
	command_usage = "/ban <self|@account|#id|Name> [duration] [reason]   (duration e.g. 30s, 10m, 2h, 1d; omit for permanent)"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() < 2:
		return "Usage: " + command_usage

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if target.account_name.is_empty():
		return "Couldn't resolve an account for that target."

	var ws: WorldServer = server_instance.world_server
	var admin: PlayerResource = ws.connected_players.get(peer_id)
	var admin_id: int = admin.player_id if admin else 0
	if admin != null and target.account_name.to_lower() == admin.account_name.to_lower():
		return "You can't ban yourself."
	if target.peer_id == peer_id and target.peer_id != 0:
		return "You can't ban yourself."
	var staff_block: String = CommandPermissions.staff_moderation_block_reason(
		admin, target, server_instance
	)
	if not staff_block.is_empty():
		return staff_block

	var args_offset: int = 2
	var duration_ms: int = 0
	var duration_label: String = "permanent"
	if args.size() > 2:
		duration_ms = ChatCommand.parse_duration_ms(args[2])
		if duration_ms > 0:
			args_offset = 3
			duration_label = args[2]
	var reason: String = " ".join(args.slice(args_offset)) if args.size() > args_offset else ""

	BanList.ban(target.account_name, reason, admin_id, duration_ms)

	if target.online:
		var notice: String = "You have been banned (%s)." % duration_label
		if not reason.is_empty():
			notice += "\nReason: " + reason
		ws.chat_service.push_system_to_player(server_instance, target.player_id, notice)
		ws.peer.disconnect_peer.call_deferred(target.peer_id)
		return "Banned %s for %s." % [target.label(), duration_label]

	return "Banned %s for %s (offline — blocked on next login)." % [target.label(), duration_label]
