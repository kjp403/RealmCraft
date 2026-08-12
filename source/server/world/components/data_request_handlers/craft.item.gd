extends DataRequestHandler

## Minimum seconds between two crafts by the same player. The client paces its
## craft loop at CraftingMenu.CRAFT_INTERVAL (2s); this is the authoritative
## floor so a hand-rolled client can't spam the request for free xp. Set a hair
## under the client interval so network jitter never eats a legitimate craft.
const MIN_CRAFT_INTERVAL_MS: int = 1500

## player_id -> ticks_msec of their last accepted craft. The handler is cached
## per request type, so this survives between requests.
var _last_craft_ms: Dictionary[int, int] = {}


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var station_key: StringName = StringName(str(args.get("station_key", "")))
	var recipe_index: int = int(args.get("recipe", -1))

	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	var player_id: int = int(player.player_resource.player_id)
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - int(_last_craft_ms.get(player_id, -MIN_CRAFT_INTERVAL_MS)) < MIN_CRAFT_INTERVAL_MS:
		return {"ok": false, "reason": "too_fast"}

	# Resolve the station from the player's map (authoritative + verifies they're at it).
	var station: CraftingStationResource = instance.instance_map.get_crafting_station(station_key)
	if station == null:
		return {"ok": false}
	# Enforce the same walk-up range as client CraftingStation / NPC interact.
	var station_node: Node2D = instance.instance_map.get_node_or_null(NodePath(String(station_key))) as Node2D
	if station_node == null or player.global_position.distance_to(station_node.global_position) > CraftingStation.INTERACT_RANGE:
		return {"ok": false, "reason": "too_far"}
	if recipe_index < 0 or recipe_index >= station.recipes.size():
		return {"ok": false}
	var recipe: CraftingRecipe = station.recipes[recipe_index]
	if recipe == null or recipe.output_item == null:
		return {"ok": false}

	var resource: PlayerResource = player.player_resource
	var inventory: Dictionary = resource.inventory

	# Crafting-profession level gate.
	var level: int = int((resource.skills.get(station.profession, {}) as Dictionary).get("level", 1))
	if level < recipe.required_level:
		return {"ok": false, "reason": "level", "required_level": recipe.required_level}

	# Station fee: a flat per-craft gold sink (docs/crafting.md economy guards).
	var fee: int = station.craft_fee
	var gold_id: int = Economy.gold_id()
	if fee > 0 and Inventory.count(inventory, gold_id) < fee:
		return {"ok": false, "reason": "gold", "fee": fee}

	# Verify every ingredient is available before consuming any (atomic craft).
	for ingredient: CraftIngredient in recipe.ingredients:
		if ingredient == null or ingredient.item == null:
			continue
		var ing_id: int = int(ingredient.item.get_meta(&"id", 0))
		if Inventory.count(inventory, ing_id) < ingredient.amount:
			return {"ok": false, "reason": "ingredients"}

	# Past every gate — this craft is happening, so start the next cooldown.
	_last_craft_ms[player_id] = now_ms

	# Perks for this station's profession, resolved once — they drive the refund
	# and extra-item rolls below as well as the XP multiplier further down.
	var perks: JobPerks = JobRegistry.perks_for(station.profession)
	var player_perks: Dictionary = {}
	if perks != null:
		player_perks = (resource.skills.get(station.profession, {}) as Dictionary).get("perks", {})

	# Consume ingredients, then the station fee. `refund` rolls PER INGREDIENT
	# UNIT, so a 3-bar helmet can refund 0-3 bars rather than all-or-nothing.
	var refund: float = 0.0 if perks == null else perks.refund_chance(player_perks)
	var refunded: Dictionary[int, int] = {}
	for ingredient: CraftIngredient in recipe.ingredients:
		if ingredient == null or ingredient.item == null:
			continue
		var ing_id: int = int(ingredient.item.get_meta(&"id", 0))
		Inventory.remove_amount_by_id(inventory, ing_id, ingredient.amount)
		if refund <= 0.0:
			continue
		var kept: int = 0
		for _u: int in ingredient.amount:
			if randf() < refund:
				kept += 1
		if kept > 0:
			refunded[ing_id] = kept
	if fee > 0:
		Inventory.remove_amount_by_id(inventory, gold_id, fee)

	# Grant the output (one at a time so stackables merge / non-stackables get slots).
	var output_id: int = int(recipe.output_item.get_meta(&"id", 0))
	# `extra_item` pays one bonus unit of the SAME output — for a batch recipe
	# (10 arrows a craft) that is one extra arrow, not a second batch.
	var output_amount: int = recipe.output_amount
	if perks != null and randf() < perks.extra_item_chance(player_perks):
		output_amount += 1
	# Ingredients already freed space; still gate so a full bag of unrelated gear
	# can't absorb a craft that needs a new square.
	if not Inventory.can_add(inventory, output_id, output_amount):
		# Rollback ingredients + fee so the craft stays atomic. Refunds are only
		# granted below, so there is nothing of theirs to undo here.
		for ingredient: CraftIngredient in recipe.ingredients:
			if ingredient == null or ingredient.item == null:
				continue
			var ing_id: int = int(ingredient.item.get_meta(&"id", 0))
			Inventory.add_item(inventory, ing_id, ingredient.amount)
		if fee > 0:
			Inventory.add_item(inventory, gold_id, fee)
		_last_craft_ms.erase(player_id)
		return {"ok": false, "reason": "inventory_full"}
	for _i: int in output_amount:
		Inventory.try_add_item(inventory, output_id, 1)
	# Refunded ingredients go back last. They came out of the bag moments ago so
	# the space exists; can_add still guards the case where the output claimed
	# the freed square.
	for ing_id: int in refunded:
		var kept: int = refunded[ing_id]
		if Inventory.can_add(inventory, ing_id, kept):
			Inventory.try_add_item(inventory, ing_id, kept)

	# Award crafting-profession xp (perk XP multiplier matches gathering / UI).
	var progress: Dictionary = {}
	if recipe.xp_reward > 0:
		var xp_gain: int = recipe.xp_reward
		if perks != null:
			xp_gain = maxi(1, roundi(float(xp_gain) * perks.xp_multiplier(player_perks)))
		progress = resource.add_skill_xp(station.profession, xp_gain)

	# Quest CRAFT progress for this output item. Push unconditionally: an empty
	# messages array is a silent tracker refresh, so a "Bring N item" (COLLECT)
	# objective reflects a freshly-crafted item live, not just on menu reopen.
	var quest_updates: Array = QuestService.on_craft(resource, output_id, peer_id, instance)
	WorldServer.curr.data_push.rpc_id(peer_id, &"quest.update", {"messages": quest_updates})
	# Daily "craft N items" progress — count the items produced this craft.
	DailyQuestService.on_craft(resource, output_amount)

	return {
		"ok": true,
		"output_id": output_id,
		"amount": output_amount,
		"profession": String(station.profession),
		"level": int(progress.get("level", level)),
		"leveled_up": progress.get("leveled_up", false),
	}
