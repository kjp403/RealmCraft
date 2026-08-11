class_name InstanceManagerClient
extends Node


signal instance_changed(instance: InstanceClient)


var current_ui: UI
var current_instance: InstanceClient


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
	InstanceClient.current = null
	InstanceClient.local_player = null
	ClientState.local_player = null


@rpc("authority", "call_remote", "reliable", 0)
func charge_new_instance(map_path: String, instance_id: String) -> void:
	# Positional banners (sealed portal / level warning) are about the map we're
	# LEAVING — kill them so they never follow the player into the next biome.
	Announcer.dismiss_positional()
	var new_instance: InstanceClient = InstanceClient.new()
	new_instance.name = instance_id
	
	print("Loading new map: %s." % map_path)
	if not ResourceLoader.exists(map_path):
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
		if current_instance.local_player:
			current_instance.instance_map.remove_child(current_instance.local_player)
			#current_instance.local_player.reparent(new_instance, false)
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
	
