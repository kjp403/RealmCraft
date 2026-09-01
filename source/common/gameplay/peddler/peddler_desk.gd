class_name PeddlerDesk
## Server-only. The shared half of the Peddler's cart: resolving the NPC a
## request names, and answering "can this player buy this, right now".
##
## Exists so [code]peddler.stock[/code] and [code]peddler.buy[/code] cannot drift.
## Both run the SAME gates, so a row the window draws as buyable is a row the
## purchase handler accepts, and a row it greys out states the real reason.
## Duplicating these checks per handler is how you get a cart that quotes a price
## and then refuses the sale.

## Why a good cannot be bought right now. Empty string = it can.
const LOCK_SOLD_OUT: String = "SOLD OUT"
const LOCK_CLOSED: String = "The cart has packed up."


## Resolves {player, npc, date} from a request, or {reason} on failure. Failure
## dicts still carry "player" once it is known, so a caller can message the person
## it just refused without a second lookup.
##
## The walk-up range check matters: without it a client could buy from across the
## map, or from a map with no Peddler standing in it.
static func resolve(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.player_resource == null:
		return {"reason": "no_player"}
	if player.is_dead:
		return {"reason": "dead", "player": player}
	if JailList.is_jailed(player.player_resource.account_name):
		return {"reason": "jailed", "player": player}

	var station: String = str(args.get("npc", ""))
	if station.is_empty() or instance.instance_map == null:
		return {"reason": "bad_npc", "player": player}

	var node: Node = instance.instance_map.get_node_or_null(NodePath(station))
	if node == null:
		node = instance.instance_map.find_child(station, true, false)
	if node == null or not (node is NPC):
		# The cart despawns on a half-hour clock, so this is the ordinary way a
		# window goes stale — name it as "closed", not as a missing node.
		return {"reason": "closed", "player": player}

	var npc: NPC = node as NPC
	if player.global_position.distance_to(npc.global_position) > NPC.INTERACT_RANGE:
		return {"reason": "too_far", "player": player}
	if PeddlerInteraction.of(npc) == null:
		return {"reason": "no_desk", "player": player}

	return {
		"player": player,
		"npc": npc,
		# Stamped once per request and threaded through everything below, so a
		# purchase that straddles UTC midnight is checked and recorded against ONE
		# day rather than being refused by a stock read from one date and a ledger
		# read from the next.
		"date": PeddlerSchedule.utc_date(),
	}


## Why [param row] is unavailable to [param player] on [param date], or "" when it
## can be bought.
##
## Gold is deliberately NOT checked here. It is reported separately so the window
## can draw an unaffordable row as a price the player is saving toward, rather
## than hiding today's 500,000-gold key from everyone who cannot yet afford it.
static func lock_reason(
	player: Player, row: PeddlerItemData, date: String
) -> String:
	if row == null or not row.is_sellable():
		return "Unavailable."
	if not PeddlerStock.is_stocked(row.id, date):
		return "Not stocked today."
	if PeddlerLedger.has_bought(player.player_resource, row.id, date):
		return LOCK_SOLD_OUT
	return ""


## Registry id of the bag item [param row] hands over, or 0 when the catalog row
## and the items registry disagree. Zero is a CONTENT error (a stock id with no
## matching item .tres, or an index that was never regenerated), and every caller
## must refuse the sale on it rather than charging for nothing.
static func item_id_for(row: PeddlerItemData) -> int:
	if row == null or row.id.is_empty():
		return 0
	return ContentRegistryHub.id_from_slug(&"items", StringName(row.id))
