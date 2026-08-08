extends ChatCommand
## Lift an IpBanList entry. Accepts a raw IP or a player target (uses last-known IP).


func _init() -> void:
	command_name = "unipban"
	command_priority = 2 # admin+
	command_usage = "/unipban <@account|#id|ip>"
	command_alias = PackedStringArray(["ipunban"])


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 2:
		return "Usage: " + command_usage

	var token: String = args[1].strip_edges()
	var ip: String = ""
	var label: String = token

	if IpBanList.looks_like_ip(token):
		ip = token
		label = IpBanList.normalize_ip(token)
	else:
		var target: CommandTarget.Result = CommandTarget.resolve(token, peer_id, server_instance)
		if not target.ok:
			return target.error
		if target.account_name.is_empty():
			return "Couldn't resolve an account for that target."
		ip = IpBanList.last_ip_for_account(target.account_name)
		if target.online:
			var live: String = server_instance.world_server.get_peer_client_ip(target.peer_id)
			if not live.is_empty():
				ip = live
		label = target.label()
		if ip.is_empty():
			return "No known IP for %s." % label

	if not IpBanList.unban(ip):
		return "%s [%s] is not IP-banned." % [label, IpBanList.normalize_ip(ip)]
	return "Removed IP ban on %s [%s]." % [label, IpBanList.normalize_ip(ip)]
