class_name InventorySpace
extends RefCounted
## "Will this fit?" for a WHOLE hand-off of several item ids at once.
##
## [method Inventory.can_add] answers for one item id against the CURRENT bag, which
## is not the question a trade asks: a swap gives and receives in the same instant
## (so the space your own offer frees is space the incoming items may use), and it
## lands several ids in a row (so each id has to be measured against the bag the
## previous one already filled). Both are answered here by simulating the whole
## hand-off on a copy of the inventory.
##
## Server-side. Callers hold the real inventory dictionary; nothing here mutates it.


## True when [param inventory] can absorb every { item_id: amount } in
## [param incoming] once [param outgoing] (this player's own side of the swap) has
## left it. Currency never consumes a square, so gold can be left out of both.
static func can_receive_all(
	inventory: Dictionary,
	incoming: Dictionary,
	outgoing: Dictionary = {},
	start_bag: int = 0,
	bag_count: int = 1
) -> bool:
	return missing_slots_for(inventory, incoming, outgoing, start_bag, bag_count) <= 0


## How many more squares [param inventory] would need to take [param incoming]
## after [param outgoing] leaves. 0 = it all fits. Drives the "needs 5 more slots"
## half of the player-facing message, so a declined trade says what to fix.
static func missing_slots_for(
	inventory: Dictionary,
	incoming: Dictionary,
	outgoing: Dictionary = {},
	start_bag: int = 0,
	bag_count: int = 1
) -> int:
	var simulated: Dictionary = inventory.duplicate(true)
	for raw_id: Variant in outgoing:
		Inventory.remove_amount_by_id(simulated, int(raw_id), int(outgoing[raw_id]))

	var bags: int = maxi(1, bag_count)
	var missing: int = 0
	for raw_id: Variant in incoming:
		var item_id: int = int(raw_id)
		var amount: int = int(incoming[raw_id])
		if item_id <= 0 or amount <= 0:
			continue
		# try_add_item only writes when the FULL amount fits, so a rejected id
		# leaves the simulation untouched — later ids are still measured against
		# the same bag, and the shortfall accumulates across every rejected id.
		if Inventory.try_add_item(
			simulated, item_id, amount, Inventory.MAX_SLOTS, false, start_bag, bags
		):
			continue
		missing += maxi(
			1,
			Inventory.slots_needed(simulated, item_id, amount, false, -1)
				- Inventory.free_slots(simulated, Inventory.MAX_SLOTS * bags, -1)
		)
	return missing
