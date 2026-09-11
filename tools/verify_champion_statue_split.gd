extends Node
## Gate: the Guild Hall champion statue must never make the world server parse
## client code.
##
## champion_statue.gd is parsed on every world-server boot, because the Guild
## Hall is a load_at_startup map. While it named client-only classes, Godot 4.7.1
## segfaulted inside that load on roughly 4 boots in 10: on 2026-09-11 that was
## 52 and 58 crash-restarts on back-to-back deploys, one failed deploy, and the
## world down for half an hour. The client half now lives in
## champion_statue_client.gd, loaded by path on a client only.
##
## Runs as a SCENE so the client autoloads exist and the client half can be
## compiled for real.
##
##   godot --headless --path . res://tools/verify_champion_statue_split.tscn

const STATUE: String = "res://source/common/gameplay/leaderboard/champion_statue.gd"
const CLIENT: String = "res://source/common/gameplay/leaderboard/champion_statue_client.gd"
## Identifiers that only resolve on a client. Any of them in the statue script
## puts the client class graph back on the server's startup load.
const CLIENT_ONLY: Array[String] = [
	"ClientState", "InstanceClient", "LocalPlayer", "ClickableArea", "GameMode", "Client.",
]


func _ready() -> void:
	var fails: Array[String] = []
	var src: String = FileAccess.get_file_as_string(STATUE)
	if src.is_empty():
		fails.append("could not read " + STATUE)
	for ident: String in CLIENT_ONLY:
		if src.contains(ident):
			fails.append("champion_statue.gd names client-only " + ident)
	if src.contains("preload("):
		fails.append("champion_statue.gd preloads a resource; load the client half by path")
	var client: GDScript = load(CLIENT) as GDScript
	if client == null or not client.can_instantiate():
		fails.append("champion_statue_client.gd does not compile")
	for f: String in fails:
		print("VERIFY_FAIL ", f)
	if fails.is_empty():
		print("VERIFY_PASS champion_statue_split")
	get_tree().quit(1 if not fails.is_empty() else 0)
