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
## lower bar so anyone who meaningfully poked them still gets a roll.
const MIN_DAMAGE_FRACTION: float = 0.1
const BOSS_MIN_DAMAGE_FRACTION: float = 0.01
## Ground piles stay reserved to their earner for this long (anti-ninja).
const LOOT_EXCLUSIVE_MS: int = 60_000
## Fallback ornate chest id (pink / 249) when a boss leaves ornate_chest_item empty.
## Ranked grants use the boss's authored color item when set.
const ORNATE_CHEST_IDS: Array[int] = [249]


## [param contributors] = peer_id -> total damage dealt this life (HostileNpc
## tracks it). Server-only.
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
	var killer_peer: int = -1
	if killer is Player and (killer as Player).player_resource != null:
		killer_peer = int((killer as Player).player_resource.current_peer_id)

	# Build the eligible set, then sort by damage so DPS-ranked chest grants
	# (Mecha Golem ornate chests) know #1 / #2 / everyone else.
	var ranked: Array[Dictionary] = []
	var seen: Dictionary[int, bool] = {}
	for peer_id: int in contributors:
		if peer_id != killer_peer and float(contributors[peer_id]) < threshold:
			continue
		ranked.append({
			"peer": peer_id,
			"dmg": float(contributors[peer_id]),
		})
		seen[peer_id] = true
	if killer_peer > 0 and not seen.has(killer_peer):
		ranked.append({
			"peer": killer_peer,
			"dmg": float(contributors.get(killer_peer, 0.0)),
		})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["dmg"]) > float(b["dmg"])
	)

	for rank: int in ranked.size():
		var peer_id: int = int(ranked[rank]["peer"])
		var player: Player = _resolve_player(peer_id)
		if player != null:
			# Each contributor gets their own loot roll, reserved to THEM for 60s
			# so nearby players can't ninja-loot (top damager included). Ranked
			# ornate chests (if authored) append on top of the table roll.
			_reward(player, npc, peer_id, _roll_ranked_ornate_chests(rank, npc))


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
	var loot_gained: Array = _roll_loot(npc)
	_append_zone_kill_loot(player, loot_gained)
	for entry: Variant in bonus_loot:
		if entry is Dictionary:
			loot_gained.append(entry)
	# Drops land on the ground for click-pickup — not auto-bagged. Each peer's
	# piles are reserved to THEM (instanced loot — goblin chief / mecha golem).
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

	var peer_id: int = int(resource.current_peer_id)
	# Only push when there is something to REPORT. A reward-suppressed body (dungeon
	# trash, boss adds) pays nothing, and the client cards every combat.reward that
	# names an enemy — so pushing here would spatter a "Defeated a Spore Swarm" toast
	# with no reward on it across every dungeon room. Progression below still runs;
	# quest and Slayer pushes carry their own feedback when they actually advance.
	if peer_id > 0 and (npc.xp_reward > 0 or not loot_gained.is_empty() or not mastery.is_empty()):
		WorldServer.curr.data_push.rpc_id(peer_id, &"combat.reward", {
			"enemy_type": npc.enemy_type,
			"xp": npc.xp_reward,
			"level": resource.level,
			"levels_gained": resource.level - level_before,
			"points_gained": PlayerResource.attribute_points_at_level(resource.level)
				- PlayerResource.attribute_points_at_level(level_before),
			"experience": resource.experience,
			"xp_to_next": resource.level_xp_to_next(),
			"loot": loot_gained,
			"ground": true,
			"mastery": mastery,
		})

	var instance: Node = WorldServer.curr.instance_manager.find_instance_for_peer(peer_id) if peer_id > 0 else null
	var quest_updates: Array = QuestService.on_kill(resource, npc.enemy_type, peer_id, instance)
	if peer_id > 0 and not quest_updates.is_empty():
		WorldServer.curr.data_push.rpc_id(peer_id, &"quest.update", {"messages": quest_updates})

	DailyQuestService.on_kill(resource, npc.enemy_type)
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
static func _roll_loot(npc: HostileNpc) -> Array:
	var out: Array = []
	for drop: LootDrop in npc.loot:
		if drop == null or drop.item == null:
			continue
		if randf() <= drop.chance:
			var amount: int = randi_range(drop.min_amount, drop.max_amount)
			if amount > 0:
				out.append({
					"id": int(drop.item.get_meta(&"id", 0)),
					"amount": amount,
					"name": str(drop.item.item_name),
				})
	return out


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


## Scatter rolled loot as clickable GroundItems around the corpse. Piles are
## reserved to [param reserved_peer] (that participant) for 60s, then free-for-all.
static func _spawn_ground_loot(
	player: Player,
	npc: HostileNpc,
	loot_gained: Array,
	reserved_peer: int = 0
) -> void:
	if loot_gained.is_empty():
		return
	var peer_id: int = int(player.player_resource.current_peer_id) if player.player_resource != null else 0
	var inst: Node = WorldServer.curr.instance_manager.find_instance_for_peer(peer_id) if peer_id > 0 else null
	if inst == null or not inst is ServerInstance:
		return
	var map: Map = (inst as ServerInstance).instance_map
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
