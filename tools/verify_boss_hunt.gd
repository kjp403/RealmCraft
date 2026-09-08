@tool
extends Node
## Headless gate for the Boss Hunt feature. Run with:
##   godot --headless --path . tools/verify_boss_hunt.tscn
##
## SCENE mode, not `-s`: the catalog scan loads enemy types, which pull in the
## weapon scripts, which reference the Client / ClientState autoloads. A `-s`
## script runs with no autoloads registered, so the whole scan dies on
## "Identifier not found: Client" before a single check reports.
## Prints VERIFY_PASS only when every piece loads and agrees:
##   - the contract catalog scans, every target resolves an enemy type,
##   - the arena scene instantiates with a Map root, a ReplicatedPropsContainer,
##     a BossHuntArena with its boss_spawn wired, and a warper 0 to spawn on,
##   - the arena InstanceResource points at that scene under the name the
##     service looks up,
##   - the Hunt Broker NPC actually offers both interactions,
##   - the Guild Hall places the broker,
##   - the Hunt Chest round-trips a deposit,
##   - every contract fights the SAME EnemyTypeResource the open world places,
##   - and the tuning rules hold: XP under the open world, no solo discount,
##     health scaling UP with party size.

const ARENA_SCENE: String = "res://source/common/gameplay/maps/maps/boss_hunt/boss_hunt_arena.tscn"
const ARENA_RES: String = "res://source/common/gameplay/maps/instance/instance_collection/boss_hunt_arena.tres"
const BROKER_RES: String = "res://source/common/gameplay/characters/npc/npcs/hunt_broker.tres"
const GUILD_HALL: String = "res://source/common/gameplay/maps/maps/guild_house/inside_map.tscn"
const MAPS_PATH: String = "res://source/common/gameplay/maps/"
const TYPES_PATH: String = "res://source/common/gameplay/characters/npc/types/"

var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_check_catalog()
	_check_same_boss_as_the_world()
	_check_arena_scene()
	_check_arena_resource()
	_check_broker()
	_check_guild_hall()
	_check_chest()

	if _failures.is_empty():
		print("VERIFY_PASS")
	else:
		for line: String in _failures:
			printerr("FAIL: %s" % line)
		printerr("VERIFY_FAIL (%d)" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


func _fail(message: String) -> void:
	_failures.append(message)


func _check_catalog() -> void:
	var targets: Array[BossHuntTarget] = BossHuntCatalog.all()
	if targets.is_empty():
		_fail("BossHuntCatalog scanned zero targets.")
		return
	print("contracts: %d" % targets.size())
	var last_cost: int = -1
	for target: BossHuntTarget in targets:
		var id: String = String(target.contract_id())
		if id.is_empty():
			_fail("a target has no contract_id.")
		if target.enemy_type == null:
			_fail("%s has no enemy_type." % id)
		if target.cost <= 0:
			_fail("%s costs %d — contracts must be paid for." % [id, target.cost])
		if target.respawn_delay_s <= 0.0:
			_fail("%s has a non-positive respawn delay." % id)
		if target.cost < last_cost:
			_fail("catalog is not cheapest-first at %s." % id)
		last_cost = target.cost
		if BossHuntCatalog.find(target.contract_id()) != target:
			_fail("%s is not findable by its own id." % id)

		# XP must never beat the open world: the instance is the faster farm, not
		# the better one. A target authored above 1.0 would invert that.
		if target.xp_mult <= 0.0 or target.xp_mult > 1.0:
			_fail("%s pays %.2fx XP — must be in (0, 1]; the world kill stays superior." % [
				id, target.xp_mult])

		# No solo discount, and the fight grows with the party.
		var solo: float = target.party_health(1)
		var duo: float = target.party_health(2)
		var full: float = target.party_health(BossHuntService.PARTY_SIZE)
		var authored: float = target.enemy_type.max_health if target.enemy_type != null else 0.0
		if solo <= 0.0:
			_fail("%s would spawn with no health." % id)
		if solo < authored:
			_fail("%s gives a SOLO DISCOUNT (%d hp vs %d authored)." % [id, int(solo), int(authored)])
		if duo <= solo or full <= duo:
			_fail("%s health does not scale up with party size (%d/%d/%d)." % [
				id, int(solo), int(duo), int(full)])

		print("  %-20s %8d g  L%-3d  %ds  xp %d%%  hp %d -> %d" % [
			id, target.cost, target.recommended_level, int(target.respawn_delay_s),
			roundi(target.xp_mult * 100.0), int(solo), int(full),
		])


## A contract is the SAME boss as the one in the world, only tougher.
##
## Drop rates live on the EnemyTypeResource, and a contract scales nothing but
## health, damage and XP — so the instant a target points at a DIFFERENT file
## from the one a map places, the instanced fight quietly gets a different loot
## table. Nothing else reports that: both files carry the same enemy_type, so
## every log, quest and slayer task still resolves.
##
## This is how the Bloated Sovereign became the only source of the Siltbound set:
## its contract held a sibling file while the Sewers pad held another, and the
## uniques sat on the contract's copy. That sibling is deleted, but the shape of
## the mistake is one ext_resource line away at any time.
##
## A boss the world does not place at all (a pure contract fight) is exempt —
## there is no world table to disagree with.
func _check_same_boss_as_the_world() -> void:
	var placed: Dictionary = _map_placed_enemies()
	for target: BossHuntTarget in BossHuntCatalog.all():
		if target.enemy_type == null:
			continue # already reported by _check_catalog
		var id: String = String(target.contract_id())
		var mine: String = target.enemy_type.resource_path.simplify_path()
		var world: String = String(placed.get(target.enemy_type.enemy_type, ""))
		if world.is_empty() or world == mine:
			continue
		_fail("%s fights %s but the world places %s — same enemy_type, different loot table."
			% [id, mine.get_file(), world.get_file()])


## enemy_type -> the resource path a map scene actually places for it.
##
## Map scenes are read as TEXT: a headless gate has no business instancing every
## biome to answer "which files does this reference", and the ext_resource header
## is the whole answer.
func _map_placed_enemies() -> Dictionary:
	var out: Dictionary = {}
	for path: String in FileUtils.get_all_file_at(MAPS_PATH, "*.tscn"):
		for line: String in FileAccess.get_file_as_string(path).split("
"):
			if not line.begins_with("[ext_resource") or not line.contains(TYPES_PATH):
				continue
			var res_path: String = _attr(line, "path")
			if res_path.is_empty():
				var uid_text: String = _attr(line, "uid")
				var uid: int = ResourceUID.text_to_id(uid_text) if not uid_text.is_empty() else -1
				if uid != ResourceUID.INVALID_ID and ResourceUID.has_id(uid):
					res_path = ResourceUID.get_id_path(uid)
			if res_path.is_empty():
				continue
			var enemy: EnemyTypeResource = ResourceLoader.load(res_path) as EnemyTypeResource
			if enemy != null and not enemy.enemy_type.is_empty():
				out[enemy.enemy_type] = res_path.simplify_path()
	return out


## One quoted attribute out of a .tscn header line, or "" if it carries none.
func _attr(line: String, name: String) -> String:
	var key: String = ' %s="' % name
	if not line.contains(key):
		return ""
	return line.get_slice(key, 1).get_slice('"', 0)


func _check_arena_scene() -> void:
	var packed: PackedScene = load(ARENA_SCENE) as PackedScene
	if packed == null:
		_fail("arena scene failed to load: %s" % ARENA_SCENE)
		return
	var root: Node = packed.instantiate()
	if root is not Map:
		_fail("arena root is %s, expected a Map." % root.get_class())
		root.free()
		return
	var map: Map = root as Map
	# The exported container only resolves from the scene's node_paths — a missing
	# bake is exactly the bug AGENTS.md warns about on boss maps.
	if map.replicated_props_container == null:
		_fail("arena map has no replicated_props_container (node_paths not baked).")

	var arena: BossHuntArena = null
	for child: Node in map.get_children():
		if child is BossHuntArena:
			arena = child as BossHuntArena
			break
	if arena == null:
		_fail("arena scene has no BossHuntArena child on the map root.")
	elif arena.boss_spawn == null:
		_fail("BossHuntArena.boss_spawn is not wired (node_paths not baked).")

	# BossHuntService switches players in on warper 0, and the party needs a way
	# out before the clock runs down.
	var spawn: Warper = null
	var exit_station: BossHuntExit = null
	for child: Node in map.get_children():
		if child is Warper and (child as Warper).warper_id == 0:
			spawn = child as Warper
		elif child is BossHuntExit:
			exit_station = child as BossHuntExit
	if spawn == null:
		_fail("arena has no warper_id 0 — players would spawn at the map origin.")
	if exit_station == null:
		_fail("arena has no BossHuntExit — no deliberate way to leave early.")

	# Everything gameplay-relevant must sit on the walkable floor. The base scene
	# this map was cut from has a second, WALLED-OFF corridor; a node parked in it
	# is unreachable, which is exactly the bug this catches.
	var ground: TileMapLayer = map.get_node_or_null(^"Map_tiles/Ground") as TileMapLayer
	var walls: TileMapLayer = map.get_node_or_null(^"Map_tiles/Walls") as TileMapLayer
	if ground != null and walls != null:
		var places: Dictionary = {}
		if spawn != null:
			places["spawn warper"] = spawn.position
		if exit_station != null:
			places["exit station"] = exit_station.position
		if arena != null and arena.boss_spawn != null:
			places["boss spawn"] = arena.boss_spawn.global_position
		for label: String in places:
			var cell: Vector2i = ground.local_to_map(places[label])
			if ground.get_cell_source_id(cell) == -1:
				_fail("%s at %s is off the floor (cell %s)." % [label, places[label], cell])
			elif walls.get_cell_source_id(cell) != -1:
				_fail("%s at %s is inside a wall (cell %s)." % [label, places[label], cell])
	root.free()


func _check_arena_resource() -> void:
	var res: Resource = load(ARENA_RES)
	if res == null or res is not InstanceResource:
		_fail("arena InstanceResource failed to load: %s" % ARENA_RES)
		return
	var instance: InstanceResource = res as InstanceResource
	if instance.instance_name != BossHuntService.ARENA_INSTANCE:
		_fail("arena instance_name is '%s', service looks up '%s'." % [
			instance.instance_name, BossHuntService.ARENA_INSTANCE])
	if not ResourceLoader.exists(instance.map_path):
		_fail("arena map_path does not exist: %s" % instance.map_path)
	if instance.load_at_startup:
		_fail("arena must not load_at_startup — each contract gets its own copy.")


func _check_broker() -> void:
	var res: Resource = load(BROKER_RES)
	if res == null:
		_fail("Hunt Broker NPCResource failed to load.")
		return
	var offers_board: bool = false
	var offers_chest: bool = false
	for inter: Variant in res.get("interactions"):
		if inter is BossHuntInteraction:
			offers_board = true
		elif inter is HuntChestInteraction:
			offers_chest = true
	if not offers_board:
		_fail("Hunt Broker has no BossHuntInteraction — the board is unreachable.")
	if not offers_chest:
		_fail("Hunt Broker has no HuntChestInteraction — loot would be unreachable.")


## Text check, not an instantiate: the Guild Hall holds champion statues and
## other CLIENT scripts that reference the ClientState autoload, which does not
## exist in a `-s` tool run — instantiating it here fails for reasons that have
## nothing to do with the broker.
func _check_guild_hall() -> void:
	var text: String = FileAccess.get_file_as_string(GUILD_HALL)
	if text.is_empty():
		_fail("Guild Hall scene could not be read.")
		return
	if not text.contains('[node name="HuntBroker"'):
		_fail("Guild Hall has no HuntBroker node.")
	if not text.contains(BROKER_RES):
		_fail("Guild Hall does not reference the Hunt Broker NPCResource.")


func _check_chest() -> void:
	var resource: PlayerResource = PlayerResource.new()
	var id: int = 1
	if HuntChest.deposit(resource, id, 5) != 5:
		_fail("HuntChest.deposit did not store a fresh stack.")
	if HuntChest.deposit(resource, id, 3) != 3:
		_fail("HuntChest.deposit did not merge into an existing stack.")
	if PendingChestLoot.count(resource.hunt_chest, id) != 8:
		_fail("HuntChest stack total is wrong after two deposits.")
	if HuntChest.stack_count(resource) != 1:
		_fail("HuntChest merged deposits into separate stacks.")
	# Cap: fill to MAX_STACKS with distinct ids, then a NEW id must be refused
	# while an existing one still grows.
	for i: int in range(2, HuntChest.MAX_STACKS + 1):
		HuntChest.deposit(resource, i, 1)
	if not HuntChest.is_full(resource):
		_fail("HuntChest did not report full at MAX_STACKS.")
	if HuntChest.deposit(resource, HuntChest.MAX_STACKS + 99, 1) != 0:
		_fail("a full HuntChest accepted a new item id.")
	if HuntChest.deposit(resource, id, 2) != 2:
		_fail("a full HuntChest refused to grow an existing stack.")
	print("chest: %d stacks at cap %d" % [HuntChest.stack_count(resource), HuntChest.MAX_STACKS])
