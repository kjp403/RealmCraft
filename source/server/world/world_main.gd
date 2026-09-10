class_name WorldMain
extends Node


var world_info: Dictionary


func _ready() -> void:
	# Server tick rate
	# For comparaison:
	# Eve Online - 1 tick par second.
	# Fortnite (Battle royale 100 players) - 30 ticks per second.
	# Albion Online - 2 ticks per second (to verify).
	# Valorant (5v5 FPS game) - 128 ticks per second.
	# I believe it depends of your game and architecture, it's a large topic.
	#
	# Raised 10 -> 20 to match the entity send rate. StateSynchronizerManagerServer
	# already ships entity state at send_rate_hz_entities = 20, so at a 10 Hz
	# simulation half of every position sent was a byte-for-byte repeat of the one
	# before it — the bandwidth was already being spent, the tick simply had nothing
	# new to put in it. Matching the two halves the movement correction window
	# (100 ms -> 50 ms, which is what rubber-banding keys on) and takes ~50 ms off
	# worst-case hit latency, for no extra bandwidth.
	#
	# Headroom measured on the live world before the change: 20.6% of one core with
	# 6 players, i.e. ~20 ms of work inside a 100 ms budget. Doubling the simulation
	# should land near 35%, comfortably inside the 50 ms a 20 Hz tick allows.
	Engine.set_physics_ticks_per_second(20) # 60 by default
	
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title("World Server")
	else:
		# Headless has no vsync, so _process — which drives the sync manager's
		# 20/10 Hz send accumulators — would spin uncapped and burn a full core.
		# 60 fps keeps the send timing accurate at a fraction of the CPU.
		Engine.max_fps = 60
	
	# Default config path. to use another one, override this;
	# or write --config=config_file_path.cfg as a launch argument.
	world_info = ConfigFileUtils.load_section_with_defaults(
		"world-server",
		CmdlineUtils.get_parsed_args().get("config", "res://data/config/world_config.cfg"),
		{
			"name": "NoName",
			"max_players": 200,
			"hardcore": false,
			"motd": "Welcome!",
			"bonus_xp": 0.0,
			"max_character": 5,
			"pvp": true
		}
		
	)
	await get_tree().create_timer(0.5).timeout
	if world_info.has("error"):
		printerr("World server loading configuration failed.")
	else:
		$Database.start_database(world_info)
		$WorldManagerClient.start_client_to_master_server(world_info)
		$WorldServer.start_world_server()
