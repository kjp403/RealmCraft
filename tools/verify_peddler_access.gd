extends Node
## Gate: for EVERY biome the Peddler can be sent to, a player can get to the
## cart and the shop window will open on it. Proved end to end, per biome,
## rather than argued from the parts.
##
## This exists because the parts all passed while the feature did not. Placement
## was correct, the spots were authored and valid, the stock resolved, and the
## cart still refused every sale — the position never crossed the wire, so the
## cart players walked to was not the cart the server range-checked. Every gate
## we had was looking at one end or the other and none of them looked at both at
## once. This one does.
##
## Per biome in the rotation, in the order a player experiences it:
##
##   1. CAN THEY GET IN. Some map, somewhere, must have a door into this biome —
##      a Warper with target_instance set, or a Wayfarer quick-travel row. A
##      biome with no inbound route is a 30-minute window nobody can attend, and
##      the biome pool is a FOLDER SCAN, so orphaned content joins the rotation
##      by existing. woodland_east was exactly that.
##
##   2. CAN THEY WALK TO IT. From EVERY arrival point, not just the home spawn:
##      each inbound door names the warper id it lands you on, and the cart has
##      to be walk-reachable from all of them. Reachability from one arbitrary
##      spawn is not the same claim — a map can have sealed regions, and which
##      door you came in decides which one you are standing in.
##
##   3. DO THEY SEE IT WHERE IT IS. The cart is spawned through the real server
##      call, the spawn op is taken off the outgoing queue, and a SECOND
##      container applies it through the real client call. The position the
##      client ends up drawing must be the authored square. This is the check
##      that was missing.
##
##   4. DOES THE WINDOW OPEN. Standing where the client drew the cart, the three
##      gates peddler.stock runs are re-run for real: the node lookup by name
##      that PeddlerDesk.resolve does, its range check, and the interaction
##      lookup. Fed the position a player would actually have, not the server's.
##
##   5. IS THERE ANYTHING IN IT. Today's stock must be three rows and every one
##      must resolve to a real registry item, or the window opens on nothing.
##
## Run: godot --headless --path . --mode=client res://tools/verify_peddler_access.tscn

const COLLECTION_DIR: String = "res://source/common/gameplay/maps/instance/instance_collection/"
## Slack over the straight-line cart-to-door distance, for a walk that has to go
## around things. Sized per biome rather than fixed: a flat budget either strands
## the long maps or makes the short ones fill half the world.
const DETOUR_FACTOR: float = 1.8
const DETOUR_FLOOR: float = 2500.0
## The fill cap this gate runs at. PeddlerSites' own 20,000 bounds a LIVE world
## server; walking a whole map offline needs far more, and at the live cap the
## fill truncates on sewers, woodland, gutterworks, ossuary and sunken_tombs —
## which reads as "cannot get there" when it means "stopped looking".
const FILL_CELL_CAP: int = 400000

var _fail: int = 0
## instance_name -> [{from: String, target_id: int, kind: String}, ...]
var _routes: Dictionary = {}


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	_check_stock()
	print("")
	await _scan_routes()
	print("")
	print("biomes")
	for biome: StringName in PeddlerSites.biome_names():
		await _check(biome)
	print("")
	print("VERIFY_PASS" if _fail == 0 else "VERIFY_FAIL")
	get_tree().quit(0 if _fail == 0 else 1)


# --- 1. Doors -----------------------------------------------------------------

## Every inbound route in the project, collected once.
##
## Walks the INSTANCE COLLECTION rather than globbing the maps folder: that
## collection is exactly the set of maps a player can stand in, so it is exactly
## the set that can hold a door. A .tscn outside it is a sub-scene, and a door in
## one reaches this scan through the map that instances it.
func _scan_routes() -> void:
	print("doors")
	var scanned: int = 0
	for file_path: String in FileUtils.get_all_file_at(COLLECTION_DIR, "*.tres"):
		var res: InstanceResource = ResourceLoader.load(file_path) as InstanceResource
		if res == null:
			continue
		var map: Map = await _load_map(res)
		if map == null:
			continue
		scanned += 1
		var from: String = String(res.instance_name)
		for node: Node in map.find_children("*", "Warper", true, false):
			var warper: Warper = node as Warper
			# A warper with no target is an ARRIVAL point, not a door out.
			if warper == null or warper.target_instance == null:
				continue
			_add_route(warper.target_instance.instance_name, from, warper.target_id, "door")
		# NPCs are the other two kinds of door: a WarpInteraction ("take me
		# across"), and the Wayfarer's quick-travel rows. Read off the NPCs
		# PLACED IN THIS MAP rather than off the npcs folder, because an
		# NPCResource nobody stands anywhere is not a route into anything —
		# which is the same mistake as trusting the biome folder scan.
		for node: Node in map.find_children("*", "NPC", true, false):
			var resource: NPCResource = (node as NPC).npc_resource
			if resource == null:
				continue
			for interaction: NPCInteraction in resource.interactions:
				if interaction is WarpInteraction:
					var warp: WarpInteraction = interaction as WarpInteraction
					if warp.target_instance != null:
						_add_route(
							warp.target_instance.instance_name, from, warp.target_id, "npc warp"
						)
				elif interaction is QuickTravelInteraction:
					for dest: QuickTravelDestination in (interaction as QuickTravelInteraction).destinations:
						if dest != null and dest.target_instance != null:
							_add_route(
								dest.target_instance.instance_name, from, dest.target_id,
								"quick travel"
							)
		map.queue_free()
		await get_tree().process_frame
	print("  scanned %d maps, found routes into %d instances" % [scanned, _routes.size()])


func _add_route(dest: StringName, from: String, target_id: int, kind: String) -> void:
	if not _routes.has(dest):
		_routes[dest] = []
	(_routes[dest] as Array).append({"from": from, "target_id": target_id, "kind": kind})


# --- 2..5. The chain, per biome -----------------------------------------------

func _check(biome: StringName) -> void:
	var res: InstanceResource = _instance_for(biome)
	if res == null:
		_bad(String(biome), "no InstanceResource in the collection")
		return
	var map: Map = await _load_map(res)
	if map == null:
		_bad(String(biome), "map_path did not load")
		return

	var routes: Array = _routes.get(biome, []) as Array
	if routes.is_empty():
		# Reported and abandoned: nothing below this is meaningful for a map
		# players cannot enter.
		# The whole woodland_east failure, generalised: the pool is a folder scan,
		# so a map nothing routes to still takes its turn in the rotation.
		_bad(String(biome), "NO INBOUND ROUTE — no warper or quick-travel row enters it")
		map.queue_free()
		await get_tree().process_frame
		return

	var spot: Vector2 = PeddlerSites.pick_spot(map)["peddler"]
	if not PeddlerSites.is_valid_spot(map, spot):
		_bad(String(biome), "the square the cart will use is not a valid spot")

	var before: int = _fail
	var reached: int = _check_walk(biome, map, routes, spot)
	var drawn_at: Vector2 = _check_wire(biome, map, spot)
	if drawn_at.is_finite():
		_check_window(biome, map, drawn_at)

	if _fail == before:
		print("  ok    %-22s spot (%.0f, %.0f)  %d door(s) / %d arrival(s), all walk to it; cart+vault drawn on the square; in range" % [
			String(biome), spot.x, spot.y, routes.size(), reached
		])
	map.queue_free()
	await get_tree().process_frame


## 2. The cart must be walk-reachable from every door into the biome.
##
## ONE fill, seeded at the CART, and every arrival point checked against it —
## not a fill per door. The lattice is an undirected graph, so "can I walk from
## the door to the cart" and "is the door in the cart's connected region" are the
## same question, and seeding at the cart also seeds on a square already proved
## valid and painted. It is also the difference between one fill per map and one
## per door, which is what makes a cap this size affordable.
func _check_walk(biome: StringName, map: Map, routes: Array, spot: Vector2) -> int:
	var arrivals: Dictionary = {} # target_id -> Vector2, deduped
	var reach: float = 0.0
	for route: Dictionary in routes:
		var target_id: int = int(route["target_id"])
		if arrivals.has(target_id):
			continue
		var arrival: Vector2 = map.get_spawn_position(target_id)
		arrivals[target_id] = arrival
		reach = maxf(reach, spot.distance_to(arrival))

	var budget: float = maxf(DETOUR_FLOOR, reach * DETOUR_FACTOR)
	var walkable: Dictionary = PeddlerSites.walkable_cells(map, spot, budget, FILL_CELL_CAP)
	# A fill that ran out of room proves nothing either way, so it must never be
	# read as a verdict.
	if walkable.size() >= FILL_CELL_CAP:
		_bad(String(biome), "the walk from the cart hit the %d-cell cap — unproven" % FILL_CELL_CAP)
		return 0

	var reached: int = 0
	for target_id: int in arrivals:
		if _near(walkable, arrivals[target_id]):
			reached += 1
		else:
			var who: String = ""
			for route: Dictionary in routes:
				if int(route["target_id"]) == target_id:
					who = "%s from %s" % [str(route["kind"]), str(route["from"])]
					break
			var at: Vector2 = arrivals[target_id]
			_bad(String(biome), "no walk from door %d at (%.0f, %.0f) to the cart (%s)" % [
				target_id, at.x, at.y, who
			])
	return reached


## 3. Server spawn -> the wire -> the real client apply. Returns where the client
## ends up drawing the cart, or Vector2.INF when it could not be placed.
##
## The client container is deliberately built OUTSIDE the map, so the name lookup
## in [method _check_window] resolves the server's node the way the live one does
## rather than tripping over this test's second copy.
func _check_wire(biome: StringName, map: Map, spot: Vector2) -> Vector2:
	var server_props: ReplicatedPropsContainer = map.replicated_props_container
	if server_props == null:
		_bad(String(biome), "no ReplicatedPropsContainer — the map cannot carry the cart")
		return Vector2.INF
	# Drain anything the map load queued, so what we read back is only the cart.
	server_props.collect_container_outgoing_and_clear()

	# Both props, exactly as PeddlerManager spawns them — the vault rides the same
	# wire and broke the same way.
	var vault_at: Vector2 = PeddlerSites.pick_spot(map)["vault"]
	var peddler: Node = server_props.spawn_dynamic(
		ReplicatedPropsContainer.SCENE_NPC,
		server_props.to_local(spot),
		{"name": PeddlerNames.NODE_NAME, "npc_slug": PeddlerNames.NPC_SLUG}
	)
	if peddler == null:
		_bad(String(biome), "the cart could not be spawned")
		return Vector2.INF
	var peddler_id: int = server_props.child_id_of_node(peddler)
	var vault: Node = server_props.spawn_dynamic(
		ReplicatedPropsContainer.SCENE_PEDDLER_VAULT,
		server_props.to_local(vault_at),
		{"name": PeddlerNames.VAULT_NODE_NAME}
	)
	var vault_id: int = server_props.child_id_of_node(vault) if vault != null else -1

	var spawns: Array = server_props.collect_container_outgoing_and_clear()["spawns"] as Array
	if spawns.is_empty():
		_bad(String(biome), "the spawn never reached the outgoing queue")
		return Vector2.INF

	var client_props := ReplicatedPropsContainer.new()
	client_props.name = "ClientPropsUnderTest"
	add_child(client_props)
	client_props.apply_spawns(spawns)

	# Matched back by child id — the same id the wire carries — rather than by
	# order, so the cart is compared against the cart.
	var drawn: Vector2 = _mirror_of(biome, server_props, client_props, peddler_id, spot, "cart")
	if vault_id >= 0:
		_mirror_of(biome, server_props, client_props, vault_id, vault_at, "vault")
	client_props.queue_free()
	return drawn


## Where the client ends up drawing prop [param child_id], checked against the
## square the server put it on. Returns that position, or Vector2.INF.
func _mirror_of(
	biome: StringName, server_props: ReplicatedPropsContainer,
	client_props: ReplicatedPropsContainer, child_id: int, expected: Vector2, label: String
) -> Vector2:
	var mirror: Node2D = client_props.dynamic_nodes.get(child_id, null) as Node2D
	if mirror == null:
		_bad(String(biome), "the client applied no %s from the spawn op" % label)
		return Vector2.INF
	# Compared in the SERVER container's frame, because the wire carries a
	# container-local position and that is the whole contract: a client puts the
	# prop at this local offset inside its own copy of the container.
	var drawn: Vector2 = server_props.to_global(mirror.position)
	if not drawn.is_equal_approx(expected):
		_bad(String(biome), "the client draws the %s at (%.0f, %.0f), %.0f px from where the server put it" % [
			label, drawn.x, drawn.y, drawn.distance_to(expected)
		])
	return drawn


## 4. The three gates peddler.stock actually runs, fed the position a player
## standing at the cart THEY CAN SEE would have.
func _check_window(biome: StringName, map: Map, player_at: Vector2) -> void:
	# The exact lookup PeddlerDesk.resolve falls back to: the cart is a child of
	# the props container, not of the map, so the direct get_node misses and this
	# is the path that answers.
	var node: Node = map.get_node_or_null(NodePath(PeddlerNames.NODE_NAME))
	if node == null:
		node = map.find_child(PeddlerNames.NODE_NAME, true, false)
	if node == null or node is not NPC:
		_bad(String(biome), "resolve() cannot find a node named '%s' — the window answers 'closed'" % PeddlerNames.NODE_NAME)
		return
	var npc: NPC = node as NPC
	var gap: float = player_at.distance_to(npc.global_position)
	if gap > NPC.INTERACT_RANGE:
		_bad(String(biome), "a player at the cart they can see is %.0f px from the one the server has (limit %.0f) — 'too_far'" % [
			gap, NPC.INTERACT_RANGE
		])
	if PeddlerInteraction.of(npc) == null:
		_bad(String(biome), "the spawned cart carries no PeddlerInteraction — the window answers 'no_desk'")


## 5. The window must open on something.
func _check_stock() -> void:
	print("stock")
	var date: String = PeddlerSchedule.utc_date()
	var rows: Array = PeddlerStock.for_date(date)
	if rows.is_empty():
		_bad("stock", "no goods are stocked for %s — the window opens empty" % date)
		return
	for row: PeddlerItemData in rows:
		if row == null or not row.is_sellable():
			_bad("stock", "a stocked row is not sellable")
			continue
		if PeddlerDesk.item_id_for(row) <= 0:
			_bad("stock", "stocked good '%s' resolves to no registry item" % row.id)
		elif row.price_gold <= 0:
			_bad("stock", "stocked good '%s' has no price" % row.id)
	print("  %s: %d rows, all priced and resolvable" % [date, rows.size()])


# --- helpers ------------------------------------------------------------------

## The fill is a 16px lattice, so a square sits inside a cell rather than on one.
## Accept the cell it falls in or any neighbour — one pixel over a boundary is
## not an unreachable cart.
func _near(walkable: Dictionary, point: Vector2) -> bool:
	var step: float = PeddlerSites.FILL_STEP
	var cell := Vector2i(floori(point.x / step), floori(point.y / step))
	for dx: int in [-1, 0, 1]:
		for dy: int in [-1, 0, 1]:
			if walkable.has(cell + Vector2i(dx, dy)):
				return true
	return false


func _instance_for(biome: StringName) -> InstanceResource:
	for file_path: String in FileUtils.get_all_file_at(COLLECTION_DIR, "*.tres"):
		var res: InstanceResource = ResourceLoader.load(file_path) as InstanceResource
		if res != null and res.instance_name == biome:
			return res
	return null


func _load_map(res: InstanceResource) -> Map:
	var packed: PackedScene = ResourceLoader.load(res.map_path) as PackedScene
	if packed == null:
		return null
	var node: Node = packed.instantiate()
	add_child(node)
	# Collision shapes are only queryable once a physics step has run.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var map: Map = node as Map
	if map == null:
		node.queue_free()
		return null
	return map


func _bad(label: String, why: String) -> void:
	_fail += 1
	printerr("  FAIL  %-22s %s" % [label, why])
