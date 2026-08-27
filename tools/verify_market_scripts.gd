extends Node
## Compile gate for the Trading Post's scripts and scenes.
##
## `--check-only --script` cannot see the project autoloads, so every client
## script "fails" there on `Client` / `ClientState`. Loading them from a real
## scene run does have the autoloads, which makes this the only honest way to
## prove the market UI and its handlers parse.
##
## Run: godot --headless --path . tools/verify_market_scripts.tscn

const PATHS: Array[String] = [
	"res://source/common/gameplay/market/market.gd",
	"res://source/server/world/database/market_store.gd",
	"res://source/server/world/data/market_service.gd",
	"res://source/server/world/components/data_request_handlers/market.browse.gd",
	"res://source/server/world/components/data_request_handlers/market.buy.gd",
	"res://source/server/world/components/data_request_handlers/market.list.gd",
	"res://source/server/world/components/data_request_handlers/market.history.gd",
	"res://source/server/world/components/data_request_handlers/market.mine.gd",
	"res://source/server/world/components/data_request_handlers/market.reprice.gd",
	"res://source/server/world/components/data_request_handlers/market.set_store.gd",
	"res://source/server/world/components/data_request_handlers/market.store.gd",
	"res://source/server/world/components/data_request_handlers/market.unlist.gd",
	"res://source/server/world/components/data_request_handlers/mail.claim.gd",
	"res://source/client/ui/menus/market/market_menu.gd",
	"res://source/client/ui/menus/market/market_menu.tscn",
	"res://source/client/ui/menus/mail/mail_menu.tscn",
	"res://source/client/ui/hud/menu_overlay.gd",
	"res://source/common/gameplay/characters/npc/npcs/market_steward.tres",
	"res://source/common/gameplay/characters/npc/npcs/mail_clerk.tres",
	"res://source/common/gameplay/maps/maps/guild_house/inside_map.tscn",
]

var _fail: int = 0


func _ready() -> void:
	for path: String in PATHS:
		var resource: Resource = load(path)
		if resource == null:
			_fail += 1
			printerr("  FAIL  %s" % path)
		else:
			print("  ok    %s" % path)
	_check_stall_wiring()
	print("VERIFY_PASS" if _fail == 0 else "VERIFY_FAIL")
	get_tree().quit(0 if _fail == 0 else 1)


## The stall NPC is only useful if its two options actually route to the market
## menu — a typo in `menu` would silently give the player a dead dialogue button.
func _check_stall_wiring() -> void:
	var steward: NPCResource = load("res://source/common/gameplay/characters/npc/npcs/market_steward.tres")
	var routes: Dictionary = {}
	for interaction: NPCInteraction in steward.interactions:
		var entry: Dictionary = interaction.menu_entry(null)
		if entry.has("menu"):
			routes[str(entry.get("label", ""))] = "%s/%s" % [entry["menu"], entry.get("arg", "")]
	_ck(routes.get("View Shops", "") == "market/browse", "View Shops opens the market board")
	_ck(routes.get("Open Store", "") == "market/mine", "Open Store opens your own stall")

	var clerk: NPCResource = load("res://source/common/gameplay/characters/npc/npcs/mail_clerk.tres")
	var mail_route: String = ""
	for interaction: NPCInteraction in clerk.interactions:
		var entry: Dictionary = interaction.menu_entry(null)
		if entry.has("menu"):
			mail_route = String(entry["menu"])
	_ck(mail_route == "mail", "the Mail Clerk opens the mailbox")

	var map: PackedScene = load("res://source/common/gameplay/maps/maps/guild_house/inside_map.tscn")
	var names: PackedStringArray = PackedStringArray()
	var state: SceneState = map.get_state()
	for i: int in state.get_node_count():
		names.append(String(state.get_node_name(i)))
	_ck(names.has("MarketStall"), "the Guild Hall has a Market Stall")
	_ck(names.has("MailClerk"), "the Guild Hall has a Mail Clerk")


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok    %s" % label)
	else:
		_fail += 1
		printerr("  FAIL  %s" % label)
