class_name QuickTravelDesk
## Server-only. The shared half of quick travel: resolving the desk a request
## names, and deciding whether one destination is bookable by one player.
##
## This exists so [code]travel.quote[/code] and [code]travel.quick[/code] cannot
## drift apart. Both run the SAME gate function, so a row the window draws as
## bookable is a row the booking handler will accept — and a row it greys out
## states the real reason. Duplicating these checks per handler is how you get a
## desk that quotes a fare and then refuses the ride.

## Why a destination cannot be taken right now. Empty string = it can.
const LOCK_HERE: String = "You are already here."
const LOCK_DEAD: String = "You cannot travel while dead."

## Registry slug of the good that opens this board remotely.
const SCROLL_SLUG: StringName = &"biome_recall_scroll"
## Where the scroll reads its routes from. It sells the WAYFARER'S board, so the
## stops stay authored in exactly one place; a second list on the scroll would be
## one to forget the next time a destination is added.
const WAYFARER_RES: String = "res://source/common/gameplay/characters/npc/npcs/wayfarer.tres"


## Resolves {player, npc, desk} from a request, or {reason} on failure. Failure
## dicts still carry "player" once it is known, so a caller can message the person
## it just refused without looking them up a second time.
## Mirrors npc.warp's resolution (direct child first, then a deep search) so the
## Wayfarer works whether it sits at the map root or under an NPCs/ container.
static func resolve(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.player_resource == null:
		return {"reason": "no_player"}
	if player.is_dead:
		return {"reason": "dead", "player": player}
	if JailList.is_jailed(player.player_resource.account_name):
		return {"reason": "jailed", "player": player}

	# A Biome Recall Scroll carries the desk with it: no NPC node to find, and no
	# walk-up range to check, because the whole good is "book a ride from here".
	if bool(args.get("scroll", false)):
		return _resolve_scroll(player)

	var station: String = str(args.get("npc", ""))
	if station.is_empty() or instance.instance_map == null:
		return {"reason": "bad_npc", "player": player}

	var node: Node = instance.instance_map.get_node_or_null(NodePath(station))
	if node == null:
		node = instance.instance_map.find_child(station, true, false)
	if node == null or not (node is NPC):
		return {"reason": "npc_missing", "player": player}

	var npc: NPC = node as NPC
	# Same walk-up rule every other NPC capability uses: you must be AT the desk.
	# Without this a client could book from across the map, or from a map that
	# has no Wayfarer at all.
	if player.global_position.distance_to(npc.global_position) > NPC.INTERACT_RANGE:
		return {"reason": "too_far", "player": player}

	var desk: QuickTravelInteraction = QuickTravelInteraction.of(npc)
	if desk == null:
		return {"reason": "no_desk", "player": player}
	return {"player": player, "npc": npc, "desk": desk}


## Resolution for a scroll ride. Returns the same {player, desk} shape plus the
## scroll's item id, so the booking handler can spend the exact stack it verified.
##
## HOLDING THE SCROLL IS THE CREDENTIAL, and it is checked HERE rather than trusted
## from the client. Both handlers route through this function, so a forged
## scroll:true buys nothing: without a scroll in the bag it is refused before a
## fare is waived or a route is quoted.
static func _resolve_scroll(player: Player) -> Dictionary:
	var scroll_id: int = ContentRegistryHub.id_from_slug(&"items", SCROLL_SLUG)
	if scroll_id <= 0:
		# The slug does not resolve — a stale items index, not a missing scroll.
		return {"reason": "no_scroll", "player": player}
	if not Inventory.has_item(player.player_resource.inventory, scroll_id):
		return {"reason": "no_scroll", "player": player}

	var wayfarer: NPCResource = load(WAYFARER_RES) as NPCResource
	var desk: QuickTravelInteraction = QuickTravelInteraction.in_resource(wayfarer)
	if desk == null:
		return {"reason": "no_desk", "player": player}
	return {
		"player": player,
		"npc": null,
		"desk": desk,
		"scroll": true,
		"scroll_id": scroll_id,
	}


## Why [param dest] is unavailable to [param player] standing in [param instance],
## or "" when it can be booked. Gold is deliberately NOT checked here: it is
## quoted separately so the window can show an affordable/unaffordable row rather
## than hiding the destination a player is saving up for.
static func lock_reason(
	player: Player,
	instance: ServerInstance,
	dest: QuickTravelDestination
) -> String:
	if dest == null or dest.target_instance == null:
		return "Unavailable."
	if player.is_dead:
		return LOCK_DEAD
	if is_current(instance, dest):
		return LOCK_HERE
	# Wardstone progression gate — the same check every door into a zone runs, so
	# quick travel can never be a way around the critical path.
	if not dest.target_instance.can_join_instance(player):
		var stone: String = String(dest.target_instance.required_wardstone).replace("_", " ")
		return "Needs the %s wardstone." % stone
	return ""


## True when [param dest] points at the map the player is already standing in.
## Compared by instance_name rather than resource identity: the name is the stable
## key the rest of the server routes on.
static func is_current(instance: ServerInstance, dest: QuickTravelDestination) -> bool:
	if instance.instance_resource == null or dest.target_instance == null:
		return false
	return instance.instance_resource.instance_name == dest.target_instance.instance_name
