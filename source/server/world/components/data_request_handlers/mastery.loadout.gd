extends DataRequestHandler
## Sets a category's special-ability loadout: an ORDERED array of owned
## ability-node ids (max 4 — slot POSITION maps to the Q / E / R / C inputs; ""
## marks a deliberately empty slot so a pick can sit on R with Q free). An empty
## array clears everything. Works from anywhere — the server is the
## authority, no NPC gatekeeper — EXCEPT mid-spar/duel, where swapping
## abilities would dodge the fight you signed up for.
##
## No weapon-capacity budget: owned picks always channel when the matching
## weapon type is held. Storing intent beats erroring on it.

## Q / E / R / C. Must stay in step with EquipmentComponent.SPECIAL_SLOTS and
## the client SLOT_KEYS lists.
const MAX_PICKS: int = 4


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var category: StringName = StringName(str(args.get("category", "")))
	if category.is_empty():
		return {"ok": false}

	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}
	var resource: PlayerResource = player.player_resource
	if resource.in_match:
		return {"ok": false, "reason": "in_match"}

	var picks_v: Variant = args.get("nodes", [])
	var picks: Array = picks_v if picks_v is Array else []
	if picks.size() > MAX_PICKS:
		return {"ok": false, "reason": "too_many"}

	var tree: MasteryTreeResource = MasteryService.tree_for(category)
	if tree == null:
		return {"ok": false, "reason": "no_tree"}
	var entry: Dictionary = resource.masteries.get(category, {})
	var spent: Dictionary = entry.get("spent", {})
	# A maxed tree grants every ability outright, so ownership is no longer
	# "did you buy it" — see MasteryService.has_full_unlock.
	var full_unlock: bool = MasteryService.has_full_unlock(entry)

	var validated: Array = []
	var seen_chains: Dictionary = {} # chain root -> true: one tier of a move max
	for pick in picks:
		var node_id: String = str(pick)
		if node_id.is_empty():
			validated.append("") # deliberate hole — keeps later picks on their key
			continue
		if validated.has(node_id):
			return {"ok": false, "reason": "duplicate"}
		var node: MasteryNode = tree.get_node_by_id(StringName(node_id))
		if node == null:
			# REMOVED CONTENT (a trimmed top rank), not a bad request: the player
			# still carries the dead id in their stored loadout and the client
			# resends it with every edit. Rejecting the whole array froze those
			# players out of equipping anything at all — drop it to an empty
			# slot instead, which also self-heals the stored loadout on write.
			# Same policy as MasteryService.spent_cost (gone = costs nothing).
			validated.append("")
			continue
		if node.ability == null:
			return {"ok": false, "reason": "unknown_node"}
		if not full_unlock and not spent.has(node_id):
			return {"ok": false, "reason": "not_owned"}
		# A signature move occupies ONE slot — can't slot two tiers of it.
		var root: String = String(MasteryService.chain_root_of(tree, node))
		if seen_chains.has(root):
			return {"ok": false, "reason": "same_chain"}
		seen_chains[root] = true
		# Store the EXACT tier the player chose. They may deliberately channel a
		# lighter tier of a chain to free weapon power for another ability.
		validated.append(node_id)

	# Trailing holes carry no information — trim so "cleared everything"
	# stores as no entry at all.
	while not validated.is_empty() and str(validated[validated.size() - 1]).is_empty():
		validated.pop_back()
	if validated.is_empty():
		resource.ability_loadout.erase(String(category))
	else:
		resource.ability_loadout[String(category)] = validated
	MasteryService.refresh(player)
	return {"ok": true}
