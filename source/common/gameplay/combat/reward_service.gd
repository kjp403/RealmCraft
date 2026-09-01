class_name RewardService
## Distributes a mob kill's rewards — XP, loot, weapon-mastery XP, quest + daily
## progress, basing glory, the PvE leaderboard, and level-milestone unlocks — to
## EVERY player who meaningfully damaged the mob, not just the last hitter. Lifted
## out of HostileNpc so the mob class stays "AI + combat": overworld mobs, dungeon
## bosses, and world bosses all reward through here. A mob with no xp_reward AND no
## loot (a dungeon "shadow") grants nothing, so it's skipped wholesale.
## Server-only.

## A player must have dealt at least this fraction of the mob's max HP to share in
## the kill (anti-leech). The killer is always included regardless. Bosses use a
## zero bar so anyone who tagged them still gets a drop-table roll — a last-hit
## steal cannot wipe the people who actually fought the boss.
const MIN_DAMAGE_FRACTION: float = 0.1
const BOSS_MIN_DAMAGE_FRACTION: float = 0.0
## Ground piles stay reserved to their earner for this long (anti-ninja).
const LOOT_EXCLUSIVE_MS: int = 60_000
## Fallback ornate chest id (pink / 249) when a boss leaves ornate_chest_item empty.
## Ranked grants use the boss's authored color item when set.
const ORNATE_CHEST_IDS: Array[int] = [249]


## [param contributors] = player_id -> total damage dealt this life (HostileNpc
## tracks it by persistent id so a reconnect still pays). Server-only.
static func distribute(npc: HostileNpc, contributors: Dictionary, killer: Character) -> void:
	if not GameMode.is_world_server():
		return
	# is_boss lives on EnemyTypeResource — HostileNPC never copied it, so bare
	# npc.is_boss crashed distribute() and wiped XP/loot for every kill.
	var is_boss: bool = (
		npc.enemy_data != null and bool(npc.enemy_data.is_boss)
	)
	# A body worth no XP, no loot and no chest still COUNTS: dungeon trash and the
	# adds a boss summons are stripped of their payout by RoomNode.make_dungeon_mob,
	# and returning here used to strip their quest / daily / Slayer credit with it —
	# which is why the Goblin Chief's runts advanced nothing. Only a body nobody can
	# earn credit for (no enemy_type to match a task or objective on) is skipped.
	if npc.enemy_type == &"" and npc.xp_reward <= 0 \
			and (npc.loot == null or npc.loot.is_empty()) \
			and not _has_ranked_ornate_chests(npc):
		return # a true shadow — nothing to give and nothing to advance
	var frac: float = BOSS_MIN_DAMAGE_FRACTION if is_boss else MIN_DAMAGE_FRACTION
	var threshold: float = npc.stats_component.get_stat(Stat.HEALTH_MAX) * frac
	var killer_id: int = -1
	if killer is Player and (killer as Player).player_resource != null:
		killer_id = int((killer as Player).player_resource.player_id)

	# Build the eligible set, then sort by damage so DPS-ranked chest grants
	# (Mecha Golem ornate chests) know #1 / #2 / everyone else.
	var ranked: Array[Dictionary] = []
	var seen: Dictionary[int, bool] = {}
	for player_id: int in contributors:
		if player_id != killer_id and float(contributors[player_id]) < threshold:
			continue
		ranked.append({
			"player_id": player_id,
			"dmg": float(contributors[player_id]),
		})
		seen[player_id] = true
	if killer_id > 0 and not seen.has(killer_id):
		ranked.append({
			"player_id": killer_id,
			"dmg": float(contributors.get(killer_id, 0.0)),
		})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["dmg"]) > float(b["dmg"])
	)

	for rank: int in ranked.size():
		var player_id: int = int(ranked[rank]["player_id"])
		var player: Player = _resolve_player_by_id(player_id)
		if player != null:
			# Each contributor gets their own loot roll, reserved to THEM for 60s
			# so nearby players can't ninja-loot (top damager included). Ranked
			# ornate chests (if authored) append on top of the table roll.
			var reserved_peer: int = int(player.player_resource.current_peer_id)
			_reward(player, npc, reserved_peer, _roll_ranked_ornate_chests(rank, npc))
			seen[player_id] = true

	_share_party_xp(npc, seen)


## Party members standing near a contributor share character + mastery XP (not
## loot / quest / Slayer — those still need a tag). Radius is PartyService.
static func _share_party_xp(npc: HostileNpc, already: Dictionary) -> void:
	if npc == null or npc.xp_reward <= 0:
		return
	var extra: Dictionary[int, Player] = {}
	for player_id: Variant in already:
		var player: Player = _resolve_player_by_id(int(player_id))
		if player == null:
			continue
		for mate: Player in PartyService.nearby_members(player, PartyService.XP_SHARE_RADIUS):
			if mate.player_resource == null:
				continue
			var mate_id: int = int(mate.player_resource.player_id)
			if already.has(mate_id) or extra.has(mate_id):
				continue
			extra[mate_id] = mate
	for mate_id: int in extra:
		_reward_shared_xp(extra[mate_id], npc)


## XP-only payout for a nearby party member who did not tag the kill.
static func _reward_shared_xp(player: Player, npc: HostileNpc) -> void:
	var resource: PlayerResource = player.player_resource
	if resource == null:
		return
	var level_before: int = resource.level
	resource.add_experience(npc.xp_reward)
	var skill_xp: int = npc.combat_skill_xp() if npc.grants_skill_xp else 0
	var mastery: Dictionary = {}
	var weapon_item: WeaponItem = player.equipment_component.equipped_items.get(&"weapon", null) as WeaponItem
	if skill_xp > 0 and weapon_item != null and not weapon_item.category.is_empty():
		mastery = resource.add_mastery_xp(weapon_item.category, skill_xp)
	var peer_id: int = int(resource.current_peer_id)
	if peer_id > 0 and (npc.xp_reward > 0 or not mastery.is_empty()):
		WorldServer.curr.data_push.rpc_id(peer_id, &"combat.reward", {
			"enemy_type": npc.enemy_type,
			"xp": npc.xp_reward,
			"level": resource.level,
			"levels_gained": resource.level - level_before,
			"points_gained": PlayerResource.attribute_points_at_level(resource.level)
				- PlayerResource.attribute_points_at_level(level_before),
			"experience": resource.experience,
			"xp_to_next": resource.level_xp_to_next(),
			"loot": [],
			"ground": true,
			"mastery": mastery,
			"shared": true,
		})
	if resource.level > level_before:
		var inst: Node = WorldServer.curr.instance_manager.find_instance_for_peer(peer_id) if peer_id > 0 else null
		LevelMilestoneService.on_levels_gained(resource, level_before, resource.level, inst)


static func _has_ranked_ornate_chests(npc: HostileNpc) -> bool:
	return npc.enemy_data != null and npc.enemy_data.ornate_chest_top_max > 0


## Ranked ornate grants for eligible damage contributors:
## - Rank 0 (top DPS): [ornate_chest_top_min, ornate_chest_top_max]
## - Rank 1: [ornate_chest_second_min, ornate_chest_second_max] when second_max > 0
## - All other ranks (and rank 1 when second is unused): 1 chest at
##   ornate_chest_consolation_chance. Solo killers are always rank 0.
static func _roll_ranked_ornate_chests(rank: int, npc: HostileNpc) -> Array:
	var d: EnemyTypeResource = npc.enemy_data
	if d == null or d.ornate_chest_top_max <= 0:
		return []
	var count: int = 0
	if rank == 0:
		count = randi_range(
			maxi(0, d.ornate_chest_top_min),
			maxi(0, d.ornate_chest_top_max)
		)
	elif rank == 1 and d.ornate_chest_second_max > 0:
		count = randi_range(
			maxi(0, d.ornate_chest_second_min),
			maxi(0, d.ornate_chest_second_max)
		)
	elif rank >= 1 and d.ornate_chest_consolation_chance > 0.0:
		if randf() < d.ornate_chest_consolation_chance:
			count = 1
	if count <= 0:
		return []
	var chest_id: int = 0
	if d.ornate_chest_item != null:
		chest_id = int(d.ornate_chest_item.get_meta(&"id", 0))
	if chest_id <= 0:
		chest_id = ORNATE_CHEST_IDS[0] if not ORNATE_CHEST_IDS.is_empty() else 249
	var chest_item: Item = ContentRegistryHub.load_by_id(&"items", chest_id) as Item
	if chest_item == null:
		return []
	return [{
		"id": chest_id,
		"amount": count,
		"name": str(chest_item.item_name),
	}]


## The live Player for a peer (null if they logged off / left), via its current
## instance — same lookup quest scoping uses.
static func _resolve_player(peer_id: int) -> Player:
	if WorldServer.curr == null:
		return null
	var inst: Node = WorldServer.curr.instance_manager.find_instance_for_peer(peer_id)
	if inst == null:
		return null
	return inst.get_player(peer_id) as Player


## The live Player for a persistent player_id (null if they logged off).
static func _resolve_player_by_id(player_id: int) -> Player:
	if player_id <= 0 or WorldServer.curr == null:
		return null
	for ires: InstanceResource in WorldServer.curr.instance_manager.instance_collection.values():
		for inst: Node in ires.charged_instances:
			if inst == null or not inst is ServerInstance:
				continue
			for peer_id: int in (inst as ServerInstance).players_by_peer_id:
				var player: Player = (inst as ServerInstance).players_by_peer_id[peer_id]
				if player != null and player.player_resource != null \
						and int(player.player_resource.player_id) == player_id:
					return player
	return null


## All of one participant's reward, and the combat.reward push to their client.
## [param reserved_peer] owns the ground piles for [constant LOOT_EXCLUSIVE_MS].
## [param bonus_loot] is extra personal loot (ranked ornate chests) merged in
## before the ground spawn — still reserved to this peer.
static func _reward(
	player: Player,
	npc: HostileNpc,
	reserved_peer: int = 0,
	bonus_loot: Array = []
) -> void:
	var resource: PlayerResource = player.player_resource
	if resource == null:
		return
	var peer_id: int = int(resource.current_peer_id)

	var level_before: int = resource.level
	# Character level rides the small 1–20 curve, so it keeps the authored xp_reward.
	resource.add_experience(npc.xp_reward)
	# Mastery and Slayer ride the SkillXp 1–99 curve (~980× bigger) and take the
	# stat-derived number instead — see EnemyTypeResource.combat_skill_xp_for.
	# The body answers, so a boss can author a flat value (combat_skill_xp_override)
	# while every ordinary mob keeps deriving it from its health. A reward-suppressed
	# body (dungeon trash / boss adds) reports 0, which zeroes mastery and drops Slayer
	# to its task's authored fallback rate — see HostileNpc.grants_skill_xp.
	var skill_xp: int = npc.combat_skill_xp() if npc.grants_skill_xp else 0
	var loot_gained: Array = _roll_loot(npc, player)
	_append_zone_kill_loot(player, loot_gained)
	for entry: Variant in bonus_loot:
		if entry is Dictionary:
			loot_gained.append(entry)
	# A dungeon run's own daily charge gates ALL loot from it, not just the
	# completion payout — otherwise a boss's untouched EnemyTypeResource table
	# (make_dungeon_mob only strips trash) keeps paying out after charges hit 0.
	# XP / mastery / Slayer / quest credit below are untouched — only the drop.
	var dungeon_instance: Node = WorldServer.curr.instance_manager.find_instance_for_peer(peer_id) if peer_id > 0 else null
	if dungeon_instance != null and DungeonService.is_dungeon_instance(dungeon_instance) \
			and DungeonService.charges_remaining(resource) <= 0:
		loot_gained.clear()
	# Ordinary drops land on the ground for click-pickup — not auto-bagged. Each
	# peer's piles are reserved to THEM (instanced loot — goblin chief / mecha golem).
	# A Boss Hunt boss banks straight into each participant's Hunt Chest instead:
	# a 30-minute farm would otherwise end under a carpet of piles, half of them
	# already expired, and collecting in the Guild Hall is the point of the mode.
	var hunt_kill: bool = npc.has_meta(BossHuntArena.HUNT_LOOT_META)
	if hunt_kill:
		_bank_hunt_loot(player, loot_gained)
	else:
		_spawn_ground_loot(player, npc, loot_gained, reserved_peer)

	# Weapon mastery: practicing a category = killing with it, on the 1–99 curve.
	var mastery: Dictionary = {}
	var weapon_item: WeaponItem = player.equipment_component.equipped_items.get(&"weapon", null) as WeaponItem
	if skill_xp > 0 and weapon_item != null and not weapon_item.category.is_empty():
		mastery = resource.add_mastery_xp(weapon_item.category, skill_xp)

	# Slayer rides the same 1–99 curve as mastery, at SLAYER_XP_RATIO of it — so it
	# takes the same stat-derived number, NOT the character-level xp_reward. A boss on
	# task pays SlayerTaskService.BOSS_XP_MULTIPLIER on top, hence the is_boss arg.
	# Resolved BEFORE the combat.reward push: Slayer can raise the derived character
	# level too, and that push reports the level, so it has to see the final value.
	var slayer_result: Dictionary = SlayerTaskService.on_kill(
		resource,
		npc.enemy_type,
		skill_xp,
		npc.enemy_data != null and bool(npc.enemy_data.is_boss)
	)

	# Only push when there is something to REPORT. A reward-suppressed body (dungeon
	# trash, boss adds) pays nothing, and the client cards every combat.reward that
	# names an enemy — so pushing here would spatter a "Defeated a Spore Swarm" toast
	# with no reward on it across every dungeon room. Progression below still runs;
	# quest and Slayer pushes carry their own feedback when they actually advance.
	if peer_id > 0 and (
		npc.xp_reward > 0 or not loot_gained.is_empty()
		or not mastery.is_empty() or not slayer_result.is_empty()
	):
		var bar_xp: int = int(resource.experience)
		var bar_next: int = resource.level_xp_to_next()
		var shown_xp: int = npc.xp_reward
		if not mastery.is_empty():
			bar_xp = int(mastery.get("xp", 0))
			bar_next = int(mastery.get("xp_to_next", 1))
			shown_xp = int(mastery.get("gained", skill_xp))
		elif not slayer_result.is_empty():
			bar_xp = int(slayer_result.get("xp", 0))
			bar_next = int(slayer_result.get("xp_to_next", 1))
			shown_xp = int(slayer_result.get("xp_gained", 0))
		WorldServer.curr.data_push.rpc_id(peer_id, &"combat.reward", {
			"enemy_type": npc.enemy_type,
			"xp": shown_xp,
			"skill_xp": skill_xp,
			"level": resource.level,
			"levels_gained": resource.level - level_before,
			"points_gained": PlayerResource.attribute_points_at_level(resource.level)
				- PlayerResource.attribute_points_at_level(level_before),
			"experience": bar_xp,
			"xp_to_next": bar_next,
			"loot": loot_gained,
			# Boss Hunt loot is banked, not scattered — the client's reward card
			# reads "sent to your Hunt Chest" instead of "on the ground".
			"ground": not hunt_kill,
			"hunt_chest": hunt_kill,
			"mastery": mastery,
			"slayer": slayer_result,
		})

	var quest_updates: Array = QuestService.on_kill(resource, npc.enemy_type, peer_id, dungeon_instance)
	if peer_id > 0 and not quest_updates.is_empty():
		WorldServer.curr.data_push.rpc_id(peer_id, &"quest.update", {"messages": quest_updates})

	# No daily hook here any more: the daily board is skilling-only (see
	# DailyQuestManager). Kills feed Slayer and the mainline quest tracker above.
	LeaderboardService.record_pve_kill(player)

	if peer_id > 0 and not slayer_result.is_empty():
		WorldServer.curr.data_push.rpc_id(peer_id, &"slayer.update", slayer_result)

	# Character level is derived now, so milestones key off the real level delta
	# rather than the (always-zero) levels_gained from add_experience.
	if resource.level > level_before:
		var inst: Node = WorldServer.curr.instance_manager.find_instance_for_peer(peer_id) if peer_id > 0 else null
		LevelMilestoneService.on_levels_gained(resource, level_before, resource.level, inst)



## Pays [param amount] weapon-mastery XP for a reward that ISN'T a kill — a quest
## turn-in or a daily claim. Quest/daily XP used to land only in
## PlayerResource.experience, a lifetime counter that stopped levelling anything
## when character level became mastery-derived; players quite reasonably asked what
## the "+90 XP" on a quest card was even for. Routing it here answers that: it goes
## to the same bar a kill fills.
##
## Destination is the weapon in HAND, so the reward trains what you are actually
## playing. With empty hands it falls back to the player's best-trained mastery
## rather than evaporating — a reward should never silently pay nothing.
##
## Returns the add_mastery_xp payload (empty when there was nothing to pay into),
## ready to ride a combat.reward push under "mastery" — which is what gives quest
## and daily XP the same bar, toast and level-up ceremony a kill already has.
## Takes the peer rather than the node so callers holding only a peer id (the quest
## turn-in path) don't have to resolve the Player themselves.
static func grant_mastery_reward(peer_id: int, amount: int) -> Dictionary:
	if peer_id <= 0 or amount <= 0:
		return {}
	var player: Player = _resolve_player(peer_id)
	if player == null or player.player_resource == null:
		return {}
	var resource: PlayerResource = player.player_resource
	var category: StringName = &""
	var weapon_item: WeaponItem = player.equipment_component.equipped_items.get(
		&"weapon", null
	) as WeaponItem
	if weapon_item != null and not weapon_item.category.is_empty():
		category = weapon_item.category
	else:
		category = _best_mastery_category(resource)
	if category.is_empty():
		return {}
	return resource.add_mastery_xp(category, amount)


## The player's highest-level trained weapon mastery, or &"" if they have never
## practiced one. Ties break on whichever the dictionary yields first — they are
## the same level, so there is no better answer to pick.
static func _best_mastery_category(resource: PlayerResource) -> StringName:
	var best: StringName = &""
	var best_level: int = 0
	for key: Variant in resource.masteries:
		var entry: Variant = resource.masteries[key]
		if entry is not Dictionary:
			continue
		var level: int = int((entry as Dictionary).get("level", 0))
		if level > best_level:
			best_level = level
			best = StringName(String(key))
	return best


## Rolls each loot entry; returns [{ "id", "amount", "name" }, ...].
##
## [param player] is the person being rewarded, needed because the Hunter's Charm
## nudges HIGH-TIER BOSS rolls for a blessed killer (see [HunterCharm]). The roll
## is taken ONCE and compared against both the base and the blessed chance, so
## the charm can only ever turn a miss into a hit — never re-roll a miss, and
## never lose a drop the base chance had already earned.
static func _roll_loot(npc: HostileNpc, player: Player) -> Array:
	var out: Array = []
	var resource: PlayerResource = player.player_resource if player != null else null
	var is_boss: bool = npc.enemy_data != null and npc.enemy_data.is_boss
	var blessed_hits: int = 0
	for drop: LootDrop in npc.loot:
		if drop == null or drop.item == null:
			continue
		var roll: float = randf()
		var chance: float = HunterCharm.adjusted_chance(resource, is_boss, drop.chance)
		if roll > chance:
			continue
		if HunterCharm.was_decisive(resource, is_boss, drop.chance, roll):
			blessed_hits += 1
		var amount: int = randi_range(drop.min_amount, drop.max_amount)
		if amount > 0:
			out.append({
				"id": int(drop.item.get_meta(&"id", 0)),
				"amount": amount,
				"name": str(drop.item.item_name),
			})
	if blessed_hits > 0:
		_toast_hunters_blessing(player)
	return out


## Float "Hunter's Blessing Triggered!" over the blessed killer. Fired only when
## the charm was what landed the drop, so the toast is a claim the player can
## trust rather than ambient noise on every rare.
static func _toast_hunters_blessing(player: Player) -> void:
	if player == null or player.player_resource == null or WorldServer.curr == null:
		return
	var peer_id: int = int(player.player_resource.current_peer_id)
	if peer_id <= 0:
		return
	WorldServer.curr.data_push.rpc_id(
		peer_id, &"peddler.toast", {"text": HunterCharm.TOAST_TEXT}
	)


## Zone-wide rares from [member InstanceResource.zone_kill_loot] — any hostile
## killed in that instance can drop them, including NPCs added later.
static func _append_zone_kill_loot(player: Player, out: Array) -> void:
	if player == null or player.player_resource == null or WorldServer.curr == null:
		return
	var peer_id: int = int(player.player_resource.current_peer_id)
	if peer_id <= 0:
		return
	var inst: Node = WorldServer.curr.instance_manager.find_instance_for_peer(peer_id)
	if inst == null or not inst is ServerInstance:
		return
	var ires: InstanceResource = (inst as ServerInstance).instance_resource
	if ires == null or ires.zone_kill_loot == null or ires.zone_kill_loot.is_empty():
		return
	for drop: LootDrop in ires.zone_kill_loot:
		if drop == null or drop.item == null:
			continue
		if randf() > drop.chance:
			continue
		var amount: int = randi_range(drop.min_amount, drop.max_amount)
		var item_id: int = int(drop.item.get_meta(&"id", 0))
		if amount <= 0 or item_id <= 0:
			continue
		out.append({
			"id": item_id,
			"amount": amount,
			"name": str(drop.item.item_name),
		})


## Bank a Boss Hunt roll into [param player]'s Hunt Chest. Currency skips the
## chest and goes straight to the pouch, matching how chest-opens already handle
## gold. A chest at its stack cap rejects NEW item ids — the drop is reported to
## the client as unbanked rather than silently vanishing, so the player knows to
## go empty it.
static func _bank_hunt_loot(player: Player, loot_gained: Array) -> void:
	var resource: PlayerResource = player.player_resource
	if resource == null or loot_gained.is_empty():
		return
	for entry: Dictionary in loot_gained:
		var item_id: int = int(entry.get("id", 0))
		var amount: int = int(entry.get("amount", 0))
		if item_id <= 0 or amount <= 0:
			continue
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
		if item != null and item.is_currency:
			Inventory.add_item(
				resource.inventory, item_id, amount, false,
				resource.active_inventory_bag, resource.inventory_bags
			)
			entry["banked"] = true
			continue
		entry["banked"] = HuntChest.deposit(resource, item_id, amount) > 0


## Scatter rolled loot as clickable GroundItems around the corpse. Piles are
## reserved to [param reserved_peer] (that participant) for 60s, then free-for-all.
## Always spawned on the NPC's map so a recall / instance switch cannot dump
## the roll in town while the corpse is still in the woodland.
static func _spawn_ground_loot(
	player: Player,
	npc: HostileNpc,
	loot_gained: Array,
	reserved_peer: int = 0
) -> void:
	if loot_gained.is_empty():
		return
	var peer_id: int = int(player.player_resource.current_peer_id) if player.player_resource != null else 0
	var map: Map = _map_of_npc(npc)
	if map == null or map.replicated_props_container == null:
		return
	var container: ReplicatedPropsContainer = map.replicated_props_container
	var origin: Vector2 = npc.global_position
	var owner_peer: int = reserved_peer if reserved_peer > 0 else peer_id
	var exclusive_until: int = Time.get_ticks_msec() + LOOT_EXCLUSIVE_MS
	var i: int = 0
	for entry: Dictionary in loot_gained:
		var item_id: int = int(entry.get("id", 0))
		var amount: int = int(entry.get("amount", 0))
		if item_id <= 0 or amount <= 0:
			continue
		var angle: float = TAU * float(i) / float(maxi(1, loot_gained.size()))
		var offset := Vector2(cos(angle), sin(angle)) * randf_range(12.0, 22.0)
		offset += Vector2(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0))
		var drop_global: Vector2 = origin + offset
		var drop_local: Vector2 = container.to_local(drop_global)
		container.spawn_dynamic(
			ReplicatedPropsContainer.SCENE_GROUND_ITEM,
			drop_local,
			{
				"item_id": item_id,
				"amount": amount,
				"position": drop_local,
				"owner_peer_id": owner_peer,
				"exclusive_until_ms": exclusive_until,
			}
		)
		i += 1


static func _map_of_npc(npc: HostileNpc) -> Map:
	var n: Node = npc
	while n != null:
		if n is Map:
			return n as Map
		n = n.get_parent()
	return null
