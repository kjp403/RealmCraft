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
## Ornate bag-chest item IDs (blue / red / pink). Ranked boss grants pick one
## at random per chest so each earner gets their own mix.
const ORNATE_CHEST_IDS: Array[int] = [247, 248, 249]


## [param contributors] = peer_id -> total damage dealt this life (HostileNpc
## tracks it). Server-only.
static func distribute(npc: HostileNpc, contributors: Dictionary, killer: Character) -> void:
	if not GameMode.is_world_server():
		return
	if npc.xp_reward <= 0 and (npc.loot == null or npc.loot.is_empty()) \
			and not _has_ranked_ornate_chests(npc):
		return # nothing to give (a shadow mob) — don't even resolve players
	# is_boss lives on EnemyTypeResource — HostileNPC never copied it, so bare
	# npc.is_boss crashed distribute() and wiped XP/loot for every kill.
	var is_boss: bool = (
		npc.enemy_data != null and bool(npc.enemy_data.is_boss)
	)
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


## Rank 0 = top DPS, 1 = second, else consolation roll. Returns loot entries
## ready to merge into the participant's personal pile.
static func _roll_ranked_ornate_chests(rank: int, npc: HostileNpc) -> Array:
	var d: EnemyTypeResource = npc.enemy_data
	if d == null or d.ornate_chest_top_max <= 0:
		return []
	var count: int = 0
	match rank:
		0:
			count = randi_range(
				maxi(0, d.ornate_chest_top_min),
				maxi(0, d.ornate_chest_top_max)
			)
		1:
			count = randi_range(
				maxi(0, d.ornate_chest_second_min),
				maxi(0, d.ornate_chest_second_max)
			)
		_:
			if d.ornate_chest_consolation_chance > 0.0 \
					and randf() <= d.ornate_chest_consolation_chance:
				count = 1
	if count <= 0:
		return []
	var out: Array = []
	for _i: int in count:
		var chest_id: int = ORNATE_CHEST_IDS[randi() % ORNATE_CHEST_IDS.size()]
		var chest_item: Item = ContentRegistryHub.load_by_id(&"items", chest_id) as Item
		if chest_item == null:
			continue
		out.append({
			"id": chest_id,
			"amount": 1,
			"name": str(chest_item.item_name),
		})
	return out


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
	var progress: Dictionary = resource.add_experience(npc.xp_reward)
	var loot_gained: Array = _roll_loot(npc)
	for entry: Variant in bonus_loot:
		if entry is Dictionary:
			loot_gained.append(entry)
	# Drops land on the ground for click-pickup — not auto-bagged. Each peer's
	# piles are reserved to THEM (instanced loot — goblin chief / mecha golem).
	_spawn_ground_loot(player, npc, loot_gained, reserved_peer)

	# Weapon mastery: practicing a category = killing with it. Same xp number.
	var mastery: Dictionary = {}
	var weapon_item: WeaponItem = player.equipment_component.equipped_items.get(&"weapon", null) as WeaponItem
	if weapon_item != null and not weapon_item.category.is_empty():
		mastery = resource.add_mastery_xp(weapon_item.category, npc.xp_reward)

	var peer_id: int = int(resource.current_peer_id)
	if peer_id > 0:
		WorldServer.curr.data_push.rpc_id(peer_id, &"combat.reward", {
			"enemy_type": npc.enemy_type,
			"xp": npc.xp_reward,
			"level": int(progress.get("level", 1)),
			"levels_gained": int(progress.get("levels_gained", 0)),
			"points_gained": int(progress.get("points_gained", 0)),
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

	if int(progress.get("levels_gained", 0)) > 0:
		var inst: Node = WorldServer.curr.instance_manager.find_instance_for_peer(peer_id) if peer_id > 0 else null
		LevelMilestoneService.on_levels_gained(resource, level_before, int(progress.get("level", 1)), inst)


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
