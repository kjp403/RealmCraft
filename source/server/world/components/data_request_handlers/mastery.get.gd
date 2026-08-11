extends DataRequestHandler
## Ships the player's weapon-mastery state for the Mastery tab. Node
## definitions are NOT shipped — trees are common/ content the client already
## has (MasteryService.trees()); only per-player state crosses the wire.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	_args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	var resource: PlayerResource = player.player_resource
	var out: Dictionary = {}
	# Iterate the tree registry (not the player's masteries) so every category
	# that HAS a tree shows up, even at zero practice — mirrors skills.get.
	for category: StringName in MasteryService.trees():
		var tree: MasteryTreeResource = MasteryService.trees()[category]
		# No entry = never killed with this weapon. That still reads as level 1
		# (masteries share the skills' 1–99 curve). Point budget is
		# point_budget(level) — first point at mastery level 3. Read the stored
		# entry directly rather than via get_mastery so a poll doesn't spawn a
		# stub for every tree.
		var entry: Dictionary = {}
		for existing: Variant in resource.masteries.keys():
			if String(existing) == String(category):
				entry = resource.masteries[existing]
				break
		var level: int = maxi(1, int(entry.get("level", 1)))
		out[String(category)] = {
			"level": level,
			"xp": int(entry.get("xp", 0)),
			"xp_to_next": resource.mastery_xp_to_next(level),
			"points": MasteryService.available_points(entry, tree),
			"spent": (entry.get("spent", {}) as Dictionary).keys(),
			"loadout": (resource.ability_loadout.get(String(category), []) as Array).duplicate(),
		}

	# The currently-wielded weapon's category + capacity (= "power" budget for
	# the special slots), so the panel can show how much of it the loadout uses.
	var wielded: Dictionary = {"category": "", "capacity": 0}
	var weapon_item: WeaponItem = player.equipment_component.equipped_items.get(&"weapon", null) as WeaponItem
	if weapon_item != null and not weapon_item.category.is_empty():
		wielded = {"category": String(weapon_item.category), "capacity": weapon_item.capacity}

	return {"ok": true, "masteries": out, "cap": PlayerResource.MASTERY_LEVEL_CAP, "wielded": wielded}
