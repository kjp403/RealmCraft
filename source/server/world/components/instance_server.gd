class_name ServerInstance
extends SubViewport


signal player_entered_warper(player: Player, current_instance: ServerInstance, warper: Warper)

const PLAYER: PackedScene = preload("res://source/common/gameplay/characters/player/player.tscn")

static var world_server: WorldServer

static var global_chat_commands: Dictionary[String, ChatCommand]
static var global_role_definitions: Dictionary[String, Dictionary] = preload("res://source/server/world/data/server_roles.tres").get_roles()

var local_chat_commands: Dictionary[String, ChatCommand]
var local_role_definitions: Dictionary[String, Dictionary]
var local_role_assignments: Dictionary[int, PackedStringArray]

var players_by_peer_id: Dictionary[int, Player]
## Current connected peers to the instance.
var connected_peers: PackedInt64Array = PackedInt64Array()
## Peers coming from another instance.
var awaiting_peers: Dictionary[int, Dictionary] = {}#[int, Player]

var last_accessed_time: float

var instance_map: Map
var instance_resource: InstanceResource

var synchronizer_manager: StateSynchronizerManagerServer


## True when this equipment slot holds its item BY REFERENCE — the id is in
## `equipment` while the stack itself stays a normal bag stack. Ammo is the only
## one today (see AmmoItem: `equipment` is slot -> id with nowhere to put a
## quantity), and `item.unequip.gd` makes the same carve-out.
##
## It matters wherever code "returns" a failed / removed equip to the bag: that
## is right for a helmet, which physically left, and wrong here — it hands the
## player a free arrow every time.
##
## Checked by SLOT as well as by type because the usual reason a re-equip fails
## is an id that no longer resolves, and then there is no type left to test.
static func is_reference_slotted(slot_key: StringName, item: Item) -> bool:
	return slot_key == &"ammo" or item is AmmoItem


func _ready() -> void:
	world_server.multiplayer_api.peer_disconnected.connect(
		func(peer_id: int):
			if connected_peers.has(peer_id):
				var player: Player = get_player(peer_id)
				if player and player.global_position.is_finite():
					player.player_resource.last_position = player.global_position
				despawn_player(peer_id)
	)

	synchronizer_manager = StateSynchronizerManagerServer.new()
	synchronizer_manager.name = "StateSynchronizerManager"
	synchronizer_manager.init_zones_from_map(instance_map)

	add_child(synchronizer_manager, true)

	# Status tick: ONE 1 Hz timer per instance for everything that regenerates
	# periodically (mana today; HP regen / poison / buffs slot in here later).
	# Deliberately not a per-frame poll on every Player node — N updates per
	# SECOND instead of 60×N, and clients run nothing at all.
	var status_tick: Timer = Timer.new()
	status_tick.name = "StatusTick"
	status_tick.wait_time = 1.0
	status_tick.timeout.connect(_on_status_tick)
	add_child(status_tick)
	status_tick.start()


## peer_id → odd/even toggle so out-of-combat HP heals 1 every 2 seconds on the
## 1 Hz status tick (see [method _on_status_tick]).
var _hp_regen_tick: Dictionary = {}


## 1 Hz upkeep for every player in this instance. Mana regen reads the
## MANA_REGEN stat (base + Spirit + future gear/food), so "regens faster" is
## an itemizable property, not a constant. Out-of-combat HP regenerates
## +1 every 2 seconds.
func _on_status_tick() -> void:
	for peer_id: int in players_by_peer_id:
		var player: Player = players_by_peer_id[peer_id]
		if player == null:
			continue
		if player.is_dead:
			player.maybe_unstick_death()
			continue
		# Expire finished buffs FIRST so this tick's regen uses the post-buff rate.
		BuffService.tick(player)
		# Drop a weapon coating the moment it runs out, so the strip and the
		# stored field agree, and the next vial is drinkable the second the icon
		# clears rather than on the next swing.
		CoatingService.tick(player)
		# Burn a second of prayer drain. Switches everything off at zero, so a
		# player who runs dry loses the bonuses the same tick the orb empties.
		PrayerService.tick(player)
		# Status HUD snapshot (buffs / DoTs / in-combat) — after the expiry pass
		# so dropped buffs vanish from the strip the same second they end.
		StatusService.sync(player)
		_tick_player_hp_regen(peer_id, player)
		var mana_max: float = player.stats_component.get_stat(Stat.MANA_MAX)
		if mana_max <= 0.0:
			continue
		var mana: float = player.stats_component.get_stat(Stat.MANA)
		if mana >= mana_max:
			continue
		var regen: float = player.stats_component.get_stat(Stat.MANA_REGEN)
		if regen <= 0.0:
			continue
		player.stats_component.set_stat(Stat.MANA, minf(mana_max, mana + regen))


func _tick_player_hp_regen(peer_id: int, player: Player) -> void:
	if player.is_in_combat():
		_hp_regen_tick.erase(peer_id)
		return
	var health_max: float = player.stats_component.get_stat(Stat.HEALTH_MAX)
	if health_max <= 0.0:
		return
	var health: float = player.stats_component.get_stat(Stat.HEALTH)
	if health >= health_max:
		_hp_regen_tick.erase(peer_id)
		return
	var phase: int = int(_hp_regen_tick.get(peer_id, 0)) + 1
	_hp_regen_tick[peer_id] = phase
	# Heal on every 2nd out-of-combat tick → 1 HP / 2 seconds.
	if phase % 2 != 0:
		return
	player.stats_component.set_stat(Stat.HEALTH, minf(health_max, health + 1.0))


func load_map(map_path: String) -> void:
	if instance_map:
		instance_map.queue_free()
	if not ResourceLoader.exists(map_path):
		push_error("ServerInstance.load_map: map path does not exist: %s" % map_path)
		return
	# Two-step load + instantiate so a busted dependency (e.g. a referenced
	# resource that fails to parse) surfaces as a clean push_error here
	# rather than a NPE on the next line. Matches the "sometimes crashes
	# on world spin-up" repro pattern from the dashboard.
	var map_scene: PackedScene = load(map_path)
	if map_scene == null:
		push_error("ServerInstance.load_map: load() returned null for %s" % map_path)
		return
	instance_map = map_scene.instantiate()
	if instance_map == null:
		push_error("ServerInstance.load_map: instantiate() returned null for %s" % map_path)
		return
	add_child.call_deferred(instance_map)

	ready.connect(func():
		if instance_map.replicated_props_container:
			synchronizer_manager.add_container(1_000_000, instance_map.replicated_props_container)
		# Recursive: an InteractionArea (warper/teleporter/...) may be grouped under an
		# organizational node ("Warpers/") — a direct-children scan silently skipped it,
		# leaving the area registered but its enter-signal never wired (dead portal).
		for area: Node in instance_map.find_children("*", "InteractionArea", true, false):
			(area as InteractionArea).player_entered_interaction_area.connect(self._on_player_entered_interaction_area)
		)


func _on_player_entered_interaction_area(player: Player, interaction_area: InteractionArea) -> void:
	if player.has_recently_teleported():
		return
	if interaction_area is Warper and interaction_area.target_instance:
		var warper: Warper = interaction_area
		# Wardstone gate (docs/wardstones.md): the ONE hard access rule — no level
		# or party bypass. Levels stay advisory (client-side warn + hesitation
		# window only). SILENT refusal: the client renders the sealed state + its
		# own banner (other portal outcomes never touch chat — consistency); this
		# is purely the authoritative backstop against modified clients.
		if not warper.target_instance.can_join_instance(player):
			return
		if warper.warp_delay_s > 0.0:
			_warp_after_dwell(player, warper)
		else:
			player_entered_warper.emit.call_deferred(player, self, warper)
	if interaction_area is Teleporter:
		var teleporter: Teleporter = interaction_area
		# No target = an unconfigured teleporter, or the landing end of a ONE-WAY pair (leave the
		# destination teleporter's target empty to make it a plain arrival spot). No-op instead of
		# crashing on a null deref.
		if teleporter.target == null:
			return
		player.mark_just_teleported()
		var dest: Vector2 = teleporter.target.global_position
		player.state_synchronizer.set_by_path(^":position", dest)
		# The teleported client OWNS its LocalPlayer position, so a state delta alone won't move it
		# (it overwrites with its own input next frame). Push the explicit player.teleport that
		# teleport_peer_to / recall use so the client actually snaps to the destination.
		WorldServer.curr.data_push.rpc_id(player.name.to_int(), &"player.teleport", {"position": dest})


## Portal-style delayed warp: fire only if the player is still inside the warper once
## its dwell elapses — stepping out cancels, mirroring the client-side fade cancel.
## An under-leveled player gets the hesitation window on top (the client holds its
## fade for the same span, so both ends stay in sync — see Warper.GATE_WARN_EXTRA_S).
## Runs outside the physics callback (post-await), so the emit needs no defer.
func _warp_after_dwell(player: Player, warper: Warper) -> void:
	# Mirror the client's phases exactly: [hesitation if warned] + spin-up + fade.
	var total_s: float = Warper.SPIN_UP_S + warper.warp_delay_s \
		+ warper.warn_extra_for(player.player_resource.level)
	await get_tree().create_timer(total_s).timeout
	if not is_instance_valid(self) or not is_instance_valid(player) or not is_instance_valid(warper):
		return
	if not warper.overlaps_body(player) or player.has_recently_teleported():
		return
	player_entered_warper.emit(player, self, warper)


@rpc("any_peer", "call_remote", "reliable", 0)
func ready_to_enter_instance() -> void:
	var peer_id: int = multiplayer.get_remote_sender_id()
	# Ignore duplicate/spam requests so a client can't spawn ghost copies of itself.
	if players_by_peer_id.has(peer_id):
		return
	spawn_player(peer_id)


#region spawn/despawn
@rpc("authority", "call_remote", "reliable", 0)
func spawn_player(peer_id: int) -> void:
	var player: Player
	var spawn_index: int = 0
	var spawn_position: Vector2

	# Warpers self-register from their OWN _ready, so on a big tiled map (the
	# woodland) a join that lands in the same frame as the map load finds
	# Map.warpers empty. get_spawn_position then falls through to the map's
	# global_position — (0, 0), the top-left border wall — and the player spawns
	# wedged in it: no movement, camera parked on whatever sits up there (the
	# goblin chief). Waiting for the map settles it before anything reads spawns.
	if not instance_map.is_node_ready():
		await instance_map.ready
	if instance_map.warpers.is_empty():
		await get_tree().process_frame
	if instance_map.warpers.is_empty():
		ServerLog.warn(
			"Instance '%s': no warpers registered at spawn — falling back to map origin."
			% instance_resource.instance_name
		)

	if awaiting_peers.has(peer_id):
		var player_info: Dictionary = awaiting_peers[peer_id]
		player = player_info["player"] if "player" in player_info else instantiate_player(peer_id)
		spawn_index = player_info.get("target_id", 0)
		spawn_position = player_info["target_position"] if "target_position" in player_info else instance_map.get_spawn_position(spawn_index)
		awaiting_peers.erase(peer_id)
	else:
		player = instantiate_player(peer_id)
		spawn_position = instance_map.get_spawn_position(spawn_index)
		WorldServer.curr.chat_service.push_system_to_player(self, player.player_resource.player_id, get_motd())
		#WorldServer.curr.data_push.rpc_id(peer_id, &"chat.message", {"text": get_motd(), "id": 1, "name": "Server"})

	player.player_resource.current_instance = instance_resource.instance_name
	player.mark_just_teleported()
	
	instance_map.add_child(player, true)
	
	players_by_peer_id[peer_id] = player
	
	if spawn_position == Vector2.ZERO or not spawn_position.is_finite():
		spawn_position = instance_map.get_spawn_position(0)

	var syn: StateSynchronizer = player.state_synchronizer
	syn.set_by_path(^":position", spawn_position)

	print_debug("baseline server pairs:", syn.capture_baseline())
	
	# Register in sync manager AFTER we seeded states.
	synchronizer_manager.add_entity(peer_id, syn)
	synchronizer_manager.register_peer(peer_id)

	connected_peers.append(peer_id)
	_propagate_spawn(peer_id)

	# A cross-map arrival REUSES the client's LocalPlayer node (InstanceClient
	# keeps it across instance changes), so it walks into the new map still
	# holding the coordinates it had in the old one — and re-asserts them at
	# 20 Hz, because movement is client-authoritative. The spawn state above
	# therefore races the client's own echo and loses, stranding the player
	# wherever the previous map put them (the Smith House "spawn into null").
	# Push the same explicit teleport every same-instance move already uses; it
	# also freezes input for 500 ms so the arrival can't be run off instantly.
	WorldServer.curr.data_push.rpc_id(peer_id, &"player.teleport", {"position": spawn_position})
	PartyService.on_spawn(peer_id)


func instantiate_player(peer_id: int) -> Player:
	var player_resource: PlayerResource = world_server.connected_players[peer_id]

	var new_player: Player = PLAYER.instantiate() as Player
	new_player.name = str(peer_id)
	new_player.player_resource = player_resource
	
	var setup_new_player: Callable = func():
		var syn: StateSynchronizer = new_player.state_synchronizer
		if CommandPermissions.strip_unreleased_vfx(player_resource, self):
			world_server.database.save_player(player_resource)
		syn.set_by_path(^":skin_id", new_player.player_resource.skin_id)
		syn.set_by_path(^":cosmetic_id", new_player.player_resource.cosmetic_id)
		syn.set_by_path(^":weapon_cosmetic_id", new_player.player_resource.weapon_cosmetic_id)
		syn.set_by_path(^":vault_skin_id", new_player.player_resource.vault_skin_id)
		syn.set_by_path(^":display_name", new_player.player_resource.display_name)
		syn.set_by_path(^":display_title", new_player.player_resource.display_title)
		syn.set_by_path(^":active_guild_id", new_player.player_resource.active_guild_id)
		syn.set_by_path(^":player_id", int(new_player.player_resource.player_id))
		syn.set_by_path(
			^":staff_role",
			CommandPermissions.effective_role_slug(new_player.player_resource, self)
		)

		# BASE_STATS is a const (read-only); copy it into a fresh dict before mutating.
		var player_stats: Dictionary[StringName, float]
		player_stats.assign(player_resource.BASE_STATS)

		# Levels grant baseline max HP on top of BASE_STATS — the durability floor
		# (docs/pvp_balance.md). Retroactive by construction: stats are rebuilt
		# from scratch here on every spawn, so existing characters get it on login.
		player_stats[Stat.HEALTH_MAX] += PlayerResource.HEALTH_PER_LEVEL * (player_resource.level - 1)

		var stats_from_attributes: Dictionary[StringName, float]
		stats_from_attributes.assign(AttributeMap.attr_to_stats(player_resource.attributes))
		
		# Add base player attributes to general base stats.
		for stat_name: StringName in stats_from_attributes:
			if player_stats.has(stat_name):
				player_stats[stat_name] += stats_from_attributes[stat_name]
			else:
				player_stats[stat_name] = stats_from_attributes[stat_name]
		
		player_resource.stats = player_stats

		for stat_name: StringName in player_stats:
			var value: float = player_stats[stat_name]
			new_player.stats_component.set_stat(stat_name, value)

		# Re-equip persisted gear (adds its stat modifiers on top of base + attributes).
		var saved_equipment: Dictionary = player_resource.equipment.duplicate()
		# Neckwear used to live in "relic"; move amulet-slot items into "amulet".
		if saved_equipment.has(&"relic"):
			var relic_id: int = int(saved_equipment[&"relic"])
			var relic_gear: GearItem = (
				ContentRegistryHub.load_by_id(&"items", relic_id) as GearItem
			)
			if (
				relic_gear
				and relic_gear.slot
				and relic_gear.slot.key == &"amulet"
			):
				var occupied: int = int(saved_equipment.get(&"amulet", 0))
				if occupied <= 0:
					saved_equipment[&"amulet"] = relic_id
					saved_equipment.erase(&"relic")
				else:
					# Amulet already filled — return the old relic-slot necklace.
					saved_equipment.erase(&"relic")
					Inventory.add_item(
						player_resource.inventory, relic_id, 1, false,
						player_resource.active_inventory_bag, player_resource.inventory_bags
					)
		player_resource.equipment.clear()
		for slot_key: StringName in saved_equipment:
			var equip_id: int = int(saved_equipment[slot_key])
			if new_player.equipment_component.equip_item(equip_id):
				var equipped: GearItem = (
					ContentRegistryHub.load_by_id(&"items", equip_id) as GearItem
				)
				var actual_slot: StringName = slot_key
				if equipped and equipped.slot:
					actual_slot = equipped.slot.key
				player_resource.equipment[actual_slot] = equip_id
			elif not is_reference_slotted(slot_key, ContentRegistryHub.load_by_id(&"items", equip_id)):
				# Rule changed (level/slot) -> return it to inventory rather than lose it.
				# Reference-slotted gear is excluded: it never left the bag, so
				# "returning" it mints a free one (see is_reference_slotted).
				Inventory.add_item(
					player_resource.inventory, equip_id, 1, false,
					player_resource.active_inventory_bag, player_resource.inventory_bags
				)

		# Stats were rebuilt from base + attributes + gear above — put any live
		# timed buffs (potions) back on top so an instance change doesn't strip them.
		BuffService.reapply(new_player)
		# Same for prayer: seat the pool (size comes from the Prayer level, the
		# CURRENT value carries across the instance change) and re-apply whatever
		# prayers were switched on. Must run AFTER the rebuild for the same
		# reason BuffService.reapply does.
		PrayerService.reapply(new_player)

		# Live level-ups raise the HP floor immediately (a method target, not a
		# lambda, so the connection auto-cleans when this node frees on instance
		# change — the resource outlives the per-instance Player node).
		player_resource.level_gained.connect(new_player._on_level_gained)

		# Mastery: mount the chosen special + the wielded category's passive
		# nodes, and keep both in sync with later weapon swaps.
		MasteryService.refresh(new_player)
		new_player.equipment_component.equipment_changed.connect(
			func(slot: StringName, _item_id: int) -> void:
				if slot == &"weapon":
					MasteryService.refresh(new_player)
		)

		# Set health to max health (heal player to full HP)
		new_player.stats_component.set_stat(
			Stat.HEALTH,
			new_player.stats_component.get_stat(Stat.HEALTH_MAX)
		)
		# Same for mana — spawn with a full pool.
		new_player.stats_component.set_stat(
			Stat.MANA,
			new_player.stats_component.get_stat(Stat.MANA_MAX)
		)
		WorldServer.curr.data_push.rpc_id(peer_id, &"stats.get", new_player.stats_component.stats.values)
		# Wardstone mirror, re-pushed per instance join. Sealed portals are drawn
		# from ClientState.wardstones, which is only filled by the login push and
		# by a live grant — a client that earns a stone and then changes instance
		# (or whose login push raced the map load) renders open portals as sealed
		# until relog. Idempotent and tiny; the client just re-emits.
		if new_player.player_resource != null:
			WorldServer.curr.data_push.rpc_id(
				peer_id, &"wardstones.set", {"wardstones": new_player.player_resource.wardstones}
			)
	new_player.ready.connect(setup_new_player,CONNECT_ONE_SHOT)
	return new_player


func get_motd() -> String:
	return world_server.world_manager.world_info.get("motd", "Default Welcome")


## Spawn the new player on all other client in the current instance
## and spawn all other players on the new client.
func _propagate_spawn(new_player_id: int) -> void:
	for peer_id: int in connected_peers:
		spawn_player.rpc_id(peer_id, new_player_id)
		if new_player_id != peer_id:
			spawn_player.rpc_id(new_player_id, peer_id)


@rpc("authority", "call_remote", "reliable", 0)
func despawn_player(peer_id: int, delete: bool = false) -> void:
	TradeService.on_peer_left(self, peer_id)
	connected_peers.remove_at(connected_peers.find(peer_id))
	
	synchronizer_manager.remove_entity(peer_id)
	synchronizer_manager.unregister_peer(peer_id)
	
	var player: Player = players_by_peer_id[peer_id]
	if player:
		if delete:
			player.queue_free()
		else:
			instance_map.remove_child(player)
		players_by_peer_id.erase(peer_id)
	
	for id: int in connected_peers:
		despawn_player.rpc_id(id, peer_id)
#endregion


func get_player(peer_id: int) -> Player:
	var p: Player = players_by_peer_id.get(peer_id, null)
	return p


func get_player_syn(peer_id: int) -> StateSynchronizer:
	var p: Player = get_player(peer_id)
	return null if p == null else p.get_node_or_null(^"StateSynchronizer")
