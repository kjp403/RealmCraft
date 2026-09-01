extends DataRequestHandler
## Use one Traveling Peddler good from the bag. Args: {id: item_registry_id}.
##
## The bag dock routes a [PeddlerGoodItem]'s primary action here rather than to
## [code]item.consume[/code], because these are not [ConsumableItem]s: they have
## no heal/mana/buff fields, no draught slot and no drink cooldown, and every one
## of those checks would refuse them by the wrong name.
##
## The effect lives on the CATALOG row's action_script, not on the bag item, so
## "what does the Anvil Stabilizer do" has one home next to its price and its
## tier. The item is consumed only after the action reports success — an action
## that cannot finish (bag full for the seed's harvest) must leave the good in
## the bag rather than half-applying.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.player_resource == null:
		return {"ok": false, "reason": "player"}
	if player.is_dead:
		return {"ok": false, "reason": "dead"}

	var item_id: int = int(args.get("id", 0))
	if item_id <= 0:
		return {"ok": false, "reason": "missing"}

	var resource: PlayerResource = player.player_resource
	if not Inventory.has_item(resource.inventory, item_id):
		return {"ok": false, "reason": "missing"}

	var good: PeddlerGoodItem = ContentRegistryHub.load_by_id(&"items", item_id) as PeddlerGoodItem
	if good == null:
		return {"ok": false, "reason": "not_peddler_good"}
	if not good.usable:
		return {"ok": false, "reason": "no_action"}

	var row: PeddlerItemData = good.stock_row()
	if row == null or row.action_script == null:
		# The item says it is usable but its catalog row has no action — an
		# authoring mismatch. Refuse by name; do NOT eat the item.
		return {"ok": false, "reason": "no_action"}

	# Instantiated and type-checked, the way WorldServer builds a
	# DataRequestHandler: a row pointed at the wrong script fails here, loudly,
	# instead of silently doing nothing to a good the player paid for.
	var action: PeddlerAction = row.action_script.new() as PeddlerAction
	if action == null:
		push_error("peddler.use: '%s' action_script is not a PeddlerAction." % row.id)
		return {"ok": false, "reason": "no_action"}

	# Re-check liveness right before the effect: resolving the row above can span
	# a frame, and an action must never run for a player who died in between.
	if player.is_dead or not Inventory.has_item(resource.inventory, item_id):
		return {"ok": false, "reason": "missing"}

	# THE CONSUME GATE. Everything above this line is a check; nothing below it
	# runs unless the action reported success. An action that returns ok=false —
	# for any reason, including one it invented — leaves the item in the bag and
	# nothing is written. This is the only place a peddler good is ever spent.
	var result: Dictionary = action.apply(player, instance)
	if not result.get("ok", false):
		# Pass the action's own refusal through untouched so the bag dock can name
		# it ("no live contract", "your bag is full") instead of a generic failure.
		result["ok"] = false
		return result

	if action.consumes() and not Inventory.remove_amount_by_id(resource.inventory, item_id, 1):
		# The action already ran and cannot be unwound generically, so this must
		# not be reachable — has_item was checked above and nothing between here
		# and there touches the bag. Log it rather than silently granting a
		# repeatable effect.
		push_error("peddler.use: '%s' applied but could not be consumed." % row.id)

	if WorldServer.curr != null and WorldServer.curr.database != null:
		WorldServer.curr.database.save_player(resource)

	result["id"] = row.id
	result["item_id"] = item_id
	return result
