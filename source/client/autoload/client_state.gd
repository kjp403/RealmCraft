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
## A dock panel (inventory, equipment, mastery, quests, ...) was opened from the
## bottom dock or its hotkey. The onboarding coach waits on these so a lesson can
## require the player to open the real panel instead of just reading about it.
signal compact_panel_opened(panel: StringName)
## The local player opened an NPC's dialogue, keyed by that NPC's giver slug.
## World markers (the Charter Clerk arrow) drop themselves once it fires.
signal npc_talked(giver_key: StringName)
## An NPC offered a guided lesson and the player took it (see TutorialInteraction).
signal tutorial_requested(topic: StringName)
## A mastery level-up crossed into a spendable point. The coach nudges the player
## to the tree the first time it happens.
signal mastery_point_earned(category: StringName, level: int)
## Emitted on the client after a successful gather (mining, ...). Carries the
## gather result so UI can refresh xp/inventory.
signal gather_succeeded(result: Dictionary)
## Bag contents changed outside gather (e.g. picked up a ground drop). Inventory
## UIs listening to gather_succeeded also listen here for a refresh.
signal inventory_changed(result: Dictionary)
## Quick-prayer set membership changed (a star toggled in the prayer book —
## see quick_prayers.gd). The prayer bar's Q button listens so it doesn't wait
## for the next prayer.state push to notice it went from empty to usable.
signal quick_prayers_changed
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
## Persistent account id of the character we're playing. Normally arrives in the
## player_id.set push at login, but that push is fired during auth — a client that
## isn't listening yet keeps a 0 here, and everything keyed on "who am I" (DM
## threads most visibly) then builds itself around the wrong id. The local Player
## node carries the same id as a synced property, so a missed push self-heals on
## the first read instead of stranding the session.
var player_id: int = 0:
	get = _get_player_id,
	set = _set_player_id
var _player_id: int = 0
## Fires when the wardstone mirror updates (login sync or a fresh grant) —
## sealed portals listen so they unseal live, without a map reload.
signal wardstones_changed
## Earned wardstone slugs, mirrored from the server (wardstones.set push at login
## + on every grant) — lets sealed portals render/explain with no round trip.
var wardstones: PackedStringArray
signal character_flags_changed
## Story flags mirrored from the server (character_flags.set at login + on grant).
var character_flags: Dictionary = {}


func has_character_flag(flag: StringName) -> bool:
	return bool(character_flags.get(flag, false))
## The local character's level, mirrored from progression data (progression.get on
## spawn/map change + combat.reward pushes — see HUD._apply_progression). Client-side
## cosmetic checks only (e.g. a gated Portal suppressing its fade); the server enforces.
var player_level: int = 1
## Profession skill levels for the local character (slug → int), mirrored from
## skills.get / login push + gather/craft level-ups. Used by client-authoritative
## skill checks (craft UI, skill gates) — the server still owns progression.
signal skill_levels_changed
var skill_levels: Dictionary = {}
## One client-side door for "the local character just banked profession XP",
## whatever paid it. Server-side every path already funnels through
## [method PlayerResource.add_skill_xp], but each handler answers on its OWN
## response type — so the funnel is rebuilt here rather than left to each HUD
## piece to reassemble from six payload shapes.
##
## [param xp_into_level] is XP banked toward the NEXT level, not lifetime XP:
## add_skill_xp subtracts each threshold as it crosses it. The denominator is
## [method SkillXp.xp_to_next], a static curve the client already carries, so
## it never has to travel.
##
## [param job] is always the SLUG (`outfitting`, `harvesting`), never a display
## name — run it through [method JobRegistry.display_name] before showing it.
## Only ever emitted with amount > 0; see [method _emit_skill_xp].
##
## [param leveled_up] is the SERVER's answer, forwarded rather than inferred.
## Every payload already carries it, and a client that instead compared levels
## between events would be wrong in exactly the cases that matter: the first
## tick of a session (nothing to compare against), a level-up that arrives in
## the same frame as a skill switch, and any tick that reaches a listener after
## something else has already written the level mirror.
signal skill_xp_gained(
	job: StringName, amount: int, xp_into_level: int, level: int, leveled_up: bool
)
## Weapon-mastery levels for the local character (category slug → int), mirrored
## from mastery.get on spawn + the combat.reward mastery payload. The CLIENT has
## no PlayerResource (it is server-only — see InstanceServer), so every tooltip /
## panel that needs "do I meet this mastery gate" reads THIS, not
## local_player.player_resource, which is always null here. Missing categories
## read as level 1, matching PlayerResource.mastery_level_of.
signal mastery_levels_changed
var mastery_levels: Dictionary = {}
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
## How many hostile click-boxes the cursor is over. Blocks click-to-move so a
## left-click Attack isn't cancelled by ground-move, but does NOT suppress
## combat (Space / hold-to-attack still work while the cursor is on a mob).
var world_hostiles_hovered: int = 0
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


func _get_player_id() -> int:
	if _player_id <= 0 and is_instance_valid(local_player) and local_player.player_id > 0:
		_player_id = local_player.player_id
	return _player_id


func _set_player_id(value: int) -> void:
	if value > 0 or _player_id <= 0:
		_player_id = value


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
	local_player_ready.connect(_restore_pending_chest_loot)
	Client.subscribe(&"wardstones.set", func(payload: Dictionary):
		wardstones = PackedStringArray(payload.get("wardstones", []))
		wardstones_changed.emit())
	Client.subscribe(&"character_flags.set", func(payload: Dictionary):
		character_flags.clear()
		for flag: Variant in payload.get("flags", []):
			character_flags[StringName(str(flag))] = true
		character_flags_changed.emit())
	# Profession levels for client-side skill gates (Mining vault, etc.).
	# skills.get is also pushed at login and after /skill admin sets.
	Client.subscribe(&"skills.get", func(payload: Dictionary):
		apply_skills_payload(payload.get("skills", {})))
	Client.subscribe(&"skills.levels", func(payload: Dictionary):
		apply_skill_levels(payload.get("levels", {})))
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
	# A stall sold something while its owner happened to be online. Purely a
	# nudge — the gold is already sitting in their mailbox either way.
	Client.subscribe(&"market.sold", func(data: Dictionary):
		Toaster.toast(str(data.get("text", "Something sold at your stall.")), 4.0)
	)
	# Server-authored float for a Traveling Peddler good that fired on its own
	# (the Hunter's Charm landing a boss drop). Pushed rather than derived: only
	# the server knows whether the blessing was what made the roll.
	Client.subscribe(&"peddler.toast", func(payload: Dictionary) -> void:
		var text: String = str(payload.get("text", ""))
		if not text.is_empty():
			Toaster.toast(text, 3.0, PixelUI.INK_GOLD)
	)
	Client.subscribe(&"combat.reward", _on_combat_reward)
	Client.subscribe(&"mining.gather_result", _on_gather_result)
	# Profession XP from the non-gathering skills. These are request/RESPONSE
	# types, not server pushes — Client._data_response fans every response back
	# through data_push, so subscribing here catches them without touching the
	# five menus that issue the requests (crafting has two call sites alone).
	# Gathering and Slayer are NOT listed: they carry extra payload the funnel
	# would have to re-parse, and are emitted from their own handlers below.
	for xp_response: StringName in [&"craft.item", &"item.salvage", &"altar.offer"]:
		Client.subscribe(xp_response, _on_skill_xp_response)
	Client.subscribe(&"quest.board.claim", _on_board_claim_xp)
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


## Profession XP off a craft / salvage / altar offering. All three answer with
## the same three fields, so one handler covers them.
func _on_skill_xp_response(data: Dictionary) -> void:
	if not bool(data.get("ok", false)):
		return
	_emit_skill_xp(
		StringName(str(data.get("profession", ""))),
		int(data.get("xp", 0)),
		int(data.get("xp_into_level", 0)),
		int(data.get("level", 0)),
		bool(data.get("leveled_up", false)),
	)


## Daily board claim. Its own handler because one claim can pay several skills
## at once, under "skill" rather than "profession".
func _on_board_claim_xp(data: Dictionary) -> void:
	if not bool(data.get("ok", false)):
		return
	var grants: Variant = data.get("skills", [])
	if grants is not Array:
		return
	for grant: Dictionary in (grants as Array):
		_emit_skill_xp(
			StringName(str(grant.get("skill", ""))),
			int(grant.get("xp", 0)),
			int(grant.get("xp_into_level", 0)),
			int(grant.get("level", 0)),
			bool(grant.get("leveled_up", false)),
		)


## Single gate in front of [signal skill_xp_gained].
##
## A zero amount is dropped rather than forwarded: it means no XP was actually
## paid (a zero-XP recipe, a salvage that yielded nothing), and on those paths
## the server leaves `progress` empty, so xp_into_level is a 0 PLACEHOLDER and
## not a genuinely empty bar. Forwarding it would snap the radial gauge to zero
## on an action that changed nothing. Gating once here keeps every consumer from
## having to know that.
func _emit_skill_xp(
	job: StringName,
	amount: int,
	xp_into_level: int,
	level: int,
	leveled_up: bool,
) -> void:
	if job == &"" or amount <= 0 or level <= 0:
		return
	skill_xp_gained.emit(job, amount, maxi(xp_into_level, 0), level, leveled_up)


## Server-pushed kill rewards: surface them as ONE grouped toast card
## ("Defeated a Goblin" + XP + loot + level-up) so the player reads it
## as a single event instead of three flashes that happen to land
## together. enemy_type may be missing for non-mob reward paths (basing
## etc.) — falls back to a generic "Reward" header in that case.
func _on_combat_reward(data: Dictionary) -> void:
	var enemy_type: String = str(data.get("enemy_type", ""))
	var title: String = "Defeated %s" % _readable_enemy_name(enemy_type) if not enemy_type.is_empty() else "Reward"

	# Loot: inventory kills use the compact ICON feed, right here, since the item
	# is already in the bag. Ground drops used to spell out "Dropped X" lines on
	# this same big center card, which is exactly what spattered the screen
	# during area-loot farming (a card per enemy type, each listing every drop)
	# — dropped entirely. Ground loot isn't granted yet at kill time (it's sitting
	# on the ground for click-pickup), so it gets NO feedback here; the compact
	# feed picks it up for real via _on_item_picked_up once the player actually
	# collects it. Boss Hunt kills bank straight into the Hunt Chest, so they
	# still say so — otherwise a farm session reads as "went to my bag" and the
	# player never goes to collect.
	var lines: PackedStringArray = PackedStringArray()
	var ground_loot: bool = bool(data.get("ground", false))
	var chest_loot: bool = bool(data.get("hunt_chest", false))
	for entry: Dictionary in data.get("loot", []):
		var loot_id: int = int(entry.get("id", 0))
		var loot_amount: int = int(entry.get("amount", 1))
		var loot_name: String = str(entry.get("name", "item"))
		var stack_text: String = "%s ×%d" % [loot_name, loot_amount] if loot_amount > 1 else loot_name
		if ground_loot:
			continue
		elif chest_loot:
			# banked=false means the chest hit its stack cap and refused a new id.
			if entry.get("banked", true):
				LootFeed.add_item(loot_id, loot_amount, loot_name)
			else:
				lines.append("Hunt Chest full — lost %s" % stack_text)
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
	# Keep the mastery mirror current off every kill — gear tooltips colour their
	# wear-gates against it, so a stale mirror reads as "locked" on gear you just
	# unlocked.
	var mastery_category: StringName = StringName(str(mastery.get("category", "")))
	var mastery_level: int = int(mastery.get("level", 0))
	# Level BEFORE this kill, so we can tell a plain level-up from the one that
	# actually hands over a spendable point (one per 3 levels, not one per level).
	var mastery_level_was: int = int(mastery_levels.get(String(mastery_category), 0))
	if not String(mastery_category).is_empty():
		set_mastery_level(mastery_category, mastery_level)
	if bool(mastery.get("started", false)):
		big.append("%s Mastery begun! (Character > Mastery)" % String(mastery_category).capitalize())
	elif bool(mastery.get("leveled_up", false)):
		# Mastery level-ups get the same fireworks / jingle ceremony.
		if local_player != null:
			LevelUpFx.celebrate(
				local_player,
				"%s Mastery" % String(mastery_category).capitalize(),
				maxi(mastery_level, 1),
			)
		else:
			big.append("%s Mastery Lv %d!" % [
				String(mastery_category).capitalize(),
				maxi(mastery_level, 1),
			])
	# Per-tree point rate: a 2x tree hands out 2 points on the same level, so the
	# toast has to be counted against THAT tree's budget, not the shared baseline.
	var mastery_tree: MasteryTreeResource = MasteryService.tree_for(mastery_category)
	var points_gained: int = (
		MasteryService.point_budget(mastery_level, mastery_tree)
		- MasteryService.point_budget(mastery_level_was, mastery_tree)
	)
	if bool(mastery.get("leveled_up", false)) and points_gained > 0:
		big.append("+%d %s mastery point%s to spend" % [
			points_gained,
			String(mastery_category).capitalize(),
			"" if points_gained == 1 else "s",
		])
		mastery_point_earned.emit(mastery_category, mastery_level)
	var slayer: Dictionary = data.get("slayer", {})
	# Slayer already shipped its own xp / xp_to_next on this push (the kill card
	# draws a bar from them), so it needs no server change to feed the tracker.
	_emit_skill_xp(
		&"slayer",
		int(slayer.get("xp_gained", 0)),
		int(slayer.get("xp", 0)),
		int(slayer.get("level", 0)),
		bool(slayer.get("leveled_up", false)),
	)
	if bool(slayer.get("leveled_up", false)):
		set_skill_level(&"slayer", int(slayer.get("level", 1)))
		if local_player != null:
			LevelUpFx.celebrate(local_player, "Slayer", int(slayer.get("level", 1)))
		else:
			big.append("Slayer Lv %d!" % int(slayer.get("level", 1)))
	elif int(slayer.get("level", 0)) > 0:
		set_skill_level(&"slayer", int(slayer.get("level", 1)))
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
	# Every pickup (ground click/area-loot, mining, /give) reports through the
	# same compact left-side feed — it already coalesces repeats, so a
	# drop→pickup loop bumps one pill's ×N instead of spawning a new one.
	# Previously "quiet" grants (ground pickups) routed to a big centered
	# Toaster card instead, which read louder than everything else, not quieter.
	if item_id > 0 and amount > 0:
		LootFeed.add_item(item_id, amount, item_name)
	inventory_changed.emit(data)


## Server-pushed loot chest open: gold to pouch, items staged for claim UI.
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
	# The reward readout is UniversalChestManager's job — it subscribes to this
	# same push and surfaces ChestRewardWindow. Deliberately NOT routed through
	# open_menu_requested any more: that lands in HUD.display_menu, which hides
	# every other menu, so opening a chest from the bag closed the inventory and
	# forced the Bank All -> Close -> reopen cycle.


## Reopen the claim UI if the player still has staged chest loot from a prior
## session that wasn't flushed (logout auto-banks, so this is mainly crash recovery).
func _restore_pending_chest_loot(_player: LocalPlayer) -> void:
	await get_tree().process_frame
	if InstanceClient.current == null:
		return
	var result: Array = await Client.request_data_await(
		&"chest.loot_get", {}, String(InstanceClient.current.name)
	)
	if result[1] != OK:
		return
	var payload: Dictionary = result[0] as Dictionary
	if not bool(payload.get("ok", false)):
		return
	var pending: Array = payload.get("pending", []) as Array
	if pending.is_empty():
		return
	Toaster.toast("You have unclaimed chest loot.")
	# Same window as every other reward, opened without disturbing whatever the
	# player already has on screen at login.
	UniversalChestManager.present(payload)


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
			"inventory_full":
				Toaster.toast("Your bag is full (%d/%d). Bank some items." % [
					Inventory.MAX_SLOTS, Inventory.MAX_SLOTS
				])
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

	# Keep the client skill mirror current even without a level-up (gates read it).
	var gather_level: int = int(data.get("level", 0))
	var gather_job: String = str(data.get("job", ""))
	if gather_level > 0 and not gather_job.is_empty():
		set_skill_level(StringName(gather_job), gather_level)
	var grants_for_mirror: Variant = data.get("grants", [])
	if grants_for_mirror is Array:
		for grant: Dictionary in grants_for_mirror:
			var prog: Dictionary = grant.get("progress", {})
			var g_level: int = int(prog.get("level", 0))
			var g_job: String = str(grant.get("job", ""))
			if g_level > 0 and not g_job.is_empty():
				set_skill_level(StringName(g_job), g_level)
				# Per grant, not per swing: a node crediting herb + medicine
				# pays two skills, and the tracker has to see both.
				_emit_skill_xp(
					StringName(g_job),
					int(grant.get("xp", 0)),
					int(prog.get("xp", 0)),
					g_level,
					bool(prog.get("leveled_up", false)),
				)

	# The yield rides the icon feed and the XP rides the radial tracker's floating
	# numbers ([XpTrackerHud]) — a gather card would only repeat both, which is
	# what put a "Mined ×5 / +62 Mining XP" panel in the middle of the screen on
	# every swing. Nothing is toasted here now except the level-up ceremony and
	# the perk point, which the tracker deliberately does not own.
	var job_slug: String = str(data.get("job", "mining"))
	var amount: int = int(data.get("amount", 0))
	if amount > 0:
		LootFeed.add_item(int(data.get("ore_id", 0)), amount, str(data.get("ore_name", "ore")))
	# Perk-gated byproduct (trees -> Headless Arrows). Its own feed row so the
	# player sees both items, not just the log.
	var byproduct_amount: int = int(data.get("byproduct_amount", 0))
	if byproduct_amount > 0:
		LootFeed.add_item(
			int(data.get("byproduct_id", 0)),
			byproduct_amount,
			str(data.get("byproduct_name", "")),
		)
	var grants_v: Variant = data.get("grants", [])
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
			set_skill_level(StringName(slug), new_lv)
			# celebrate_skill owns the wording — repeating it on the gather card
			# would stack the same sentence twice in the toast lane.
			LevelUpFx.celebrate_skill(local_player, StringName(slug), new_lv)
	if int(data.get("perk_points_gained", 0)) > 0:
		Toaster.toast("Perk point available. Spend in Mastery → Perks.")


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
	var mineable: MineableNode = node as MineableNode
	mineable.apply_visual_state(
		int(data.get("progress_hp", 0)),
		int(data.get("extraction_hp", 1)),
		int(data.get("charges_left", 0)),
		int(data.get("max_charges", 1)),
	)
	# Only a swing that actually connected earns a burst — a cooldown / wrong-tool
	# reply would otherwise spray particles at a player who did nothing.
	if data.get("ok", false):
		mineable.play_chop_effect()


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


## Local profession level for client-side gates. Missing skills read as 1.
func skill_level(skill_name: StringName) -> int:
	return int(skill_levels.get(String(skill_name), 1))


## Merge a skills.get-shaped dict ({slug: {level, ...}}) into the mirror.
func apply_skills_payload(skills: Variant) -> void:
	if not (skills is Dictionary):
		return
	var changed: bool = false
	for raw_name: Variant in (skills as Dictionary):
		var entry: Variant = (skills as Dictionary)[raw_name]
		if not (entry is Dictionary):
			continue
		var slug: String = String(raw_name)
		var level: int = int((entry as Dictionary).get("level", 1))
		if int(skill_levels.get(slug, -1)) != level:
			skill_levels[slug] = level
			changed = true
	if changed:
		skill_levels_changed.emit()


## Merge a flat {slug: level} dict (login skills.levels push).
func apply_skill_levels(levels: Variant) -> void:
	if not (levels is Dictionary):
		return
	var changed: bool = false
	for raw_name: Variant in (levels as Dictionary):
		var slug: String = String(raw_name)
		var level: int = int((levels as Dictionary)[raw_name])
		if int(skill_levels.get(slug, -1)) != level:
			skill_levels[slug] = level
			changed = true
	if changed:
		skill_levels_changed.emit()


## Local weapon-mastery level for client-side gates. Missing categories read as 1
## (masteries share the skills' 1–99 curve — never practiced is level 1, not 0).
func mastery_level(category: StringName) -> int:
	return maxi(1, int(mastery_levels.get(String(category), 1)))


## Merge a mastery.get-shaped dict ({category: {level, ...}}) into the mirror.
func apply_mastery_payload(masteries: Variant) -> void:
	if not (masteries is Dictionary):
		return
	var changed: bool = false
	for raw_name: Variant in (masteries as Dictionary):
		var entry: Variant = (masteries as Dictionary)[raw_name]
		if not (entry is Dictionary):
			continue
		var slug: String = String(raw_name)
		var level: int = maxi(1, int((entry as Dictionary).get("level", 1)))
		if int(mastery_levels.get(slug, -1)) != level:
			mastery_levels[slug] = level
			changed = true
	if changed:
		mastery_levels_changed.emit()


## Bump one mastery level after a kill reward (no-op if unchanged).
func set_mastery_level(category: StringName, level: int) -> void:
	var slug: String = String(category)
	if slug.is_empty() or level < 1:
		return
	if int(mastery_levels.get(slug, -1)) == level:
		return
	mastery_levels[slug] = level
	mastery_levels_changed.emit()


## Highest mastery level across every category the client knows about — the
## &"any" gate on universal endgame sets.
func best_mastery_level() -> int:
	var best: int = 1
	for slug: Variant in mastery_levels:
		best = maxi(best, int(mastery_levels[slug]))
	return best


## Bump one profession level after gather/craft (no-op if unchanged / lower).
func set_skill_level(skill_name: StringName, level: int) -> void:
	var slug: String = String(skill_name)
	if level < 1:
		return
	if int(skill_levels.get(slug, -1)) == level:
		return
	skill_levels[slug] = level
	skill_levels_changed.emit()


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
