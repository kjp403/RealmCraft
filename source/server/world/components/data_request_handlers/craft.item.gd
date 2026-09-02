extends DataRequestHandler

## Minimum milliseconds between two crafts by the same player, at normal speed.
## The client paces its craft loop at CraftController.CRAFT_INTERVAL (2s); this
## is the authoritative floor, a hair under it so network jitter never eats a
## legitimate craft. An Anvil Stabilizer divides it — see the check below.
const MIN_CRAFT_INTERVAL_MS: int = 1500

## player_id -> {"ms": ticks_msec, "speed": float} for their last accepted
## craft. The handler is cached per request type, so this survives between
## requests.
##
## The SPEED is remembered as well as the time because the client paces the
## wait before its next craft on the speed the last one came back with. If an
## Anvil Stabilizer lapses mid-batch, the client is already half way through a
## fast wait it began in good faith; judging that wait by the new, slower floor
## would refuse it as too_fast and break the batch at the exact moment the buff
## ran out. The floor below therefore judges each craft by the pace the player
## was told to keep, not the one that applies from now on.
var _last_craft: Dictionary[int, Dictionary] = {}


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

	# Resolve the station from the player's map (authoritative + verifies they're at it).
	var station: CraftingStationResource = instance.instance_map.get_crafting_station(station_key)
	if station == null:
		return {"ok": false}
	# Enforce the same walk-up range as client CraftingStation / NPC interact.
	# Resolved from the map's registry, not a get_node() path off the Map root:
	# stations placed inside an instanced sub-scene are not direct children.
	var station_node: Node2D = instance.instance_map.get_crafting_station_node(station_key)
	if station_node == null or player.global_position.distance_to(station_node.global_position) > Interactable.INTERACT_RANGE:
		return {"ok": false, "reason": "too_far"}
	if recipe_index < 0 or recipe_index >= station.recipes.size():
		return {"ok": false}
	var recipe: CraftingRecipe = station.recipes[recipe_index]
	if recipe == null or recipe.output_item == null:
		return {"ok": false}

	var resource: PlayerResource = player.player_resource
	# The profession this ONE craft gates on and pays. Usually the station's, but
	# a bench can host another trade's recipes (the Ascended Workbench holds the
	# metal ascension sets, which stay Smithing). Every check below reads this,
	# never station.profession, or a moved recipe silently trains the wrong skill.
	var prof: StringName = recipe.profession_for(station)

	# Craft pacing floor. The client paces its own loop at
	# CraftController.CRAFT_INTERVAL; this is the authoritative floor, set a hair
	# under it so network jitter never eats a legitimate craft, and so a
	# hand-rolled client cannot spam the request for free xp. An Anvil Stabilizer
	# divides both by AnvilBoost.SPEED_MULTIPLIER, which is why this sits AFTER
	# the station is resolved: the buff is scoped to the station's profession,
	# so the floor is not knowable until we know what is being crafted.
	var speed: float = AnvilBoost.speed_multiplier(resource, prof)
	var previous: Dictionary = _last_craft.get(player_id, {})
	var paced_at: float = maxf(0.01, float(previous.get("speed", speed)))
	var floor_ms: int = int(roundf(float(MIN_CRAFT_INTERVAL_MS) / paced_at))
	if now_ms - int(previous.get("ms", -MIN_CRAFT_INTERVAL_MS)) < floor_ms:
		return {"ok": false, "reason": "too_fast"}

	var inventory: Dictionary = resource.inventory
	var active_bag: int = resource.active_inventory_bag
	var bag_count: int = resource.inventory_bags

	# Crafting-profession level gate.
	var level: int = int((resource.skills.get(prof, {}) as Dictionary).get("level", 1))
	if level < recipe.required_level:
		return {"ok": false, "reason": "level", "required_level": recipe.required_level}

	# Station fee: a flat per-craft gold sink (docs/crafting.md economy guards).
	var fee: int = station.craft_fee
	var gold_id: int = Economy.gold_id()
	if fee > 0 and Inventory.count(inventory, gold_id) < fee:
		return {"ok": false, "reason": "gold", "fee": fee}

	# Verify every input is available before consuming any (atomic craft).
	# `required_inputs()` — not `ingredients` — so a SmeltingRecipe's catalysts
	# are gated here too: a smelt with no crucible must be refused BEFORE the
	# ore is taken, not after.
	for ingredient: CraftIngredient in recipe.required_inputs():
		if ingredient == null or ingredient.item == null:
			continue
		var ing_id: int = int(ingredient.item.get_meta(&"id", 0))
		if Inventory.count(inventory, ing_id) < ingredient.amount:
			return {"ok": false, "reason": "ingredients"}

	# Past every gate — this craft is happening, so start the next cooldown at
	# the pace this one ran at.
	_last_craft[player_id] = {"ms": now_ms, "speed": speed}

	# Perks for this station's profession, resolved once — they drive the refund
	# and extra-item rolls below as well as the XP multiplier further down.
	var perks: JobPerks = JobRegistry.perks_for(prof)
	var player_perks: Dictionary = {}
	if perks != null:
		player_perks = (resource.skills.get(prof, {}) as Dictionary).get("perks", {})

	# Consume ingredients, then the station fee. `refund` rolls PER INGREDIENT
	# UNIT, so a 3-bar helmet can refund 0-3 bars rather than all-or-nothing.
	var refund: float = 0.0 if perks == null else perks.refund_chance(player_perks)
	# Herbalist set: ingredient preservation. Mechanically the same "you get the
	# unit back" as the perk refund, so it folds into the same per-unit roll
	# rather than adding a second pass — two independent rolls would compound
	# into a far higher effective rate than either number suggests. Scoped to the
	# station's profession, so the set does nothing at an anvil.
	refund = minf(
		refund + SkillingOutfitManager.bonus_for(
			player, prof, SkillingOutfitManager.Bonus.PRESERVE
		),
		perks.abs_max_refund_chance if perks != null else 0.5
	)
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

	# Catalyst erosion (SmeltingRecipe only). Rolled per unit, and deliberately
	# NOT folded into the refund pass above: a catalyst's cost IS this roll, so
	# letting a refund perk also apply would quietly halve an authored erosion
	# rate. Tracked so the inventory_full rollback below can put them back.
	var consumed_catalysts: Dictionary[int, int] = {}
	var smelt: SmeltingRecipe = recipe as SmeltingRecipe
	if smelt != null and smelt.catalyst_consume_chance > 0.0:
		for catalyst: CraftIngredient in smelt.catalysts:
			if catalyst == null or catalyst.item == null:
				continue
			var burned: int = 0
			for _u: int in catalyst.amount:
				if randf() < smelt.catalyst_consume_chance:
					burned += 1
			if burned <= 0:
				continue
			var cat_id: int = int(catalyst.item.get_meta(&"id", 0))
			Inventory.remove_amount_by_id(inventory, cat_id, burned)
			consumed_catalysts[cat_id] = consumed_catalysts.get(cat_id, 0) + burned

	# Grant the output (one at a time so stackables merge / non-stackables get slots).
	var output_id: int = int(recipe.output_item.get_meta(&"id", 0))
	# `extra_item` pays one bonus unit of the SAME output — for a batch recipe
	# (10 arrows a craft) that is one extra arrow, not a second batch.
	var output_amount: int = recipe.output_amount
	if perks != null and randf() < perks.extra_item_chance(player_perks):
		output_amount += 1
	# Ingredients already freed space; still gate so a full bag of unrelated gear
	# can't absorb a craft that needs a new square.
	if not Inventory.can_add(
		inventory, output_id, output_amount, Inventory.MAX_SLOTS,
		false, active_bag, bag_count
	):
		# Rollback ingredients + fee so the craft stays atomic. Refunds are only
		# granted below, so there is nothing of theirs to undo here.
		for ingredient: CraftIngredient in recipe.ingredients:
			if ingredient == null or ingredient.item == null:
				continue
			var ing_id: int = int(ingredient.item.get_meta(&"id", 0))
			Inventory.add_item(inventory, ing_id, ingredient.amount, false, active_bag, bag_count)
		# Catalysts eroded by this craft are restored too, or a smelt that fails
		# on a full bag would still quietly eat the crucible.
		for cat_id: int in consumed_catalysts:
			Inventory.add_item(
				inventory, cat_id, consumed_catalysts[cat_id], false, active_bag, bag_count
			)
		if fee > 0:
			Inventory.add_item(inventory, gold_id, fee, false, active_bag, bag_count)
		_last_craft.erase(player_id)
		return {"ok": false, "reason": "inventory_full"}
	for _i: int in output_amount:
		Inventory.try_add_item(
			inventory, output_id, 1, Inventory.MAX_SLOTS,
			false, active_bag, bag_count
		)
	# Refunded ingredients go back last. They came out of the bag moments ago so
	# the space exists; can_add still guards the case where the output claimed
	# the freed square.
	for ing_id: int in refunded:
		var kept: int = refunded[ing_id]
		if Inventory.can_add(
			inventory, ing_id, kept, Inventory.MAX_SLOTS,
			false, active_bag, bag_count
		):
			Inventory.try_add_item(
				inventory, ing_id, kept, Inventory.MAX_SLOTS,
				false, active_bag, bag_count
			)

	# Award crafting-profession xp (perk XP multiplier matches gathering / UI).
	var progress: Dictionary = {}
	var xp_gain: int = 0
	if recipe.xp_reward > 0:
		xp_gain = recipe.xp_reward
		if perks != null:
			xp_gain = maxi(1, roundi(float(xp_gain) * perks.xp_multiplier(player_perks)))
		progress = resource.add_skill_xp(prof, xp_gain)

	# Quest CRAFT progress for this output item. Push unconditionally: an empty
	# messages array is a silent tracker refresh, so a "Bring N item" (COLLECT)
	# objective reflects a freshly-crafted item live, not just on menu reopen.
	var quest_updates: Array = QuestService.on_craft(resource, output_id, peer_id, instance)
	WorldServer.curr.data_push.rpc_id(peer_id, &"quest.update", {"messages": quest_updates})
	# Daily board progress for the station's profession (smithing / cooking /
	# herblore / fletching / outfitting). Counts items PRODUCED, so a batch
	# recipe that makes 10 arrows advances a Fletching daily by 10 rather than
	# by one — the same rule the old "craft N items" counter used.
	SkillingEvents.emit_crafted(resource, prof, output_id, output_amount)

	return {
		"ok": true,
		"output_id": output_id,
		"amount": output_amount,
		"profession": String(prof),
		"xp": xp_gain,
		"level": int(progress.get("level", level)),
		"leveled_up": progress.get("leveled_up", false),
		# The pace the NEXT craft may run at, so the client loop follows an Anvil
		# Stabilizer starting or lapsing mid-batch without polling for it.
		"craft_speed": speed,
	}
