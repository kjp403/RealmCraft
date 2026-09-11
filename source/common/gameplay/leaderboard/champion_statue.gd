class_name ChampionStatue
extends Character
## A plaza statue wearing a leaderboard champion's skin, with a rank / name / score
## plaque. Pulls the cached champions ONCE when the local player enters this map; clicking it
## opens the champion's profile by player_id (so it works even while they're offline). Extends
## Character purely to reuse the skin_id->sprite property + the AnimatedSprite/AnimationPlayer;
## no combat — the over-head health bar + default name label are hidden, it never takes damage.
##
## SERVER-SAFE BY DESIGN. The Guild Hall loads at world-server startup, so this
## script is parsed on every boot. It must name nothing that only exists on a
## client: all of that lives in champion_statue_client.gd (read its header for
## the startup crash this split fixed), which _ready loads by path on a client.
## tools/verify_champion_statue_split.tscn enforces it.

## Which board this statue honors. Guild Hall currently uses "level" → Total Level only;
## pve/pvp remain for a future podium without a scene rewrite.
@export_enum("pve", "pvp", "level") var category: String = "level"
## Which place on that board this statue enshrines (1 = champion, 2/3 = podium, …). Drop several
## statues sharing a category with ascending rank to build a hall of fame. Capped to the service's
## STATUE_TOP_N; a rank with no one yet shows "(unclaimed)".
@export_range(1, 10) var rank: int = 1

## Loaded by PATH, never preloaded or named as a type, so the world server never
## parses the client half.
const CLIENT_SCRIPT_PATH: String = "res://source/common/gameplay/leaderboard/champion_statue_client.gd"


func _ready() -> void:
	health_bar_auto_hide = false # a statue never takes damage; no flashing bar ever
	super._ready()
	if multiplayer.is_server():
		return # display-only — all the statue logic is client-side
	var client_script: GDScript = load(CLIENT_SCRIPT_PATH) as GDScript
	if client_script == null:
		push_error("ChampionStatue: could not load " + CLIENT_SCRIPT_PATH)
		return
	var client_half: Node2D = client_script.new() as Node2D
	client_half.name = &"StatueClient"
	add_child(client_half)
