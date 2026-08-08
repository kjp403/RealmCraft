extends Node
## Events Autoload (only for the client side)
## Should be removed on non-client exports.


signal local_player_ready(local_player: LocalPlayer)
signal player_profile_requested(id: int)
## Same as player_profile_requested but the target is identified by PEER id (a world
## click) — the client doesn't carry the persistent player_id, so the server resolves
## it (see profile.get.gd).
signal player_profile_by_peer_requested(peer_id: int)
## A remote player's world hitbox was right-clicked. The HUD owns presentation
## and turns this into Examine / Follow / Trade actions.
signal player_context_requested(peer_id: int)
## Right-click a hostile → HUD opens Attack menu for that NPC.
signal hostile_context_requested(npc: HostileNpc)
signal open_menu_requested(menu: StringName, arg: Variant)
signal dm_requested(id: int)
## Emitted on the client after a successful gather (mining, ...). Carries the
## gather result so UI can refresh xp/inventory.
signal gather_succeeded(result: Dictionary)
## Bag contents changed outside gather (e.g. picked up a ground drop). Inventory
## UIs listening to gather_succeeded also listen here for a refresh.
signal inventory_changed(result: Dictionary)
## The quest currently shown on the HUD tracker changed (0 = none).
signal tracked_quest_changed(quest_id: int)
## An objective of [quest_id] ticked forward (server quest.update progress entry) —
## the tracker listens to pulse its display (tracker-first, docs/notifications.md).
signal quest_progressed(quest_id: int)

## Quest id pinned to the HUD tracker (manually via the log, or the latest
## accepted). -1 = none — the DEFAULT (owner call 2026-07-20): the tracker
## starts hidden every session and only shows once the player pins/accepts a
## quest; the choice is session-local, deliberately not persisted anywhere.
var tracked_quest_id: int = -1

## The private trade session whose panel is open (0 = closed).
signal viewed_trade_changed(trade_id: int)
var viewed_trade_id: int
## Emitted whenever the active input type changes. [br]
## [b]Example[/b]: switching from keyboard to gamepad.
signal input_changed(input_type: InputComponent.InputType)

var local_player: LocalPlayer
var player_id: int
## Fires when the wardstone mirror updates (login sync or a fresh grant) —
## sealed portals listen so they unseal live, without a map reload.
signal wardstones_changed
## Earned wardstone slugs, mirrored from the server (wardstones.set push at login
## + on every grant) — lets sealed portals render/explain with no round trip.
var wardstones: PackedStringArray
## The local character's level, mirrored from progression data (progression.get on
## spawn/map change + combat.reward pushes — see HUD._apply_progression). Client-side
## cosmetic checks only (e.g. a gated Portal suppressing its fade); the server enforces.
var player_level: int = 1
## True while a blocking menu is open (NPC dialogue, shop, quest log, inventory).
## While set, the local player's movement and actions are suppressed, so you can't
## walk or fight with a menu up, and can't keep one open to act from afar. Only the
## movement polling is gated. Raw key events still flow, so menu UI can use arrows
## or stick for navigation later.
var menu_open: bool = false
## How many talkable world interactables (NPC click-areas) the cursor is over. While
## > 0, combat input is suppressed (InputComponent._ui_blocks_combat) so clicking an NPC
## to talk doesn't ALSO fire your weapon — the world-space mirror of the GUI gate.
## Counter, so overlapping NPCs balance; each NPC clears its own contribution on free.
var world_interactables_hovered: int = 0
## Fired when the local player's tagged guild changes (login / tag / create /
## join / leave). Ally-aware visuals (e.g. guild guard health bars) listen so
## they re-evaluate without a relog.
signal active_guild_id_changed(value: int)
var active_guild_id: int:
	set(value):
		if value == active_guild_id:
			return
		active_guild_id = value
		# Mirror into the static Player/HostileNpc read (avoids them importing us).
		Character.local_viewer_guild_id = value
		active_guild_id_changed.emit(value)
		_retint_local_players()
var stats: DataDict = DataDict.new()
var settings: Settings = Settings.new()
var quick_slots: DataDict = DataDict.new()
var guilds: DataDict = DataDict.new()

## Set of player_ids the local user has blocked. Used by chat_menu to drop
## incoming messages from blocked senders (server already filters too, but
## this catches the brief window between a Block click and the next message
## the server may have already dispatched). Hydrated once at instance entry
## via social.block.list and kept in sync as the user blocks/unblocks.
var blocked_ids: Dictionary[int, bool]
## Fired when blocked_ids changes — profile/chat-settings menus listen so
## their UI mirrors the live state without a refresh round-trip.
signal blocked_ids_changed

## Persistent friend player_ids for green nameplates. Hydrated from friend.list
## on spawn and kept in sync when the friends menu refreshes / accepts / removes.
var friend_ids: Dictionary[int, bool]
signal friend_ids_changed

var language: String:
	set(value):
		var loaded_locales: PackedStringArray = TranslationServer.get_loaded_locales()
		if loaded_locales.is_empty() or value not in loaded_locales: value = "en_US"
		language = value
		TranslationServer.set_locale(value)

var input_type: InputComponent.InputType:
	set(value):
		input_type = value
		input_changed.emit(value)


## Re-color visible players' team health bars after the local guild changes —
## already-spawned players read Character.local_viewer_guild_id (set above) but
## need a nudge to re-evaluate. Called by method name to avoid importing Player.
func _retint_local_players() -> void:
	if not is_instance_valid(local_player):
		return
	var map: Node = local_player.get_parent()
	if map == null:
		return
	for child: Node in map.get_children():
		if child.has_method(&"_apply_team_bar_color"):
			child.call(&"_apply_team_bar_color")
		if child.has_method(&"refresh_nameplate_color"):
			child.call(&"refresh_nameplate_color")


func set_friend_ids_from_list(payload: Dictionary) -> void:
	friend_ids.clear()
	for friend_id: Variant in payload:
		var id: int = int(friend_id)
		if id > 0:
			friend_ids[id] = true
	Character.local_friend_ids = friend_ids.duplicate()
	friend_ids_changed.emit()
	_retint_local_players()


func add_friend_id(id: int) -> void:
	if id <= 0:
		return
	friend_ids[id] = true
	Character.local_friend_ids = friend_ids.duplicate()
	friend_ids_changed.emit()
	_retint_local_players()


func remove_friend_id(id: int) -> void:
	if id <= 0:
		return
	friend_ids.erase(id)
	Character.local_friend_ids = friend_ids.duplicate()
	friend_ids_changed.emit()
	_retint_local_players()


func _hydrate_friend_ids(_lp: LocalPlayer = null) -> void:
	# friend.list is a world-server social handler (no instance id), same as the
	# Friends menu — keep nameplates green even if the dock is never opened.
	Client.request_data(
		&"friend.list",
		func(payload: Dictionary) -> void:
			if payload.has("ok") and not bool(payload.get("ok", true)):
				return
			set_friend_ids_from_list(payload)
	)


func _ready() -> void:
	if not GameMode.is_client():
		queue_free()
	Client.subscribe(&"player_id.set", func(payload: Dictionary):
		player_id = payload.get("player_id", 0))
	Client.subscribe(&"active_guild_id.set", func(payload: Dictionary):
		active_guild_id = payload.get("active_guild_id", 0))
	# Friend-green nameplates: pull the list once we have a local player + world.
	local_player_ready.connect(_hydrate_friend_ids)
	Client.subscribe(&"wardstones.set", func(payload: Dictionary):
		wardstones = PackedStringArray(payload.get("wardstones", []))
		wardstones_changed.emit())
	# The campaign's heartbeat moment — bigger than a level-up (docs/wardstones.md).
	Client.subscribe(&"wardstone.granted", func(payload: Dictionary):
		var stone: String = str(payload.get("stone", ""))
		var next_zone: String = ZoneDiscovery.zone_unlocked_by(stone)
		Announcer.announce(
			"%s Wardstone" % stone.capitalize(),
			("The way to %s is open." % next_zone) if not next_zone.is_empty()
				else "The frontier is pushed one gate deeper.",
			{"eyebrow": "Wardstone reclaimed", "duration": 4.0, "sfx": UISound.WARDSTONE}
		))
	Client.subscribe(&"stats.get", func(data: Dictionary):
		stats.data.merge(data, true)
	)
	Client.subscribe(&"combat.reward", _on_combat_reward)
	Client.subscribe(&"mining.gather_result", _on_gather_result)
	Client.subscribe(&"item.picked_up", _on_item_picked_up)
	Client.subscribe(&"chest.opened", _on_chest_opened)
	Client.subscribe(&"quest.update", func(data: Dictionary):
		# Tracker-first routing (docs/notifications.md, 2026-07-20): PROGRESS
		# entries arrive as dicts {q, t} — live state belongs to the TRACKER
		# (it pulses; no card for the tracked quest), untracked quests get ONE
		# self-replacing card each (1/5 becomes 2/5 in place, never a stack).
		# EVENT lines stay strings ("ready to turn in", "Quest complete",
		# "Title unlocked") and keep the grouped card — one card per push.
		var events: PackedStringArray = []
		for entry: Variant in data.get("messages", []):
			if entry is Dictionary:
				var e: Dictionary = entry
				var quest_id: int = int(e.get("q", 0))
				quest_progressed.emit(quest_id)
				if bool(e.get("ready", false)):
					# Ready-to-turn-in: a state the tracked quest's TRACKER
					# already shows (green + "Return to...") — card only when
					# untracked. The kalimba chime marks the moment either way.
					UISound.play(UISound.QUEST_READY, 1.0, -4.0)
					if quest_id != tracked_quest_id:
						events.append(str(e.get("t", "")))
				elif quest_id != tracked_quest_id:
					Toaster.toast_feed(
						"questprog:%d" % quest_id, "Quest",
						PackedStringArray([str(e.get("t", ""))])
					)
			elif not str(entry).is_empty():
				events.append(str(entry))
		if not events.is_empty():
			Toaster.toast_group("Quest", events)
	)

	settings.load_file()
	# Control-layout migration: LMB is now movement/interact and Space is the
	# primary attack. Only migrate the former shipped default; any other custom
	# attack binding remains untouched.
	if settings.get_value(&"mouse_keyboard", &"player_shoot") == "mouse:1":
		settings.set_value(
			&"mouse_keyboard",
			&"player_shoot",
			"physical:Space"
		)
	# Special slot 1 was RMB; HUD labels it Q — migrate the old default so Q works.
	if settings.get_value(&"mouse_keyboard", &"player_special") == "mouse:2":
		settings.set_value(
			&"mouse_keyboard",
			&"player_special",
			"physical:Q"
		)
	settings.setting_changed.connect(_on_setting_changed)
	language = settings.data.get(&"general", {}).get(&"language", "en_US")
	# Saved keybinds must hold from boot (gateway, menus) — not only once the
	# local player's InputComponent spawns.
	InputComponent.apply_saved_binds()


## Server-pushed kill rewards: surface them as ONE grouped toast card
## ("Defeated a Goblin" + XP + loot + level-up) so the player reads it
## as a single event instead of three flashes that happen to land
## together. enemy_type may be missing for non-mob reward paths (basing
## etc.) — falls back to a generic "Reward" header in that case.
func _on_combat_reward(data: Dictionary) -> void:
	var enemy_type: String = str(data.get("enemy_type", ""))
	var title: String = "Defeated %s" % _readable_enemy_name(enemy_type) if not enemy_type.is_empty() else "Reward"

	# Loot: inventory kills use the compact ICON feed; ground drops just name
	# what landed so players know to click-pick it up.
	var lines: PackedStringArray = PackedStringArray()
	var ground_loot: bool = bool(data.get("ground", false))
	for entry: Dictionary in data.get("loot", []):
		var loot_id: int = int(entry.get("id", 0))
		var loot_amount: int = int(entry.get("amount", 1))
		var loot_name: String = str(entry.get("name", "item"))
		if ground_loot:
			if loot_amount > 1:
				lines.append("Dropped %s ×%d" % [loot_name, loot_amount])
			else:
				lines.append("Dropped %s" % loot_name)
		else:
			LootFeed.add_item(loot_id, loot_amount, loot_name)
	# Character level-up ceremony (fireworks + jingle + banner) rides the
	# level.up broadcast in InstanceClient — avoid a second banner/sfx here.
	# Attribute points still get a quiet corner line so the gain isn't lost.
	if int(data.get("levels_gained", 0)) > 0:
		var pts: int = int(data.get("points_gained", 0))
		if pts > 0:
			Toaster.toast("+%d attribute points" % pts)
	var big: PackedStringArray = PackedStringArray()
	var mastery: Dictionary = data.get("mastery", {})
	if bool(mastery.get("started", false)):
		big.append("%s Mastery begun! +1 mastery point (Character > Mastery)" % str(mastery.get("category", "")).capitalize())
	elif bool(mastery.get("leveled_up", false)):
		# Mastery level-ups get the same fireworks / jingle ceremony.
		if local_player != null:
			LevelUpFx.celebrate(
				local_player,
				"%s Mastery" % str(mastery.get("category", "")).capitalize(),
				int(mastery.get("level", 1)),
			)
		else:
			big.append("%s Mastery Lv %d! +1 mastery point" % [
				str(mastery.get("category", "")).capitalize(),
				int(mastery.get("level", 1)),
			])
	if not big.is_empty():
		Toaster.toast_group("Mastery", big)

	if lines.is_empty() and enemy_type.is_empty():
		return  # Nothing to show.
	# Repeated kills coalesce into one "Defeated a Goblin ×N" card; quest/basing
	# reward turn-ins (no enemy_type) are rare one-offs on the big lane.
	if enemy_type.is_empty():
		Toaster.toast_group(title, lines)
	else:
		Toaster.toast_feed("kill:" + enemy_type, title, lines)


## Server-pushed harvest result. Re-uses the gather_succeeded signal +
## toast format that the legacy click-based mining handler used, so quest
## tracking and any inventory UI that already listens to gather_succeeded
## keeps working unchanged.
## Throttle for the "depleted" toast — depleted swings are now rejected
## server-side on every hit, so without this the message would spam.
var _last_depleted_toast_ms: int


func _on_item_picked_up(data: Dictionary) -> void:
	if data.is_empty():
		return
	var item_id: int = int(data.get("id", 0))
	var amount: int = int(data.get("amount", 0))
	var item_name: String = str(data.get("name", "item"))
	# Ground-drop / admin-grant pickups are "quiet": refresh the bag, but do NOT
	# inflate the left-side LootFeed (drop→pickup loops were showing Copper Ore
	# ×50 while the bag still held 10). Combat/mining loot keeps using LootFeed.
	if not bool(data.get("quiet", false)):
		if item_id > 0 and amount > 0:
			LootFeed.add_item(item_id, amount, item_name)
	elif item_id > 0 and amount > 0:
		# Quiet grants still need a readable confirmation — otherwise /give can
		# succeed server-side while the player thinks nothing arrived.
		Toaster.toast("Received %s ×%d" % [item_name, amount] if amount > 1 \
			else "Received %s" % item_name)
	inventory_changed.emit(data)


## Server-pushed loot chest open: gold + items already in the bag; show LootFeed.
func _on_chest_opened(data: Dictionary) -> void:
	if data.is_empty():
		return
	var gold: int = int(data.get("gold", 0))
	if gold > 0 and Economy.gold_id() > 0:
		LootFeed.add_item(Economy.gold_id(), gold, "Gold")
	for entry: Dictionary in data.get("items", []):
		var item_id: int = int(entry.get("id", 0))
		var amount: int = int(entry.get("amount", 0))
		var item_name: String = str(entry.get("name", "item"))
		if item_id > 0 and amount > 0:
			LootFeed.add_item(item_id, amount, item_name)
	var chest_name: String = str(data.get("chest", "Loot Chest"))
	Toaster.toast("Opened %s" % chest_name)
	inventory_changed.emit(data)


func _on_gather_result(data: Dictionary) -> void:
	if data.is_empty():
		return

	# Route progress + charge state to the node's local visuals so the bar +
	# label show only when the node is mid-extraction or partially depleted.
	# Only fires for the player who swung — broadcast can come later if other
	# players need to see live state on the same node.
	_apply_node_visual_state(data)

	# Keep the click-to-gather loop in sync (stop on wrong tool, wait on deplete).
	if local_player != null:
		local_player.notify_gather_result(data)

	if not data.get("ok", false):
		match str(data.get("reason", "")):
			"no_tool":
				Toaster.toast("You need a gathering tool equipped.")
			"wrong_tool":
				Toaster.toast("You need a %s for this." % str(data.get("required_tool", "different tool")).replace("_", " ").capitalize())
			"too_far":
				Toaster.toast("Too far from the node.")
			"level":
				var job_label: String = str(data.get("job_display", "")).strip_edges()
				if job_label.is_empty():
					job_label = str(data.get("job", "skill")).capitalize()
				Toaster.toast("Requires %s Lv %d." % [job_label, int(data.get("required_level", 0))])
			"depleted":
				# HarvestController toasts when auto-gather stops on deplete;
				# only toast here for manual / stray swings.
				if local_player != null and local_player.is_auto_gathering():
					pass
				else:
					var now_ms: int = Time.get_ticks_msec()
					if now_ms - _last_depleted_toast_ms > 4000:
						_last_depleted_toast_ms = now_ms
						Toaster.toast("Resource depleted. Click again when it regenerates.")
			# "cooldown" stays silent — players will spam swings during it.
		return

	# Successful hit. Two shapes:
	#   { ok: true, extracted: false, progress_hp, extraction_hp }   ← just a swing
	#   { ok: true, extracted: true,  ore_id, amount, xp, ... }      ← a full yield
	if not data.get("extracted", false):
		# Mid-extraction swings are intentionally silent — feedback comes
		# from the swing animation + (future) chip-sound, not a toast.
		return

	gather_succeeded.emit(data)

	# The yield itself rides the icon feed; the card keeps only job XP + level-ups.
	var job_slug: String = str(data.get("job", "mining"))
	var title: String = "Caught" if job_slug == "fishing" else (
		"Chopped" if job_slug == "woodcutting" else (
			"Farmed" if job_slug == "harvesting" else "Mined"
		)
	)

	var lines: PackedStringArray = PackedStringArray()
	var amount: int = int(data.get("amount", 0))
	if amount > 0:
		LootFeed.add_item(int(data.get("ore_id", 0)), amount, str(data.get("ore_name", "ore")))
	# XP entries — primary job first (verbose), additional grants compact.
	var grants_v: Variant = data.get("grants", [])
	if grants_v is Array:
		for grant: Dictionary in grants_v:
			lines.append("+%d %s XP" % [int(grant.get("xp", 0)), str(grant.get("job", "")).capitalize()])
	# Profession level-up: fireworks + jingle + "Your Mining level has achieved N".
	# Check every grant so multi-job nodes (e.g. herb + medicine) each celebrate.
	var leveled_jobs: Dictionary = {}
	if data.get("leveled_up", false):
		leveled_jobs[job_slug] = int(data.get("level", 1))
	if grants_v is Array:
		for grant: Dictionary in grants_v:
			var prog: Dictionary = grant.get("progress", {})
			if bool(prog.get("leveled_up", false)):
				leveled_jobs[str(grant.get("job", ""))] = int(prog.get("level", 1))
	if local_player != null:
		for job_key: Variant in leveled_jobs.keys():
			var slug: String = str(job_key)
			if slug.is_empty():
				continue
			var new_lv: int = int(leveled_jobs[job_key])
			var skill_label: String = JobRegistry.display_name(StringName(slug))
			if skill_label.is_empty():
				skill_label = slug.capitalize()
			lines.append("Your %s level has achieved %d" % [skill_label, new_lv])
			LevelUpFx.celebrate_skill(local_player, StringName(slug), new_lv)
	if int(data.get("perk_points_gained", 0)) > 0:
		Toaster.toast("Perk point available. Spend in Character → Jobs.")

	Toaster.toast_feed("gather:" + str(data.get("ore_name", "ore")), title, lines)


## Look up the MineableNode the result is about and push the new progress +
## charge counts into its [method MineableNode.apply_visual_state]. Silently
## no-ops if the path is missing (older result shapes) or the node went away
## (instance switch / despawn between the swing and the push).
func _apply_node_visual_state(data: Dictionary) -> void:
	var raw_path: Variant = data.get("node_path", null)
	if raw_path == null:
		return
	if InstanceClient.current == null:
		return
	var path: NodePath = raw_path as NodePath
	var node: Node = InstanceClient.current.get_node_or_null(path)
	if node == null or not (node is MineableNode):
		return
	(node as MineableNode).apply_visual_state(
		int(data.get("progress_hp", 0)),
		int(data.get("extraction_hp", 1)),
		int(data.get("charges_left", 0)),
		int(data.get("max_charges", 1)),
	)


## "bandit_captain" → "a Bandit Captain". Article ("a"/"an") chosen by
## first letter so we don't produce "a Orc" / "a Iron Warlord" weirdness.
func _readable_enemy_name(slug: String) -> String:
	if slug.is_empty():
		return "an enemy"
	var words: PackedStringArray = slug.split("_")
	var titled: PackedStringArray = PackedStringArray()
	for w: String in words:
		if w.is_empty():
			continue
		titled.append(w.substr(0, 1).to_upper() + w.substr(1))
	var pretty: String = " ".join(titled)
	var article: String = "an" if "aeiou".contains(pretty.substr(0, 1).to_lower()) else "a"
	return "%s %s" % [article, pretty]


## Pin a quest to the HUD tracker (from the quest log, or auto on accept).
func set_tracked_quest(quest_id: int) -> void:
	tracked_quest_id = quest_id
	tracked_quest_changed.emit(quest_id)


## Replace the local block list (called after a social.block.list bootstrap).
func set_blocked_ids(entries: Array) -> void:
	blocked_ids.clear()
	for entry: Dictionary in entries:
		blocked_ids[int(entry.get("id", 0))] = true
	blocked_ids_changed.emit()


## Mark a player as blocked locally. Server confirms first.
func add_blocked(id: int) -> void:
	if id <= 0:
		return
	blocked_ids[id] = true
	blocked_ids_changed.emit()


## Unmark a player. Server confirms first.
func remove_blocked(id: int) -> void:
	blocked_ids.erase(id)
	blocked_ids_changed.emit()


## Open/close the private trade panel (0 = close).
func set_viewed_trade(trade_id: int) -> void:
	viewed_trade_id = trade_id
	viewed_trade_changed.emit(trade_id)


func _on_setting_changed(section: StringName, property: StringName, new_value: Variant) -> void:
	match property:
		"language":
			language = new_value


class DataDict:
	signal data_changed(property: Variant, value: Variant)
	
	var data: Dictionary
	
	
	func _set(property: StringName, value: Variant) -> bool:
		if property == &"data":
			return false
		data[property] = value
		data_changed.emit(property, value)
		return true
	
	
	func set_key(key: Variant, value: Variant) -> void:
		data.set(key, value)
		data_changed.emit(key, value)
	
	
	func get_key(property: Variant, default: Variant = null) -> Variant:
		return data.get(property, default)


class Settings:
	const SETTINGS_PATH: String = "user://client_settings.cfg"
	const DEFAULTS_PATH: String = "res://data/config/client_default_settings.cfg"

	signal setting_changed(section: StringName, property: StringName, new_value: Variant)

	var data: Dictionary
	var _defaults: Dictionary


	func load_file() -> void:
		_defaults = ConfigFileUtils.load_file_with_defaults(DEFAULTS_PATH, {})
		data = ConfigFileUtils.load_file_with_defaults(SETTINGS_PATH, _defaults)


	## The shipped default for a setting ([code]null[/code] if it has none) —
	## used by "Reset to Defaults" flows.
	func get_default(section: StringName, property: StringName) -> Variant:
		return _defaults.get(section, {}).get(property)


	## Every shipped default of a section (empty if the section has none).
	func get_defaults_section(section: StringName) -> Dictionary:
		return _defaults.get(section, {})


	func save() -> void:
		ConfigFileUtils.save_sections(data, SETTINGS_PATH)
	

	func get_value(section: StringName, property: StringName) -> Variant:
		return data.get(section, {}).get(property)


	func set_value(section: StringName, property: StringName, value: Variant) -> void:
		if not data.has(section):
			data[section] = {}
		data[section][property] = value
		setting_changed.emit(section, property, value)
		save()
