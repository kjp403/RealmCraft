extends DataRequestHandler
## Move bag stacks of an item into the personal bank. Starts from the selected
## bag slot, then continues draining other bag slots of the same item_id until
## [code]amount[/code] is satisfied or the vault can't hold more — the mirror of
## [code]bank.withdraw[/code], so Deposit All/Max sweeps every pile of an item
## instead of only the one that was clicked.
##
## Capacity is [member PlayerResource.bank_slots]; stacking into an existing bank
## pile is allowed when full, but opening a new stack is rejected with reason
## "full". Currency (gold) is rejected — it stays in the currency pouch.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.player_resource == null:
		return {"ok": false, "reason": "missing"}
	if player.is_dead:
		return {"ok": false, "reason": "dead"}

	var slot_uid: int = int(args.get("uid", -1))
	var inventory: Dictionary = player.player_resource.inventory
	if slot_uid < 0 or not inventory.has(slot_uid):
		return {"ok": false, "reason": "missing"}

	var slot: Dictionary = inventory[slot_uid]
	var item_id: int = int(slot.get("id", 0))
	var have: int = int(slot.get("a", 0))
	if item_id <= 0 or have <= 0:
		return {"ok": false, "reason": "missing"}

	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	if item != null and item.is_currency:
		return {"ok": false, "reason": "currency"}

	var bank: Dictionary = player.player_resource.bank
	var capacity: int = maxi(BankInteraction.STARTING_SLOTS, player.player_resource.bank_slots)

	# Total held across every bag pile — Deposit All on a split stack (3 + 7 ore)
	# has to mean 10, the same way Withdraw All spans every vault pile.
	var held_total: int = Inventory.count(inventory, item_id)
	var amount: int = int(args.get("amount", have))
	if amount <= 0:
		amount = held_total
	amount = mini(amount, held_total)
	# Fill existing stacks / free slots only — never open past capacity.
	var fit: int = Inventory.max_fit(bank, item_id, capacity, true)
	amount = mini(amount, fit)
	if amount <= 0:
		return {
			"ok": false,
			"reason": "full",
			"inventory": inventory,
			"bank": bank,
			"bank_slots": capacity,
		}

	# Credit the vault BEFORE touching the bag: add_item(in_bank=true) always
	# places the item (an existing pile or one unconditional new slot — see its
	# own docstring), so crediting first means a bug or crash on the removal
	# side below can only DUPLICATE the stack, never erase it.
	Inventory.add_item(bank, item_id, amount, true)

	var remaining: int = amount
	var total_removed: int = 0
	# Prefer the selected slot first, then any other pile of the same item.
	var order: Array[int] = [slot_uid]
	for other_uid: Variant in inventory.keys():
		var ouid: int = int(other_uid)
		if ouid == slot_uid:
			continue
		if int(inventory[ouid].get("id", 0)) == item_id:
			order.append(ouid)
	for uid: int in order:
		if remaining <= 0:
			break
		if not inventory.has(uid):
			continue
		var removed: int = Inventory.remove_from_slot(inventory, uid, remaining)
		remaining -= removed
		total_removed += removed

	if total_removed != amount:
		# Should be unreachable — amount was already capped to held_total — but
		# if it ever fires, the vault credit above stands and the mismatch is
		# a visible duplication instead of the silent bag-drains-vault-doesn't
		# failure this ordering exists to rule out.
		push_error(
			"bank.deposit: removed %d of item %d from bag, expected %d (peer %d)"
			% [total_removed, item_id, amount, peer_id]
		)
	instance.world_server.database.save_player(player.player_resource)
	return {
		"ok": true,
		"moved": total_removed,
		"item_id": item_id,
		"inventory": player.player_resource.inventory,
		"bank": player.player_resource.bank,
		"bank_slots": capacity,
	}
