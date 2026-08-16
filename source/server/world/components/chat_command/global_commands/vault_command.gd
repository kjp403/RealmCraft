extends ChatCommand
## Enter the VFX Vault — the staff-only room where unreleased cosmetics are tested.
## `/vault out` recalls you to town, as a safety net if the Vault's exit warper ever
## breaks and someone would otherwise be stranded in a room with no other door.
##
## This command is one of TWO independent gates, not the gate. command_priority makes
## it admin+, and AdminOnlyInstanceResource.can_join_instance refuses non-staff on
## arrival regardless of how the transfer was requested. Nothing in the world warps
## into the vault, and it is not load_at_startup.


func _init() -> void:
	command_name = "vault"
	command_priority = 2 # admin+
	command_usage = "/vault [out]"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	var ws: WorldServer = server_instance.world_server
	if ws == null or ws.instance_manager == null:
		return "World not ready."

	if args.size() > 1 and args[1].to_lower() == "out":
		ws.instance_manager.recall_player(peer_id)
		return "Recalled to town."
	if args.size() > 1:
		return "Usage: " + command_usage

	# instance_collection is Dictionary[String, InstanceResource] — look up with a
	# String, not a StringName, so the key type matches the declared dictionary.
	var res: InstanceResource = ws.instance_manager.instance_collection.get("vfx_vault", null)
	if res == null:
		return "The Vault isn't registered on this server."

	var current_inst: ServerInstance = ws.instance_manager.find_instance_for_peer(peer_id)
	if current_inst == null:
		return "Couldn't locate you."
	var player: Player = current_inst.get_player(peer_id)
	if player == null:
		return "Couldn't locate you."
	if current_inst.instance_resource == res:
		return "You're already in the Vault."
	# Belt and braces: the instance refuses non-staff itself, but bail early with a
	# readable message rather than a silent no-op transfer.
	if not res.can_join_instance(player):
		return "The Vault is closed to you."

	# The Vault is not load_at_startup — charge it on first entry, like recall does.
	if res.charged_instances.is_empty():
		ws.instance_manager.queue_switch_to(res, 0, player, current_inst)
	else:
		ws.instance_manager.player_switch_instance(res.get_instance(), 0, player, current_inst)
	return "Entering the VFX Vault."
