extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	var pr: PlayerResource = player.player_resource
	if pr.available_attributes_points <= 0:
		return {"ok": false, "points": pr.available_attributes_points}

	# Normalize first: the client sends "strength" while the table used to be
	# keyed "strenght", so unnormalized names failed silently here — the client
	# had already applied the point locally, and the build vanished on respawn.
	var attr: StringName = AttributeMap.normalize(StringName(str(args.get("attr", ""))))
	var gained_stats: Dictionary = AttributeMap.stats_for(attr)
	if gained_stats.is_empty():
		# Unknown / invalid attribute name.
		return {"ok": false, "points": pr.available_attributes_points}

	# Record in the persisted attributes dict: this is the source of truth and is
	# re-applied to stats on every spawn (see InstanceServer setup_new_player).
	pr.attributes[attr] = int(pr.attributes.get(attr, 0)) + 1
	# Apply to the live stats right now so the change is immediate.
	for stat_name: StringName in gained_stats:
		player.stats_component.modify_stat(stat_name, gained_stats[stat_name])

	pr.available_attributes_points -= 1
	return {"ok": true, "points": pr.available_attributes_points}
