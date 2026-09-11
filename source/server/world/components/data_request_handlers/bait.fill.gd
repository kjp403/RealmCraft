extends DataRequestHandler
## Sweeps every loose Fish Bait stack out of the bags and into the Bottomless Bait
## Bucket. Fired straight from the bag's right-click "Fill" row — there is nothing
## to choose, so there is no panel.
##
## The `id` arg the inventory dock sends is deliberately IGNORED. The bucket is not
## a stack the player picked; it is a single per-character charge, and BaitBucket
## re-derives ownership from the registry. Trusting a client-sent id here would let
## a crafted packet name any item as "the bucket".


func data_request_handler(peer_id: int, instance: ServerInstance, _args: Dictionary) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.player_resource == null:
		return {"ok": false, "reason": "no_player"}

	var result: Dictionary = BaitBucket.fill_from_inventory(player.player_resource)
	# Every branch answers with the SAME status block, refusals included. The
	# client mirrors the bucket off this reply (ClientState.apply_bait_payload),
	# and the refusal paths used to omit `stored` — so a Fill that bounced off a
	# full bucket left the hover card showing whatever it last saw, which on a
	# first-session player was zero.
	result.merge(BaitBucket.status_payload(player.player_resource), true)
	return result
