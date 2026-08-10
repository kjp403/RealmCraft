extends ChatCommand
## Tell the calling player their current instance and world position.


func _init() -> void:
	command_name = "coords"
	command_priority = 0
	command_usage = "/coords"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 1:
		return "Usage: " + command_usage

	var p: Player = server_instance.get_player(peer_id)
	var pos: Vector2 = p.global_position if p != null else Vector2.ZERO
	return "You are in %s at (%d, %d)." % [
		server_instance.instance_resource.instance_name, int(pos.x), int(pos.y)
	]
