extends DataRequestHandler
## Fired when a player opens an NPC's interactions (i.e. talks to it). Advances any
## VISIT quest objective that targets this giver, so a "talk to NPC X" quest
## completes on conversation — not only when the player drills into the Quests
## sub-menu. No-op (still ok) for NPCs that aren't quest givers in this map.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	var npc_key: StringName = StringName(str(args.get("npc", "")))
	if npc_key.is_empty():
		return {"ok": false}

	# Talking to any named NPC counts as "visiting" it — advance VISIT
	# objectives even when the NPC is not a quest giver (Courier hand-off).
	var visit_updates: Array = QuestService.on_visit(player.player_resource, npc_key, peer_id, instance)
	if not visit_updates.is_empty():
		WorldServer.curr.data_push.rpc_id(peer_id, &"quest.update", {"messages": visit_updates})
	return {"ok": true}
