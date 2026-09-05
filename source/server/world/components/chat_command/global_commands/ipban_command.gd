extends ChatCommand
## Ban a client IP from joining the world. Target may be an online/offline
## player (uses their current or last-known IP) or a raw IPv4/IPv6 string.


func _init() -> void:
	command_name = "ipban"
	command_priority = 2 # admin+
	command_usage = "/ipban <self|@account|#id|ip> [duration] [reason]"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() < 2:
		return "Usage: " + command_usage

	var ws: WorldServer = server_instance.world_server
	var admin: PlayerResource = ws.connected_players.get(peer_id)
	var admin_id: int = admin.player_id if admin else 0

	var args_offset: int = 2
	var duration_ms: int = 0
	var duration_label: String = "permanent"
	if args.size() > 2:
		duration_ms = ChatCommand.parse_duration_ms(args[2])
		if duration_ms > 0:
			args_offset = 3
			duration_label = args[2]
	var reason: String = " ".join(args.slice(args_offset)) if args.size() > args_offset else ""

	var token: String = args[1].strip_edges()
	var ip: String = ""
	var label: String = token
	var kick_peer_id: int = 0

	# Raw IP (contains a dot or multiple colons) — not a player token.
	if IpBanList.looks_like_ip(token):
		ip = token
		label = IpBanList.normalize_ip(token)
	else:
		var target: CommandTarget.Result = CommandTarget.resolve(token, peer_id, server_instance)
		if not target.ok:
			return target.error
		if admin != null and not target.account_name.is_empty() \
				and target.account_name.to_lower() == admin.account_name.to_lower():
			return "You can't IP-ban yourself."
		var staff_block: String = CommandPermissions.staff_moderation_block_reason(
			admin, target, server_instance
		)
		if not staff_block.is_empty():
			return staff_block
		if target.online:
			ip = ws.get_peer_client_ip(target.peer_id)
			kick_peer_id = target.peer_id
		elif not target.account_name.is_empty():
			ip = IpBanList.last_ip_for_account(target.account_name)
		label = target.label()
		if ip.is_empty():
			return (
				"No known IP for %s. They must connect once after this deploy, "
				+ "or pass a raw IP: /ipban 1.2.3.4"
			) % label

	var banned_ip: String = IpBanList.ban(ip, reason, admin_id, duration_ms)
	if banned_ip.is_empty():
		return "Refusing to ban unusable/loopback IP '%s'." % ip

	# Kick everyone currently connected from that IP, with the same wording the
	# login gate will give them when they try to come back.
	var kicked: int = ws.disconnect_peers_with_ip(
		banned_ip, BanNotice.ip_message(IpBanList.ban_info(banned_ip))
	)
	if kick_peer_id != 0 and ws.connected_players.has(kick_peer_id):
		ws.peer.disconnect_peer.call_deferred(kick_peer_id)
		kicked = maxi(kicked, 1)

	var extra: String = " (kicked %d)" % kicked if kicked > 0 else ""
	return "IP-banned %s [%s] for %s.%s" % [label, banned_ip, duration_label, extra]
