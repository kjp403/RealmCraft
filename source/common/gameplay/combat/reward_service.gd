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


## [param contributors] = peer_id -> total damage dealt this life (HostileNpc
## tracks it). Server-only.
static func distribute(npc: HostileNpc, contributors: Dictionary, killer: Character) -> void:
	if not GameMode.is_world_server():
		return
	if npc.xp_reward <= 0 and (npc.loot == null or npc.loot.is_empty()):
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
	var rewarded: Dictionary[int, bool] = {}
	for peer_id: int in contributors:
		if peer_id != killer_peer and float(contributors[peer_id]) < threshold:
			continue
		var player: Player = _resolve_player(peer_id)
		if player != null:
			# Each contributor gets their own loot roll, reserved to THEM for 60s
			# so nearby players can't ninja-loot (top damager included).
			_reward(player, npc, peer_id)
		rewarded[peer_id] = true
	if killer_peer > 0 and not rewarded.has(killer_peer):
		var kp: Player = _resolve_player(killer_peer)
		if kp != null:
			_reward(kp, npc, killer_peer)


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
static func _reward(player: Player, npc: HostileNpc, reserved_peer: int = 0) -> void:
	var resource: PlayerResource = player.player_resource
	if resource == null:
		return

	var level_before: int = resource.level
	var progress: Dictionary = resource.add_experience(npc.xp_reward)
	var loot_gained: Array = _roll_loot(npc)
	# Drops land on the ground for click-pickup — not auto-bagged.
	_spawn_ground_loot(player, npc, loot_gained, reserved_peer)

	# Weapon mastery: practicing a category = killing with it. Same xp number.
	var mastery: Dictionary = {}
	var weapon_item: WeaponItem = player.equipment_component.equipped_items.get(&"weapon", null) as WeaponItem
	if weapon_item != null and not weapon_item.category.is_empty():
		mastery = resource.add_mastery_xp(weapon_item.category, npc.xp_reward)
		# Level-up intrinsic bonuses (AD/AP/armor/…) need a refresh to apply.
		if bool(mastery.get("leveled_up", false)) or bool(mastery.get("started", false)):
			MasteryService.refresh(player)

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
## reserved to [param reserved_peer] (top damage) for 60s, then free-for-all.
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
