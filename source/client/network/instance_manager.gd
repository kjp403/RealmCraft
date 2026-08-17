class_name InstanceManagerClient
extends Node


signal instance_changed(instance: InstanceClient)


var current_ui: UI
var current_instance: InstanceClient
## Warp/login destination, applied when the reused LocalPlayer is parented into
## the new map. Position is client-authoritative, so a late state-sync cannot
## place the avatar — without this, arrivals keep the previous map's coordinates
## and land in empty space (Mining Cave / Smith House "null spawn").
var pending_spawn: Vector2 = Vector2.ZERO


func _ready() -> void:
	pass


## Free the live world (map) + HUD and clear the InstanceClient statics so the client
## can cleanly return to the gateway. These live under PERSISTENT parents — this
## manager under the Client autoload, the UI added under root — so a scene reload
## alone does NOT free them, which left the old world rendering under the rebuilt
## login menu after a disconnect. Transition._back_to_login calls this first.
func teardown() -> void:
	if current_instance and is_instance_valid(current_instance):
		current_instance.queue_free()
	current_instance = null
	if current_ui and is_instance_valid(current_ui):
		current_ui.queue_free()
	current_ui = null
	# A local player PARKED for a map load (see _park_local_player) sits on this
	# manager, not in the instance we just freed — so nothing else takes it down.
	# Free it here or it survives the teardown and follows the user to the login
	# screen. (The old orphaning had the same leak, with no parent at all.)
	var parked: Node = InstanceClient.local_player
	if parked != null and is_instance_valid(parked) and parked.get_parent() == self:
		parked.queue_free()
	InstanceClient.current = null
	InstanceClient.local_player = null
	ClientState.local_player = null


## Hold the reused local player somewhere ALIVE AND IN-TREE while the next map
## loads, instead of leaving it parentless.
##
## A node outside the tree has a NULL get_tree() AND a null multiplayer — but the
## local player keeps receiving network pushes and UI signals for the whole load
## window (death/respawn, channel start/end, equip cast, the chat typing gate).
## Every one of those dereferenced the null and took the client down, which is
## why players crashed teleporting — and dying, which teleports you to your spawn
## point. Clicking the chat box on the load screen was a one-click repro.
## Character._sync_overhead already carried a hand-rolled is_inside_tree() guard
## against this; parking fixes the cause instead of one symptom.
##
## Processing is OFF while parked so nothing ticks against the map we just freed,
## and it stays hidden so the avatar doesn't render over the empty world — which
## is what being orphaned gave us for free. [method InstanceClient.spawn_player]
## reverses both when it moves the player into the new map.
func _park_local_player(player: Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	var previous: Node = player.get_parent()
	if previous != null:
		previous.remove_child(player)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	if player is CanvasItem:
		(player as CanvasItem).hide()
	add_child(player)


@rpc("authority", "call_remote", "reliable", 0)
func charge_new_instance(
	map_path: String,
	instance_id: String,
	spawn_x: float = 0.0,
	spawn_y: float = 0.0
) -> void:
	# Positional banners (sealed portal / level warning) are about the map we're
	# LEAVING — kill them so they never follow the player into the next biome.
	Announcer.dismiss_positional()
	pending_spawn = Vector2(spawn_x, spawn_y)
	var new_instance: InstanceClient = InstanceClient.new()
	new_instance.name = instance_id

	map_path = _resolve_map_path(map_path)
	print("Loading new map: %s." % map_path)
	if map_path.is_empty() or not ResourceLoader.exists(map_path):
		push_error("InstanceManagerClient: map path missing: %s" % map_path)
		_fail_charge("Couldn't load the area (missing map).")
		return
	var map_scene: PackedScene = load(map_path) as PackedScene
	if map_scene == null:
		push_error("InstanceManagerClient: load() returned null for %s" % map_path)
		_fail_charge("Couldn't load the area.")
		return
	var map: Map = map_scene.instantiate() as Map
	if map == null:
		push_error("InstanceManagerClient: instantiate() failed for %s" % map_path)
		_fail_charge("Couldn't load the area.")
		return
	new_instance.instance_map = map
	
	map.ready.connect(
		new_instance.ready_to_enter_instance.rpc_id.bind(1),
		CONNECT_ONE_SHOT
	)
	map.ready.connect(
		instance_changed.emit.bind(new_instance),
		CONNECT_ONE_SHOT
	)
	# First-visit region banner (client-only cosmetic; no-op for known/unlisted maps).
	map.ready.connect(
		ZoneDiscovery.on_map_loaded.bind(map_path),
		CONNECT_ONE_SHOT
	)
	
	if current_instance:
		_park_local_player(current_instance.local_player)
		current_instance.queue_free()
	current_instance = new_instance

	new_instance.add_child(map, true)
	add_child(new_instance, true)
	
	# Charge different type of UI/HUD and clear old one,
	# for mini game / special instances that would require unique HUD ? 
	
	#if current_ui:
		#current_ui.queue_free()
	if not current_ui:
		current_ui = preload("res://source/client/ui/ui.tscn").instantiate()
		get_parent().add_sibling(current_ui)


## Map charge failed before the local player could spawn — drop the enter overlay
## so the player isn't stuck on "Entering the world…" with a silent load error.
func _fail_charge(message: String) -> void:
	push_error(message)
	if is_instance_valid(Client):
		Client.close_connection()
	if is_instance_valid(Transition):
		Transition.show_load_error(message)


## Buildings often author map_path as uid://. ResourceLoader.exists() on a uid
## misses after a reimport; resolve to res:// before loading.
static func _resolve_map_path(map_path: String) -> String:
	if not map_path.begins_with("uid://"):
		return map_path
	var uid: int = ResourceUID.text_to_id(map_path)
	if uid == ResourceUID.INVALID_ID or not ResourceUID.has_id(uid):
		return ""
	return ResourceUID.get_id_path(uid)
	
