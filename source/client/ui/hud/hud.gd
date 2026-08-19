class_name HUD
extends Control

const NAVIGATION_MINIMAP_SCRIPT: Script = preload(
	"res://source/client/ui/hud/navigation_minimap.gd"
)
const PLAYER_CONTEXT_MENU_SCRIPT: Script = preload(
	"res://source/client/ui/hud/player_context_menu.gd"
)
const HOSTILE_CONTEXT_MENU_SCRIPT: Script = preload(
	"res://source/client/ui/hud/hostile_context_menu.gd"
)
const SLAYER_TRACKER_SCRIPT: Script = preload(
	"res://source/client/ui/hud/slayer_tracker.gd"
)
## Submenus sit at z=100. Chat stays this high over the dungeon lobby so Enter
## can still compose a room code without closing the keeper UI.
const CHAT_ABOVE_MENU_Z: int = 110
const CHAT_DEFAULT_Z: int = 1

@export var sub_menu: Control

var notifications: Array[Dictionary]
var menus: Dictionary[StringName, Control]
var _xp_tween: Tween
var _navigation_minimap: Control
## Bumped on every player.died push so an in-flight respawn countdown can detect that a newer
## death event superseded it and bail (the newest invocation owns the death overlay).
var _death_gen: int = 0
## Gameplay nodes we hid because a menu opened — restored (only these) on close, so nodes with
## their own visibility gating (touch-only sticks, tracked-only quest tracker) that were already
## hidden don't get force-shown.
var _hidden_for_menu: Array[CanvasItem] = []
## Red unread count on the chat bubble. Created in `_ready` so the scene stays a
## static 40×40 button.
var _chat_unread_badge: PanelContainer
var _chat_unread_label: Label
var _party_hud: PartyHud

@onready var menu_overlay: Control = $MenuOverlay
@onready var notification_button: Button = $MenuButtons/ButtonRail/NotificationButton
@onready var menu_button: Button = $MenuButtons/ButtonRail/MenuButton
@onready var chat_button: Button = $MenuButtons/ButtonRail/ChatButton
@onready var chat: ChatMenu = $Chat
@onready var twin_sticks: Control = $TwinSticks
@onready var quest_tracker: QuestTracker = $QuestTracker
@onready var slayer_tracker: PanelContainer = $SlayerTracker
@onready var trade_panel: Control = $TradePanel
@onready var experience_bar: ProgressBar = $Resources/ExperienceBar
@onready var experience_level_label: Label = $Resources/ExperienceBar/LevelLabel
@onready var death_screen: ColorRect = $DeathScreen
@onready var death_label: Label = $DeathScreen/Label

## UI-sound: button text that gets the softer "back" cue instead of the click.
const BACK_BUTTON_LABELS: Array[String] = ["Close", "Back", "Cancel"]
## Menu open fade-in duration. Kept short + subtle on purpose (a soft arrival, not a flourish).
const MENU_FADE_S: float = 0.10

## Upper-right tracker rail. RIGHT_RAIL_TOP clears the navigation minimap
## (which ends at y=120 — see NavigationMinimap._ready); the width/margin match
## its lane so the whole rail reads as one column.
const RIGHT_RAIL_TOP: float = 128.0
const RIGHT_RAIL_GAP: float = 8.0
const RIGHT_RAIL_WIDTH: float = 224.0
const RIGHT_RAIL_MARGIN: float = 8.0

## Top-left inset for the compact Slayer badge — sits to the right of the chat bubble.
const SLAYER_BADGE_MARGIN: float = 6.0
const SLAYER_BESIDE_CHAT_LEFT: float = 58.0


func _ready() -> void:
	_navigation_minimap = NAVIGATION_MINIMAP_SCRIPT.new()
	add_child(_navigation_minimap)
	add_child(PLAYER_CONTEXT_MENU_SCRIPT.new())
	add_child(HOSTILE_CONTEXT_MENU_SCRIPT.new())
	# The minimap owns the upper-right navigation lane; the quest tracker sits
	# beneath it in the same rail (_place_right_rail owns the vertical order).
	# The Slayer tracker is a compact badge pinned to the top-LEFT corner instead,
	# well clear of the rail and the centre-right quickslot bar.
	for tracker: Control in [quest_tracker]:
		tracker.anchor_left = 1.0
		tracker.anchor_top = 0.0
		tracker.anchor_right = 1.0
		tracker.anchor_bottom = 0.0
		tracker.offset_left = -RIGHT_RAIL_WIDTH
		tracker.offset_right = -RIGHT_RAIL_MARGIN
	_place_slayer_tracker()
	quest_tracker.resized.connect(_place_right_rail)
	quest_tracker.visibility_changed.connect(_place_right_rail)
	call_deferred(&"_place_right_rail")

	_party_hud = PartyHud.new()
	add_child(_party_hud)

	notification_button.visible = false
	notification_button.disabled = true
	# Adopt the buttons' editor-assigned .tscn icons as crisp mounted glyphs (integer-scaled to fit,
	# whole-pixel centered) — visible in the scene, sharp at runtime.
	PixelIcon.from_button(menu_button)
	PixelIcon.from_button(notification_button)
	PixelIcon.from_button(chat_button)
	chat_button.visible = true
	chat_button.focus_mode = Control.FOCUS_NONE
	chat_button.clip_contents = false
	var button_rail: Control = chat_button.get_parent() as Control
	if button_rail != null:
		button_rail.clip_contents = false
		var rail_host: Control = button_rail.get_parent() as Control
		if rail_host != null:
			rail_host.clip_contents = false
	chat_button.pressed.connect(_on_chat_button_pressed)
	_chat_unread_badge = _make_chat_unread_badge()
	chat_button.add_child(_chat_unread_badge)
	_chat_unread_label = _chat_unread_badge.get_node("Count") as Label
	chat.unread_changed.connect(_on_chat_unread)
	Client.subscribe(&"notification", _on_notification_received)
	ClientState.player_profile_requested.connect(open_player_profile)
	ClientState.player_profile_by_peer_requested.connect(open_player_profile_by_peer)
	ClientState.open_menu_requested.connect(_on_menu_requested)
	# HUD chrome (compact docks z=5, button rail z=10, minimap z=80) is a sibling
	# of Submenu. Menus must sit above all of it so Withdraw / Close stay visible
	# and clickable — compact inventory used to paint over the bank footer.
	if sub_menu != null:
		sub_menu.z_index = 100
	# The launcher isn't a display_menu submenu, so hook its show/hide into the same HUD-hide path.
	menu_overlay.visibility_changed.connect(_refresh_hud_for_menus)
	# The trade panel is a standalone overlay (not a display_menu) — treat it like a menu too: hide
	# the gameplay HUD + freeze movement while it's open, so HUD clicks can't bleed through behind it.
	trade_panel.visibility_changed.connect(_refresh_hud_for_menus)

	ClientState.input_changed.connect(_on_input_type_changed)

	# Character level / xp bar. The bar chrome starts hidden and only flashes
	# on gains (see _flash_xp_bar); the level label stays visible throughout.
	experience_bar.self_modulate.a = 0.0
	Client.subscribe(&"combat.reward", _apply_progression)
	Client.subscribe(&"player.died", _on_player_died)
	# Fair-arena indicator: normalized spar matches carry sync_level > 0.
	Client.subscribe(&"sparring.match.state", _on_spar_sync_state)
	ClientState.local_player_ready.connect(func(_lp: LocalPlayer):
		_refresh_progression()
		_maybe_show_welcome())
	_refresh_progression()

	# Sparring countdown — big centered text fired each second by the server.
	Client.subscribe(&"sparring.countdown", _on_sparring_countdown)
	# /players opens a centered online roster panel (public command).
	Client.subscribe(&"players.list", _on_players_list)

	# Dungeon run HUD (live clock + revive pool) — self-contained; shows itself on dungeon.hud pushes.
	add_child(DungeonHud.new())
	# Boss Hunt HUD (contract countdown + kill tally) — same deal on boss_hunt.hud.
	add_child(BossHuntHud.new())

	# Dock icons must never take keyboard focus — Space is the attack bind, and Godot's default
	# Button FOCUS_ALL would let ui_accept / focused-button activation toggle inventory on Space.
	for dock_button: Node in $BottomMenuDock.get_children():
		if dock_button is BaseButton:
			(dock_button as BaseButton).focus_mode = Control.FOCUS_NONE

	# UI sound: wire every Button under the HUD to tap/hover cues (menus build theirs lazily, so also
	# watch node_added). The gateway has its own wiring; this is scoped to the in-game HUD subtree.
	_wire_subtree(self)
	get_tree().node_added.connect(_on_node_added)


## Fetch the current level/xp once (e.g. on spawn / map change). A fetch is a
## sync, not a gain — the bar stays hidden (no login/warp flash).
func _refresh_progression() -> void:
	if InstanceClient.current == null:
		return
	Client.request_data(&"progression.get", func(data: Dictionary) -> void:
		_apply_progression(data)
		_hide_xp_bar_now(),
		{}, InstanceClient.current.name)
	# Weapon-mastery mirror, hydrated on the same beat. Gear tooltips colour
	# their wear-gates from it (ItemTooltip), so it has to be populated before
	# the player opens a bag or a crafting station, not only after they visit
	# the Mastery tab.
	Client.request_data(&"mastery.get", func(data: Dictionary) -> void:
		ClientState.apply_mastery_payload(data.get("masteries", {})),
		{}, InstanceClient.current.name)


## First-run welcome modal, shown once via a client settings flag (so per install, not per character).
## Good enough for the alpha intro; the same guidance lives in the Help menu. Make it first-time-only with
## a server flag later if existing players should skip it.
func _maybe_show_welcome() -> void:
	if ClientState.settings.get_value(&"onboarding", &"seen_welcome"):
		# Welcome already seen; a web player may still have the one-time web notice pending.
		_maybe_show_web_notice()
		return
	ClientState.settings.set_value(&"onboarding", &"seen_welcome", true)
	var welcome: WelcomeScreen = WelcomeScreen.new()
	# Chain the web-only download notice so the two first-run modals never stack on screen.
	welcome.tree_exited.connect(_maybe_show_web_notice, CONNECT_DEFERRED)
	add_child(welcome)


## One-time "you're on the web build, grab the download" nudge. Web only, shown once via a
## client flag (per install, like the welcome modal). Edit the copy + URL in web_notice.gd.
func _maybe_show_web_notice() -> void:
	if not OS.has_feature("web"):
		return
	if ClientState.settings.get_value(&"onboarding", &"seen_web_notice"):
		return
	ClientState.settings.set_value(&"onboarding", &"seen_web_notice", true)
	add_child(WebNotice.new())


## Shows the death overlay with a per-second countdown until the server respawns us.
func _on_player_died(data: Dictionary) -> void:
	# Re-entrancy guard: claim a fresh generation. If a newer death push arrives while this
	# countdown is mid-flight, our captured gen goes stale and we bail without touching the
	# overlay, so the newest invocation owns the screen (no early hide / no double text write).
	_death_gen += 1
	var gen: int = _death_gen
	var seconds: int = int(ceil(float(data.get("respawn_in", 2.5))))
	var killed_by: String = str(data.get("killed_by", ""))
	var headline: String = "Slain by %s" % killed_by if not killed_by.is_empty() else "You died"
	death_screen.visible = true
	for remaining: int in range(seconds, 0, -1):
		death_label.text = "%s\nRespawning in %d..." % [headline, remaining]
		await get_tree().create_timer(1.0).timeout
		if not is_instance_valid(self):
			return
		if gen != _death_gen:
			return
	death_screen.visible = false


## Level the local player is currently SYNCED to by a normalized spar match
## (0 = none). Drives the "Lv 38 (sync 10)" level-label state.
var _spar_sync_level: int = 0
## Seconds the xp bar stays visible after a gain before fading back out.
const XP_BAR_LINGER_S: float = 3.0
## Fade tween for the bar chrome (owner call: xp is moment-of-gain info, not
## a 24/7 readout — the bar auto-shows on gain and hides again, like the
## overhead bars. self_modulate so the LevelLabel child stays visible).
var _xp_bar_fade: Tween


## Updates the xp bar + level label from progression.get or a combat.reward push.
func _apply_progression(data: Dictionary) -> void:
	if data.has("level"):
		# Mirror into ClientState so world nodes (gated portals) can read it without
		# poking at HUD labels.
		ClientState.player_level = int(data["level"])
		_refresh_level_label()
	if data.has("xp_to_next"):
		experience_bar.max_value = maxi(1, int(data["xp_to_next"]))
	if data.has("experience"):
		var new_xp: int = int(data["experience"])
		if _xp_tween != null and _xp_tween.is_valid():
			_xp_tween.kill()
		if new_xp >= experience_bar.value:
			# XP gained — fill up smoothly. A level-up wraps the value DOWN; snap that
			# (a draining bar reads backwards) so only forward gains animate.
			_xp_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_xp_tween.tween_property(experience_bar, ^"value", new_xp, 0.3)
		else:
			experience_bar.value = new_xp
		_flash_xp_bar()
	# The GAIN amount reads at the bar itself (its one home — moved off the kill
	# cards, docs/notifications.md): a small rising "+N XP" floaty, coalescing
	# across rapid kills.
	var gained: int = int(data.get("xp", 0))
	if gained > 0:
		_show_xp_gain(gained)


## Show the bar chrome, hold XP_BAR_LINGER_S, fade back out. Rapid gains keep
## resetting the hold (one sequential tween, killed on re-entry).
func _flash_xp_bar() -> void:
	if _xp_bar_fade != null and _xp_bar_fade.is_valid():
		_xp_bar_fade.kill()
	_xp_bar_fade = create_tween()
	_xp_bar_fade.tween_property(experience_bar, ^"self_modulate:a", 1.0, 0.15)
	_xp_bar_fade.tween_interval(XP_BAR_LINGER_S)
	_xp_bar_fade.tween_property(experience_bar, ^"self_modulate:a", 0.0, 0.4)


func _hide_xp_bar_now() -> void:
	if _xp_bar_fade != null and _xp_bar_fade.is_valid():
		_xp_bar_fade.kill()
	experience_bar.self_modulate.a = 0.0


## The live "+N XP" floaty above the bar (null when none). Rapid gains bump the
## SAME label's number instead of stacking floaties.
var _xp_floaty: Label
var _xp_floaty_amount: int


func _show_xp_gain(amount: int) -> void:
	if is_instance_valid(_xp_floaty):
		_xp_floaty_amount += amount
		_xp_floaty.text = "+%d XP" % _xp_floaty_amount
		return
	_xp_floaty_amount = amount
	var label: Label = Label.new()
	label.text = "+%d XP" % amount
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", 13)
	label.add_theme_color_override(&"font_color", Color(0.72, 0.88, 1.0))
	label.add_theme_color_override(&"font_outline_color", Color(0.05, 0.06, 0.1, 0.9))
	label.add_theme_constant_override(&"outline_size", 4)
	# Child of the BAR: escapes its self_modulate auto-hide (the LevelLabel
	# trick) and rides its position for free.
	experience_bar.add_child(label)
	label.position = Vector2(experience_bar.size.x * 0.5 - 22.0, -20.0)
	_xp_floaty = label
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, ^"position:y", label.position.y - 14.0, 0.9).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, ^"modulate:a", 0.0, 0.5).set_delay(0.5)
	tween.set_parallel(false)
	tween.tween_callback(label.queue_free)


## While a fair-arena match is live the level label reads "Lv 38 (sync 10)"
## in the section amber (owner reco) — players should never have to GUESS
## they're normalized. Restored the moment the match ends.
func _on_spar_sync_state(payload: Dictionary) -> void:
	_spar_sync_level = int(payload.get("sync_level", 0)) if bool(payload.get("in_match", false)) else 0
	_refresh_level_label()


func _refresh_level_label() -> void:
	if _spar_sync_level > 0:
		experience_level_label.text = "Lv %d (sync %d)" % [ClientState.player_level, _spar_sync_level]
		experience_level_label.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.5))
	else:
		experience_level_label.text = "Lv %d" % ClientState.player_level
		experience_level_label.remove_theme_color_override(&"font_color")


func _on_input_type_changed(input_type: InputComponent.InputType) -> void:
	twin_sticks.enabled = input_type == InputComponent.InputType.TOUCH


func _on_menu_requested(menu_name: StringName, arg: Variant) -> void:
	display_menu(menu_name, arg)


func _unhandled_input(event: InputEvent) -> void:
	# World map (M): toggle open/closed even while menus freeze LocalPlayer input.
	if event.is_action_pressed(&"player_map"):
		display_menu(&"world_map", null)
		get_viewport().set_input_as_handled()
		return
	# ESC closes every open interface (menus, launcher overlay, trade).
	if event.is_action_pressed(&"ui_cancel"):
		var closed: bool = false
		for menu: Control in menus.values():
			if menu.visible:
				menu.hide()
				closed = true
		if menu_overlay != null and menu_overlay.visible:
			menu_overlay.close()
			closed = true
		if trade_panel != null and trade_panel.visible:
			if trade_panel.has_method(&"close"):
				trade_panel.close()
			else:
				trade_panel.hide()
			closed = true
		if closed:
			get_viewport().set_input_as_handled()


func open_player_profile(player_id: int) -> void:
	display_menu(&"player_profile")
	menus[&"player_profile"].open_player_profile(player_id)


## Open a profile by the target's PEER id (a world click) — the server resolves it to
## the persistent player_id. Mirrors open_player_profile for the by-peer path.
func open_player_profile_by_peer(peer_id: int) -> void:
	display_menu(&"player_profile")
	menus[&"player_profile"].open_player_profile_by_peer(peer_id)


func _on_submenu_visiblity_changed(_menu: Control) -> void:
	_refresh_hud_for_menus()


## Gameplay HUD hides behind any open menu OR the launcher (both are semi-transparent, so the
## bars / sticks / chat bleeding through reads messy). We hide the individual gameplay nodes
## rather than the whole HUD, because the launcher is our OWN child (hiding self would hide it
## too); display_menu submenus live in the separate sub_menu container, so they're unaffected.
## Stacked menus are handled by _any_submenu_visible (the HUD stays hidden until ALL close).
func _refresh_hud_for_menus() -> void:
	var covered: bool = _any_submenu_visible() or (menu_overlay != null and menu_overlay.visible) or trade_panel.visible
	var keep_chat: bool = covered and _menu_allows_chat()
	if covered:
		# Capture-and-hide ONCE: only nodes currently visible, so we never force-show a node that
		# was hidden by its OWN logic (TwinSticks is touch-only; QuestTracker shows only while a
		# quest is tracked). Re-entrancy from stacked menus is a no-op (list already populated).
		if _hidden_for_menu.is_empty():
			var hud_nodes: Array[CanvasItem] = [
				$TwinSticks, $Chat, $QuestTracker, $SlayerTracker, $ItemSlots, $StatusBar, $AbilityBar, $Resources, $MenuButtons,
				$BottomMenuDock, $BossBar,
			]
			if _party_hud != null:
				hud_nodes.append(_party_hud)
			for node: CanvasItem in hud_nodes:
				if node != null and node.visible:
					if keep_chat and node == chat:
						continue
					node.hide()
					_hidden_for_menu.append(node)
		# Compact inventory / skills / etc. sit on the HUD and used to cover
		# bank Withdraw and other footer buttons. Hide them whenever a menu owns
		# the screen — not only during Secure Trade.
		_hide_compact_panels()
		if keep_chat:
			_raise_chat_over_menu()
		else:
			_restore_chat_layer()
			# Dungeon kept Chat out of the hide-list; if another overlay still
			# covers the HUD, tuck it away so it doesn't bleed through.
			if chat != null and chat.visible:
				chat.hide()
				if _hidden_for_menu.find(chat) < 0:
					_hidden_for_menu.append(chat)
		if trade_panel.visible:
			trade_panel.z_index = 20
			trade_panel.mouse_filter = Control.MOUSE_FILTER_STOP
			trade_panel.move_to_front()
	else:
		_restore_chat_layer()
		for node: CanvasItem in _hidden_for_menu:
			node.show()
		_hidden_for_menu.clear()
		# The quest tracker self-gates on tracked/active state, which may have changed while it was
		# menu-hidden (the player untracked it in the log) — re-derive instead of trusting the blind
		# show() above. Sync-set covers the common cases instantly; refresh() confirms vs live quests.
		quest_tracker.visible = ClientState.tracked_quest_id > 0 # > 0 = real pinned quest (0 = none, -1 = untracked)
		quest_tracker.refresh()
		if slayer_tracker.has_method(&"refresh"):
			slayer_tracker.call(&"refresh")
		_place_right_rail()


## Prayer state handler — pass through to the prayer bar (it subscribes independently,
## but we also handle it here for any HUD-level prayer state needs).
func _on_prayer_state(payload: Dictionary) -> void:
	# The prayer bar handles its own subscription, this is for any HUD-level needs
	pass


## Stack the upper-right rail top-down: minimap (fixed), then the quest tracker.
## A hidden panel leaves no gap and the tracker can't drift down into the
## quickslot bar.
func _place_right_rail() -> void:
	if quest_tracker == null:
		return
	var top: float = RIGHT_RAIL_TOP
	for tracker: Control in [quest_tracker]:
		if not tracker.visible:
			continue
		var panel_height: float = maxf(tracker.get_combined_minimum_size().y, 28.0)
		tracker.offset_top = top
		tracker.offset_bottom = top + panel_height
		top += panel_height + RIGHT_RAIL_GAP


## Pin the compact Slayer badge to the top-left corner. It sizes itself to its
## contents (shrink anchors), so no manual height bookkeeping is needed.
func _place_slayer_tracker() -> void:
	if slayer_tracker == null:
		return
	slayer_tracker.custom_minimum_size = Vector2.ZERO
	slayer_tracker.set_anchors_preset(Control.PRESET_TOP_LEFT)
	slayer_tracker.grow_horizontal = Control.GROW_DIRECTION_END
	slayer_tracker.grow_vertical = Control.GROW_DIRECTION_END
	slayer_tracker.offset_left = SLAYER_BESIDE_CHAT_LEFT
	slayer_tracker.offset_top = SLAYER_BADGE_MARGIN
	slayer_tracker.offset_right = SLAYER_BESIDE_CHAT_LEFT
	slayer_tracker.offset_bottom = SLAYER_BADGE_MARGIN


## Suppress player movement whenever a blocking menu is up. Polled each frame (NOT
## event-driven) so a menu-to-menu handoff (the NPC greeting closing as its Shop
## opens) can't leave a one-frame gap where movement slips through. Mobile is already
## covered (the HUD and its sticks hide above). This is the desktop-keyboard gate.
func _process(_delta: float) -> void:
	ClientState.menu_open = _any_submenu_visible() or trade_panel.visible


## True if any display_menu submenu is currently visible.
func _any_submenu_visible() -> bool:
	for menu: Control in menus.values():
		if menu.visible:
			return true
	return false


## Dungeon lobbies need live chat so a leader can paste the private room code
## without closing the keeper UI. Other fullscreen shells still hide it.
func _menu_allows_chat() -> bool:
	var dungeon: Control = menus.get(&"dungeon") as Control
	return dungeon != null and dungeon.visible


func _raise_chat_over_menu() -> void:
	if chat == null:
		return
	var hidden_at: int = _hidden_for_menu.find(chat)
	if hidden_at >= 0:
		_hidden_for_menu.remove_at(hidden_at)
	chat.show()
	chat.z_index = CHAT_ABOVE_MENU_Z
	chat.move_to_front()


func _restore_chat_layer() -> void:
	if chat != null:
		chat.z_index = CHAT_DEFAULT_Z


func display_menu(menu_name: StringName, arg: Variant = null) -> void:
	if not menus.has(menu_name):
		var path: String = "res://source/client/ui/menus/" + menu_name + "/" + menu_name + "_menu.tscn"
		if not ResourceLoader.exists(path):
			return
		var new_menu: Control = load(path).instantiate()
		new_menu.visibility_changed.connect(_on_submenu_visiblity_changed.bind(new_menu))
		sub_menu.add_child(new_menu)
		menus[menu_name] = new_menu
	# M / Map toggles closed when already open (same shortcut re-press).
	if menu_name == &"world_map" and menus[menu_name].visible:
		menus[menu_name].hide()
		return
	# Fullscreen shells (inventory, profile, shop, …) each dim the whole viewport.
	# Only one may be visible: stacking lets a later-opened menu cover another's Close
	# button with no Escape escape hatch on every panel. NPC→shop already closes the
	# dialogue first, so exclusive open keeps that handoff intact.
	for other_name: StringName in menus.keys():
		if other_name != menu_name and menus[other_name].visible:
			menus[other_name].hide()
	# Dock panels sit on the HUD (often above/beside the profile Close). Close them
	# so a world-click profile can't get trapped under the inventory dock.
	_hide_compact_panels()
	menus[menu_name].show()
	menus[menu_name].move_to_front()
	_animate_menu_open(menus[menu_name])
	if menus[menu_name].has_method(&"open") and (arg != null or menu_name == &"world_map"):
		menus[menu_name].open(arg)


func _on_overlay_menu_button_pressed() -> void:
	menu_overlay.open()


func _on_chat_button_pressed() -> void:
	if chat != null:
		chat.toggle_feed()


func _on_chat_unread(unread_count: int) -> void:
	if chat_button == null or _chat_unread_badge == null or _chat_unread_label == null:
		return
	var has_unread: bool = unread_count > 0
	chat_button.tooltip_text = (
		"Open chat  (Enter) — unread messages" if has_unread else "Open chat  (Enter to type)"
	)
	if not has_unread:
		_chat_unread_badge.hide()
		return
	_chat_unread_label.text = "99+" if unread_count > 99 else str(unread_count)
	_chat_unread_badge.show()
	_pin_chat_unread_badge()


func _make_chat_unread_badge() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "UnreadBadge"
	panel.visible = false
	panel.z_index = 20
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(14, 14)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.84, 0.16, 0.14)
	bg.set_corner_radius_all(8)
	bg.set_border_width_all(1)
	bg.border_color = Color(0.12, 0.04, 0.04, 0.9)
	bg.content_margin_left = 4
	bg.content_margin_right = 4
	bg.content_margin_top = 1
	bg.content_margin_bottom = 1
	panel.add_theme_stylebox_override(&"panel", bg)
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_END
	var count := Label.new()
	count.name = "Count"
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count.add_theme_font_size_override(&"font_size", 10)
	count.add_theme_color_override(&"font_color", Color.WHITE)
	panel.add_child(count)
	return panel


func _pin_chat_unread_badge() -> void:
	if _chat_unread_badge == null:
		return
	_chat_unread_badge.reset_size()
	var s: Vector2 = _chat_unread_badge.get_combined_minimum_size()
	s.x = maxf(s.x, 14.0)
	s.y = maxf(s.y, 14.0)
	# Hang off the top-right corner of the 40×40 bubble without covering the icon.
	_chat_unread_badge.offset_right = 5.0
	_chat_unread_badge.offset_top = -5.0
	_chat_unread_badge.offset_left = 5.0 - s.x
	_chat_unread_badge.offset_bottom = -5.0 + s.y


func _on_notification_button_pressed() -> void:
	# Weird safety case where notification button could be visible
	if notifications.is_empty():
		notification_button.visible = false
		notification_button.disabled = true
		return
	var notification_payload: Dictionary = notifications.pop_back()
	$NotificationPopup.pop_notification(notification_payload.get("topic", ""), notification_payload)
	if notifications.is_empty():
		notification_button.visible = false
		notification_button.disabled = true


func _on_notification_received(payload: Dictionary) -> void:
	notifications.append(payload)
	notification_button.visible = true
	notification_button.disabled = false
	# Arrival ping (docs/notifications.md open item, built 2026-07-20): the badge
	# persists until acted on, but alone it's easy to miss on a busy HUD — one
	# toast points at it the moment something arrives.
	match str(payload.get("topic", "")):
		"friend.request":
			Toaster.toast("Friend request from %s. Check your notifications." % str(payload.get("player_name", "someone")))
		"guild.invite":
			Toaster.toast("%s invited you to %s. Check your notifications." % [
				str(payload.get("from_name", "Someone")), str(payload.get("guild_name", "a guild"))
			])
		_:
			Toaster.toast("You have a new notification.")


## Big centered "3 / 2 / 1 / FIGHT!" pushed each second of the sparring countdown.
## Lazily creates the label so we don't carry the node when nobody spars.
##
## Smoothing: each tick is a hard text swap (no fade between digits — fading
## while the next digit arrives just looks twitchy). Only the final FIGHT!
## tick (seconds=0) fades out, and we kill any prior tween so it can't leak
## across into the next match.
var _countdown_tween: Tween

func _on_sparring_countdown(payload: Dictionary) -> void:
	var label: Label = get_node_or_null(^"SparringCountdown") as Label
	if label == null:
		label = Label.new()
		label.name = "SparringCountdown"
		label.anchor_left = 0.5
		label.anchor_top = 0.5
		label.anchor_right = 0.5
		label.anchor_bottom = 0.5
		label.offset_left = -120
		label.offset_top = -40
		label.offset_right = 120
		label.offset_bottom = 40
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override(&"font_size", 64)
		add_child(label)

	if _countdown_tween != null and _countdown_tween.is_valid():
		_countdown_tween.kill()
		_countdown_tween = null

	label.text = str(payload.get("text", ""))
	label.modulate.a = 1.0
	label.visible = true

	# Only the FIGHT! tick auto-fades. Intermediate digits stay solid until
	# the next push replaces them, which keeps the cadence crisp.
	if int(payload.get("seconds", 1)) > 0:
		return

	_countdown_tween = create_tween()
	_countdown_tween.tween_interval(0.6)
	_countdown_tween.tween_property(label, ^"modulate:a", 0.0, 0.4)
	_countdown_tween.tween_callback(func():
		label.visible = false
		label.modulate.a = 1.0
		_countdown_tween = null
	)


func _on_players_list(payload: Dictionary) -> void:
	display_menu(&"players", payload)


# --- UI sound + menu motion ------------------------------------------------

func _play_click() -> void:
	UISound.click()


func _play_back() -> void:
	UISound.back()


func _play_hover() -> void:
	UISound.hover()


## Give a button press + hover cues (idempotent). Close/Back/Cancel buttons get the softer back cue.
func _wire_button(button: Button) -> void:
	if not (button.pressed.is_connected(_play_click) or button.pressed.is_connected(_play_back)):
		var press: Callable = _play_back if button.text in BACK_BUTTON_LABELS else _play_click
		button.pressed.connect(press)
	if not button.mouse_entered.is_connected(_play_hover):
		button.mouse_entered.connect(_play_hover)


## Wire every Button currently under [root].
func _wire_subtree(root: Node) -> void:
	for b: Node in root.find_children("*", "Button", true, false):
		_wire_button(b as Button)


## Any Button added under the HUD later (lazily-built menus) gets wired automatically.
func _on_node_added(node: Node) -> void:
	if node is Button and is_ancestor_of(node):
		_wire_button(node as Button)


## Fade a just-shown menu in + play the reveal cue, so menus arrive with a little motion + sound
## instead of snapping on. Open only — close stays an instant hide for now.
func _animate_menu_open(menu: Control) -> void:
	UISound.reveal()
	menu.modulate.a = 0.0
	create_tween().tween_property(menu, ^"modulate:a", 1.0, MENU_FADE_S)


func _compact_panels() -> Array[Control]:
	return [
		$CompactMenuHost,
		$CompactEquipmentHost,
		$CompactSkillsHost,
		$CompactMasteryHost,
		$CompactQuestsHost,
		$CompactFriendsHost,
		$CompactSettingsHost,
	]


func _hide_compact_panels() -> void:
	for panel: Control in _compact_panels():
		panel.hide()


func _toggle_compact_panel(selected_panel: Control) -> void:
	# Fullscreen menus (bank, shop, trade, …) own the screen. Opening a dock over
	# them covers footer buttons and used to close the menu — ignore the dock.
	if trade_panel.visible or _any_submenu_visible():
		return
	var should_open: bool = not selected_panel.visible
	_hide_compact_panels()
	selected_panel.visible = should_open


func _on_inventory_dock_button_pressed() -> void:
	_toggle_compact_panel($CompactMenuHost)


func _on_equipment_dock_button_pressed() -> void:
	_toggle_compact_panel($CompactEquipmentHost)


func _on_skills_dock_button_pressed() -> void:
	_toggle_compact_panel($CompactSkillsHost)


func _on_mastery_dock_button_pressed() -> void:
	_toggle_compact_panel($CompactMasteryHost)


func _on_quests_dock_button_pressed() -> void:
	_toggle_compact_panel($CompactQuestsHost)


func _on_friends_dock_button_pressed() -> void:
	_toggle_compact_panel($CompactFriendsHost)


func _on_settings_dock_button_pressed() -> void:
	_toggle_compact_panel($CompactSettingsHost)
