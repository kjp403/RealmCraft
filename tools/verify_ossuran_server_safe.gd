extends Node
## Gate: clicking Enter on the Ossuran gate must never make the world server parse
## client code.
##
## These three scripts are compiled by the world server for the first time when a
## party enters Ossuran's Ruin — no load_at_startup map and nothing in fire_forge
## loads them. While they named the Client autoload, that first compile pulled in
## client.gd and the whole client class graph, and Godot 4.7.1 segfaulted inside
## the load: on 2026-09-11 every Enter dropped every player on the world. Same
## crash class as the Guild Hall champion statue at boot
## (verify_champion_statue_split). The autoload is now reached by node path.
##
## Runs as a SCENE so the client autoloads exist and the scripts are compiled for
## real, not just text-scanned.
##
##   godot --headless --path . res://tools/verify_ossuran_server_safe.tscn

const SCRIPTS: Array[String] = [
	"res://source/common/gameplay/ossuran/ossuran_arena.gd",
	"res://source/common/gameplay/ossuran/charge_pad.gd",
	"res://source/common/gameplay/ossuran/environment_transition_manager.gd",
]
## Identifiers that only resolve on a client. Any of them in code (comments are
## stripped first) puts the client class graph back on the server's Enter load.
const CLIENT_ONLY: Array[String] = [
	"Client", "ClientState", "InstanceClient", "LocalPlayer", "ClickableArea",
	"Announcer", "UISound", "Toaster",
]


func _ready() -> void:
	var fails: Array[String] = []
	var ident: RegEx = RegEx.new()
	for path: String in SCRIPTS:
		var src: String = FileAccess.get_file_as_string(path)
		if src.is_empty():
			fails.append("could not read " + path)
			continue
		var code: String = _strip_comments_and_strings(src)
		for name: String in CLIENT_ONLY:
			ident.compile("\\b" + name + "\\b")
			if ident.search(code) != null:
				fails.append("%s names client-only %s" % [path.get_file(), name])
		var script: GDScript = load(path) as GDScript
		if script == null or not script.can_instantiate():
			fails.append("%s does not compile" % path.get_file())
	for f: String in fails:
		print("VERIFY_FAIL ", f)
	if fails.is_empty():
		print("VERIFY_PASS ossuran_server_safe")
	get_tree().quit(1 if not fails.is_empty() else 0)


## Drop `#` comments and string literals so a doc comment or a node path like
## "/root/Client" never reads as an identifier.
func _strip_comments_and_strings(src: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	var strings: RegEx = RegEx.new()
	strings.compile("\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'")
	for line: String in src.split("\n"):
		var no_strings: String = strings.sub(line, "\"\"", true)
		var hash_at: int = no_strings.find("#")
		out.append(no_strings if hash_at == -1 else no_strings.substr(0, hash_at))
	return "\n".join(out)
