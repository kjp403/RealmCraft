extends DataRequestHandler
## Returns chat commands the caller may run (same filter as /help), for the
## Settings → Commands panel. Staff-only commands are omitted unless the
## player holds a high enough role.


func data_request_handler(peer_id: int, instance: ServerInstance, _args: Dictionary) -> Dictionary:
	var player: PlayerResource = null
	if instance != null and instance.world_server != null:
		player = instance.world_server.connected_players.get(peer_id)
	if player == null:
		return {"ok": false, "reason": "no_player", "commands": []}

	var commands: Dictionary = instance.global_chat_commands if instance != null else {}
	var names: Array = commands.keys()
	names.sort()
	var rows: Array = []
	for command_name: String in names:
		var command: ChatCommand = commands[command_name]
		if command == null or not CommandPermissions.can_run(command, player, instance):
			continue
		var usage: String = command.command_usage
		if usage.is_empty():
			usage = "/" + command.command_name
		rows.append({
			"name": command.command_name,
			"aliases": Array(command.command_alias),
			"usage": usage,
			"priority": command.command_priority,
		})
	return {"ok": true, "commands": rows}
