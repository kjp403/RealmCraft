extends DataRequestHandler
## Combine two bag or vault stacks of the same item ({"from_uid", "to_uid",
## "in_bank"?}). Moves as many as the destination stack still has room for.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: PlayerResource = instance.world_server.connected_players.get(peer_id)
	if player == null:
		return {"ok": false, "reason": "not_registered"}

	var from_uid: int = int(args.get("from_uid", -1))
	var to_uid: int = int(args.get("to_uid", -1))
	var in_bank: bool = bool(args.get("in_bank", false))
	if from_uid < 0 or to_uid < 0 or from_uid == to_uid:
		return {"ok": false, "reason": "bad_uid"}

	var store: Dictionary = player.bank if in_bank else player.inventory
	var moved: int = Inventory.merge_slots(store, from_uid, to_uid, in_bank)
	if moved <= 0:
		return {"ok": false, "moved": 0, "reason": "no_merge"}
	return {"ok": true, "moved": moved}
