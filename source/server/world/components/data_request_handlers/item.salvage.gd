extends DataRequestHandler
## Break a bag stack down into materials (see [SalvageTable]).
##
## Deliberately NOT a crafting station: breaking down is a bag action the player
## does anywhere, and routing it through `craft.item` would have meant one
## authored recipe per salvageable weapon sitting in the Alchemy brew list.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.player_resource == null:
		return {"ok": false, "reason": "missing"}
	# Same death gate every other item action carries (see item.equip.gd).
	if player.is_dead:
		return {"ok": false, "reason": "dead"}

	var slot_uid: int = int(args.get("uid", -1))
	var resource: PlayerResource = player.player_resource
	var inventory: Dictionary = resource.inventory
	if slot_uid < 0 or not inventory.has(slot_uid):
		return {"ok": false, "reason": "missing"}

	var slot: Dictionary = inventory[slot_uid]
	var item_id: int = int(slot.get("id", 0))
	var have: int = int(slot.get("a", 0))
	if item_id <= 0 or have <= 0:
		return {"ok": false, "reason": "missing"}

	# Favouriting an item means "don't touch this". Dropping is recoverable off
	# the ground; breaking down is not, so it is the one action that honours the
	# pin rather than treating it as a sort hint.
	if bool(slot.get("p", false)):
		return {"ok": false, "reason": "pinned"}

	var table: SalvageTable = SalvageTable.shared()
	if table == null:
		return {"ok": false, "reason": "missing"}
	var recipe: SalvageRecipe = table.recipe_for(item_id)
	if recipe == null or recipe.outputs.is_empty():
		return {"ok": false, "reason": "cant_salvage"}

	var level: int = int((resource.skills.get(table.profession, {}) as Dictionary).get("level", 1))
	if level < recipe.required_level:
		# Its own reason, not the shared "level": that one is already spoken for
		# by the equip gate and reads as "Requires level N to equip".
		return {
			"ok": false,
			"reason": "salvage_level",
			"required_level": recipe.required_level,
			"profession": String(table.profession),
		}

	var amount: int = maxi(1, int(args.get("amount", 1)))
	amount = mini(amount, have)

	# Consume first: the freed slots are exactly what makes room for the yield
	# (a 28/28 bag holding one last sword still breaks it down).
	var removed: int = Inventory.remove_from_slot(inventory, slot_uid, amount)
	if removed <= 0:
		return {"ok": false, "reason": "missing"}

	# Every output has to fit or none of it happens. Outputs are distinct items,
	# so their independent slot needs sum cleanly.
	#
	# Random yields (rustic weapons pay 1-3 bars) are rolled PER UNIT here on the
	# server — breaking 5 at once gives five independent rolls, not one roll
	# multiplied, and the client never gets to pick the number.
	var yields: Dictionary[int, int] = {}
	var needed: int = 0
	for output: SalvageOutput in recipe.outputs:
		if output == null or output.item == null or output.max_amount <= 0:
			continue
		var out_id: int = int(output.item.get_meta(&"id", 0))
		if out_id <= 0:
			continue
		var total: int = 0
		for _unit: int in removed:
			total += output.roll()
		if total <= 0:
			continue
		yields[out_id] = int(yields.get(out_id, 0)) + total
		needed += Inventory.slots_needed(inventory, out_id, total)
	# Space is counted across every unlocked bag, not just the open tab: the
	# stack being broken down can free a square in one bag while the materials
	# land in another.
	var active_bag: int = resource.active_inventory_bag
	var bag_count: int = resource.inventory_bags
	if yields.is_empty() or needed > Inventory.total_free_slots(inventory, bag_count):
		Inventory.add_item(inventory, item_id, removed, false, active_bag, bag_count)
		return {"ok": false, "reason": "inventory_full"}

	for out_id: int in yields:
		Inventory.try_add_item(
			inventory, out_id, yields[out_id], Inventory.MAX_SLOTS,
			false, active_bag, bag_count
		)

	# Herblore xp, run through the same perk multiplier crafting uses so Green
	# Thumb pays out consistently across the whole skill.
	var progress: Dictionary = {}
	var xp_gain: int = recipe.xp_reward * removed
	if xp_gain > 0:
		var perks: JobPerks = JobRegistry.perks_for(table.profession)
		if perks != null:
			var player_perks: Dictionary = (
				resource.skills.get(table.profession, {}) as Dictionary
			).get("perks", {})
			xp_gain = maxi(1, roundi(float(xp_gain) * perks.xp_multiplier(player_perks)))
		progress = resource.add_skill_xp(table.profession, xp_gain)

	var granted: Array = []
	for out_id: int in yields:
		granted.append({"id": out_id, "amount": yields[out_id]})

	return {
		"ok": true,
		"id": item_id,
		"amount": removed,
		"granted": granted,
		"profession": String(table.profession),
		"level": int(progress.get("level", level)),
		"leveled_up": progress.get("leveled_up", false),
	}
