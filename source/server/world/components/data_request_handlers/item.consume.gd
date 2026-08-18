extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var item_id: int = int(args.get("id", 0))

	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null:
		return {"ok": false, "reason": "player"}

	if player.is_dead:
		return {"ok": false, "reason": "dead"}

	var inventory: Dictionary = player.player_resource.inventory
	if not Inventory.has_item(inventory, item_id):
		return {"ok": false, "reason": "missing"}

	var consumable: ConsumableItem = ContentRegistryHub.load_by_id(
		&"items",
		item_id
	) as ConsumableItem

	if consumable == null:
		return {"ok": false, "reason": "not_consumable"}

	# One weapon coating at a time. Checked ahead of can_use (which also refuses,
	# so the hotbar and the held sip agree) purely so the refusal can be NAMED —
	# "no_effect" would read as "this potion is broken".
	if consumable.is_coating() and CoatingService.is_active(player):
		return {
			"ok": false,
			"reason": "coating_active",
			"active_kind": String(CoatingService.active_kind(player)),
			"remaining": CoatingService.remaining_seconds(player),
		}

	if not consumable.can_use(player):
		return {"ok": false, "reason": "no_effect"}

	var cooldown_key: String = (
		"consumable:" + str(consumable.cooldown_category)
	)

	var consume_ability := ConsumeAbility.new()
	consume_ability.consumable = consumable
	consume_ability.cooldown = (
		float(consumable.shared_cooldown_ms) / 1000.0
	)
	consume_ability.root_s = (
		float(consumable.use_freeze_ms) / 1000.0
	)
	consume_ability.set_meta(&"cooldown_key", cooldown_key)

	if player.ability_cooldowns.has(cooldown_key):
		consume_ability.last_action_time = float(
			player.ability_cooldowns[cooldown_key]
		)

	if not consume_ability.can_use(player):
		return {"ok": false, "reason": "cooldown"}

	consume_ability.use_ability(player, Vector2.ZERO)
	consume_ability.mark_used()

	player.ability_cooldowns[cooldown_key] = (
		consume_ability.last_action_time
	)

	# Bag drinks skip the held ConsumeAbility client freeze. Push the authored
	# root so hotbar chug cannot be done while strafing.
	if consumable.use_freeze_ms > 0 and WorldServer.curr != null:
		WorldServer.curr.data_push.rpc_id(
			peer_id, &"player.rooted", {"ms": consumable.use_freeze_ms}
		)

	return {"ok": true}
