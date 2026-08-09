extends ChatCommand
## Public world roster. Opens a centered client panel instead of dumping chat lines.


func _init() -> void:
	command_name = "players"
	command_priority = 0
	command_alias = ["online"]
	command_usage = "/players"


func execute(_args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	var world: WorldServer = server_instance.world_server
	if world == null:
		return "Players list unavailable."

	var rows: Array = []
	for pid: int in world.connected_players:
		var res: PlayerResource = world.connected_players[pid]
		if res == null:
			continue
		rows.append({
			"name": res.display_name,
			"level": res.level,
			"instance": res.current_instance,
			"self": pid == peer_id,
		})

	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var la: int = int(a.get("level", 0))
		var lb: int = int(b.get("level", 0))
		if la != lb:
			return la > lb
		return str(a.get("name", "")).nocasecmp_to(str(b.get("name", ""))) < 0
	)

	world.data_push.rpc_id(peer_id, &"players.list", {
		"players": rows,
		"count": rows.size(),
	})
	return ""
