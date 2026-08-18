extends SceneTree
## Headless checks for smithing material tabs, craft-tooltip mastery swap,
## Ascension Emporium removal, wildlife levels, slayer/commands surfaces.
## Run: godot --headless --path . -s tools/verify_gameplay_ux_fixes.gd

func _init() -> void:
	var failures: PackedStringArray = PackedStringArray()

	# Craft menu: smithing tiers + jewelry rename + craft-level tooltip.
	var craft_src: String = FileAccess.get_file_as_string(
		"res://source/client/ui/menus/crafting/crafting_menu.gd"
	)
	for token: String in ["bronze", "iron", "steel", "mithril", "adamant", "runite", "ascended", "jewelry"]:
		if craft_src.find('&"%s"' % token) < 0:
			failures.append("crafting_menu missing tab token %s" % token)
	if craft_src.find('ItemTooltip.body(') < 0:
		failures.append("crafting_menu missing ItemTooltip.body craft call")
	if craft_src.find("_station.profession") < 0:
		failures.append("crafting_menu craft tooltip missing profession arg")

	var tip_src: String = FileAccess.get_file_as_string(
		"res://source/client/ui/item_tooltip.gd"
	)
	if tip_src.find("craft_profession") < 0:
		failures.append("ItemTooltip.body missing craft_profession param")
	if tip_src.find('Requires %s level %d') < 0:
		failures.append("ItemTooltip missing craft level requirement line")

	# Ascension Emporium removed from Hub + dev merchant.
	var hub: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/maps/maps/hub.tscn"
	)
	if hub.find("AscensionBrokerVael") >= 0:
		failures.append("hub still has AscensionBrokerVael")
	if hub.find("ascension_broker_vael") >= 0:
		failures.append("hub still references ascension_broker_vael")
	if hub.find("BankerYard") >= 0:
		failures.append("hub still has outdoor banker by the smith house")
	var merchant: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/characters/npc/npcs/dev_all_merchant.tres"
	)
	if merchant.find("ascension_shop") >= 0 or merchant.find("Ascension · Emporium") >= 0:
		failures.append("dev_all_merchant still sells Ascension Emporium")

	# Wildlife levels.
	var badger: Resource = load("res://source/common/gameplay/characters/npc/types/woodland_rat.tres")
	var wolf: Resource = load("res://source/common/gameplay/characters/npc/types/wolf.tres")
	if badger == null or int(badger.get("combat_level")) != 20:
		failures.append("Woodland Badger combat_level != 20")
	if wolf == null or int(wolf.get("combat_level")) != 22:
		failures.append("Wild Wolf combat_level != 22")

	# Slayer HUD + info handler.
	if not ResourceLoader.exists("res://source/client/ui/hud/slayer_tracker.gd"):
		failures.append("missing slayer_tracker.gd")
	if not ResourceLoader.exists("res://source/server/world/components/data_request_handlers/slayer.info.gd"):
		failures.append("missing slayer.info.gd")
	var hud: String = FileAccess.get_file_as_string("res://source/client/ui/hud/hud.tscn")
	if hud.find("SlayerTracker") < 0:
		failures.append("hud.tscn missing SlayerTracker")

	# Commands UI.
	if not ResourceLoader.exists("res://source/client/ui/menus/settings/commands_panel.gd"):
		failures.append("missing commands_panel.gd")
	if not ResourceLoader.exists("res://source/server/world/components/data_request_handlers/chat.commands.list.gd"):
		failures.append("missing chat.commands.list.gd")
	var compact: String = FileAccess.get_file_as_string(
		"res://source/client/ui/compact_menus/compact_settings_host.gd"
	)
	if compact.find("Chat commands") < 0:
		failures.append("compact settings missing Chat commands button")
	var settings_tscn: String = FileAccess.get_file_as_string(
		"res://source/client/ui/menus/settings/settings_menu.tscn"
	)
	if settings_tscn.find("CommandsButton") < 0:
		failures.append("settings_menu missing CommandsButton")

	# Mining gate eject fix.
	var gate: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/maps/components/skill_level_gate.gd"
	)
	if gate.find("eject_direction") < 0:
		failures.append("skill_level_gate missing eject_direction")

	var trade: String = FileAccess.get_file_as_string(
		"res://source/client/ui/hud/trade_panel.gd"
	)
	if trade.find("func _open_qty") < 0 or trade.find("_make_picker_gold_button") < 0:
		failures.append("trade panel missing gold picker / offer-X amount UI")
	if trade.find("_qty_spin.apply()") < 0 or trade.find("_gold_spin.apply()") < 0:
		failures.append("trade panel must apply() SpinBox text before offering gold")
	if trade.find("current if current > 0 else owned") >= 0:
		failures.append("trade qty overlay must not default to all owned gold/items")
	var chat: String = FileAccess.get_file_as_string(
		"res://source/client/ui/menus/chat/chat_menu.gd"
	)
	if chat.find("_pending_chat_focus") < 0:
		failures.append("chat must defer Enter focus so combat+chat doesn't crash")

	var smith_inside: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/maps/maps/smith_house/inside_map.tscn"
	)
	if smith_inside.find("ForgeSmith") >= 0 or smith_inside.find("Forge Smith") >= 0:
		failures.append("smith house inside still has Forge Smith — replace with banker beside Mira")
	if smith_inside.find("npcs/banker.tres") < 0 or smith_inside.find("npcs/mira.tres") < 0:
		failures.append("smith house inside must have banker beside Mira")
	var east: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/maps/maps/woodland/woodland_east.tscn"
	)
	if east.find("mineable_nodes/bloodcap.tres") < 0 \
			or east.find("mineable_nodes/starblossom.tres") < 0 \
			or east.find("mineable_nodes/grimshade.tres") < 0:
		failures.append("woodland east missing bloodcap/starblossom/grimshade nodes")
	var slayer_shop: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/shops/resources/slayer_shop.tres"
	)
	if slayer_shop.find("enchanted_cloth.tres") < 0 \
			or slayer_shop.find("dragon_ore.tres") < 0 \
			or slayer_shop.find("sirenic_leather.tres") < 0:
		failures.append("slayer shop missing Enchanted/Dragon/Sirenic materials")
	var fighter: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/characters/npc/types/bandits/bandit_fighter.tres"
	)
	if fighter.find("attack_damage = 29.0") >= 0:
		failures.append("bandit fighter damage was not nerfed for new players")

	if failures.is_empty():
		print("VERIFY_PASS gameplay_ux_fixes")
		quit(0)
	else:
		print("VERIFY_FAIL")
		for line: String in failures:
			print("  - ", line)
		quit(1)
