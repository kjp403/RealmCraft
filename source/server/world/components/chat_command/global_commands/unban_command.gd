extends ChatCommand
## Lift a BanList entry so the account can log in again.


func _init() -> void:
	command_name = "unban"
	command_priority = 2 # admin+
	command_usage = "/unban <@account|#id|Name>"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 2:
		return "Usage: " + command_usage

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if target.account_name.is_empty():
		return "Couldn't resolve an account for that target."

	if not BanList.unban(target.account_name):
		return "%s is not banned." % target.label()
	return "Unbanned %s." % target.label()
