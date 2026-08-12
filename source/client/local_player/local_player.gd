class_name LocalPlayer
extends Player

## Toast tint for the SAFE <-> PvP zone-crossing notice — red warns of danger,
## green signals protection. Defined locally because ZonePatch2D (which owns the
## canonical zone colors) is an @tool node that's stripped from client exports.
const PVP_TOAST_COLOR: Color = Color(1.0, 0.5, 0.45)
const SAFE_TOAST_COLOR: Color = Color(0.55, 0.95, 0.6)

## Godot Camera2D's default (effectively unbounded) limit magnitude — restored on maps
## that define no camera_limits so a previous map's bounds don't linger.
const CAMERA_LIMIT_MIN: int = -10000000
const CAMERA_LIMIT_MAX: int = 10000000

## Upstream send rate cap. The server rebroadcasts entity state at 20 Hz, so sending
## faster (client physics runs at 60) just triples server ingest for updates nobody
## ever sees. Dirty-marking still happens every physics frame — the dirty map
## coalesces — only the actual send is gated (docs/netcode_smoothness.md, Phase 2).
const NET_SEND_INTERVAL_S: float = 1.0 / 20.0
const CLICK_NAVIGATION_SCRIPT: Script = preload(
	"res://source/client/local_player/click_navigation.gd"
)
const CLICK_MOVE_MARKER_SCRIPT: Script = preload(
	"res://source/client/local_player/click_move_marker.gd"
)
const HARVEST_CONTROLLER_SCRIPT: Script = preload(
	"res://source/client/local_player/harvest_controller.gd"
)
const PICKUP_CONTROLLER_SCRIPT: Script = preload(
	"res://source/client/local_player/pickup_controller.gd"
)
const COMBAT_TARGET_CONTROLLER_SCRIPT: Script = preload(
	"res://source/client/local_player/combat_target_controller.gd"
)
const INTERACT_CONTROLLER_SCRIPT: Script = preload(
	"res://source/client/local_player/interact_controller.gd"
)
const CRAFT_CONTROLLER_SCRIPT: Script = preload(
	"res://source/client/local_player/craft_controller.gd"
)
const FOLLOW_REPATH_MS: int = 300
const FOLLOW_STOP_DISTANCE: float = 28.0
## Auto-retaliate ignores hits after this much idle time (no move/attack/ability).
const AFK_RETALIATE_MS: int = 5 * 60 * 1000


## Fallback move speed until the synced MOVE_SPEED stat arrives. Actual movement
## reads the stat (see process_movement) so AGILITY / gear speed bonuses apply.
var speed: float = 112.5
var hand_pivot_speed: float = 17.5

var input_direction: Vector2 = Vector2.ZERO
var look_direction: Vector2 = Vector2.ZERO
var action_input: bool = false

## While dead, input/movement are locked so the player can't act or drift; the respawn
## teleport is applied locally (position is client-authoritative).
var _dead: bool = false
var _respawn_position: Vector2

## Last-seen PvP state, so the zone-crossing toast fires only on the SAFE<->PVP
## edge. zone_flags is server-authoritative (synced via correction); we just
## watch the value flip rather than adding another network message.
var _was_pvp: bool = false

var fid_position: int
var fid_flipped: int
var fid_anim: int
var fid_pivot: int

## Accumulator gating upstream sends to NET_SEND_INTERVAL_S.
var _net_send_accum: float = 0.0

var synchronizer_manager: StateSynchronizerManagerClient
var _click_navigation: ClickNavigation
var _click_move_marker: ClickMoveMarker
var _harvest_controller: HarvestController
var _pickup_controller: PickupController
var _combat_target_controller: CombatTargetController
var _interact_controller: InteractController
var _craft_controller: CraftController
var _follow_peer_id: int = 0
var _follow_repath_at_ms: int = 0
## Last ticks_msec the local player provided intentional input (movement, attack,
## abilities, interact, click-nav). Used to disable auto-retaliate while AFK.
var _last_input_ms: int = 0

@onready var camera_2d: Camera2D = $Camera2D
@onready var controller: InputComponent = $InputComponent


func _ready() -> void:
	ClientState.local_player = self
	_click_navigation = CLICK_NAVIGATION_SCRIPT.new()
	add_child(_click_navigation)
	_click_navigation.setup(self)
	_click_move_marker = CLICK_MOVE_MARKER_SCRIPT.new()
	add_child(_click_move_marker)
	_harvest_controller = HARVEST_CONTROLLER_SCRIPT.new()
	add_child(_harvest_controller)
	_harvest_controller.setup(self)
	_pickup_controller = PICKUP_CONTROLLER_SCRIPT.new()
	add_child(_pickup_controller)
	_pickup_controller.setup(self)
	_combat_target_controller = COMBAT_TARGET_CONTROLLER_SCRIPT.new()
	add_child(_combat_target_controller)
	_combat_target_controller.setup(self)
	_interact_controller = INTERACT_CONTROLLER_SCRIPT.new()
	add_child(_interact_controller)
	_interact_controller.setup(self)
	_craft_controller = CRAFT_CONTROLLER_SCRIPT.new()
	add_child(_craft_controller)
	_craft_controller.setup(self)
	_last_input_ms = Time.get_ticks_msec()
	ClientState.local_player_ready.emit(self)
	
	super._ready()

	# Seed the zone-crossing baseline so we don't toast for the spawn state.
	_was_pvp = is_pvp()

	fid_position = PathRegistry.id_of(":position")
	fid_flipped = PathRegistry.id_of(":flipped")
	fid_anim = PathRegistry.id_of(":anim")
	fid_pivot = PathRegistry.id_of(":pivot")
	
	_apply_settings()
	ClientState.settings.setting_changed.connect(_on_settings_changed)
	# Clamp the camera to each map's authored bounds (no black borders past the edge). The
	# local player persists across maps (InstanceClient reuses it), so re-apply on every
	# instance change — plus once now for the map we spawned into.
	Client.instance_manager.instance_changed.connect(_on_instance_changed_camera_limits)
	if InstanceClient.current != null:
		_apply_camera_limits(InstanceClient.current.instance_map)
	Client.subscribe(&"player.died", _on_player_died)
	# Sparring: explicit teleport push at match start (to spawn) and end (back
	# to the duel master). State-sync deltas alone can't move the LocalPlayer
	# because process_movement overwrites with current input each frame; we
	# need to actually set the position here AND freeze input briefly so the
	# player doesn't run off the spot they were teleported to.
	Client.subscribe(&"sparring.match.state", _on_sparring_match_state)
	# Staff teleports (/goto, /summon) within the same map: same problem as the
	# sparring teleport — we must set position locally + freeze input briefly.
	Client.subscribe(&"player.teleport", _on_teleport)
	# STUNNED (Pinning Arrow): the server locks our input for the duration — movement
	# is client-authoritative, so the freeze must happen here. The movement lock also
	# swallows attacks, and the server refuses our actions regardless.
	Client.subscribe(&"player.stunned", func(payload: Dictionary) -> void:
		freeze_movement(float(payload.get("ms", 1000)) / 1000.0))
	# Channeling (healing aura, future recall): when OUR channel starts we root in
	# place; pressing a move key cancels it. Other players' channels only show
	# their aura (handled in InstanceClient) — these handlers ignore them.
	Client.subscribe(&"channel.start", _on_channel_start)
	Client.subscribe(&"channel.end", _on_channel_end)
	# Weapon equip-cast: a short draw where abilities are locked (movement + aim
	# stay free) and a cast bar shows over our head. Server pushes start + done.
	Client.subscribe(&"equip.cast", _on_equip_cast)
	Client.subscribe(&"equip.done", _on_equip_done)
	# Co-op group roster (dungeons): mirror our groupmate peer ids so their health
	# bars tint as allies. Same pattern as the sparring team push.
	Client.subscribe(&"group.roster", _on_group_roster)
	# Dungeon cleared (final room down) — show the recap; the server returns the
	# party to town after a short timer (the recap auto-closes with it).
	Client.subscribe(&"dungeon.cleared", func(payload: Dictionary) -> void:
		ClientState.open_menu_requested.emit(&"dungeon_recap", payload))
	# Dungeon FAILED (hardcore wipe — revive pool spent): same recap menu, "failed" variant.
	Client.subscribe(&"dungeon.failed", func(payload: Dictionary) -> void:
		ClientState.open_menu_requested.emit(&"dungeon_recap", payload))
	# Dungeon entered — a center-screen banner so the run opens with weight.
	Client.subscribe(&"dungeon.entered", func(payload: Dictionary) -> void:
		Announcer.announce(
			str(payload.get("dungeon", "The dungeon")),
			"Clear each room. Defeat the boss to escape.",
			{"delay": 0.6}))
	# Boss enrage (dungeon phase 2): a red center banner + camera shake so the
	# escalation reads — see BossController._announce_enrage.
	Client.subscribe(&"boss.enrage", func(payload: Dictionary) -> void:
		Announcer.announce("%s enrages!" % str(payload.get("name", "The boss")), "", {"color": PVP_TOAST_COLOR})
		shake_camera(0.6))
	# Boss mechanic callout — a named warning as the wind-up starts, so a move
	# with counterplay (Killing Frost's safe circle) can be LEARNED the first
	# time instead of just killing people. No shake: it must not read as damage.
	Client.subscribe(&"boss.callout", func(payload: Dictionary) -> void:
		Announcer.announce(str(payload.get("text", "")), "", {"color": PVP_TOAST_COLOR}))


## The local player's own over-head HP bar reads as "self" (green), never
## ally/neutral. (Overrides Player so the local-player check stays out of Player —
## see the cycle note there.)
func _apply_team_bar_color() -> void:
	set_health_bar_fill(BAR_COLOR_SELF)
	refresh_nameplate_color()


## Self nameplate is light cyan (not friend-green / player-white).
func refresh_nameplate_color() -> void:
	set_nameplate_color(NAME_COLOR_SELF)


## Lock control while dead, then teleport ourselves to the spawn point (the server owns
## HP + the dead flag; position is ours to set). Deaths with return_home
## (Guild Hall recall) skip the local snap — the server switches instance after the delay.
func _on_player_died(data: Dictionary) -> void:
	_dead = true
	_respawn_position = data.get("spawn", global_position)
	var return_home: bool = bool(data.get("return_home", false))
	await get_tree().create_timer(float(data.get("respawn_in", 3.0))).timeout
	if not is_instance_valid(self):
		return
	_dead = false
	if return_home:
		return
	global_position = _respawn_position


## Server-driven teleport for the start/end of a sparring match. Pushes carry
## the new position; we apply it and freeze input briefly so the player
## doesn't immediately walk off the spot.
var _movement_lock_until_ms: int = 0

func _on_sparring_match_state(payload: Dictionary) -> void:
	var pos: Variant = payload.get("position", null)
	if pos is Vector2 and pos != Vector2.ZERO:
		global_position = pos
		# Match START freezes for the whole countdown (3/2/1 must actually hold you on your spawn
		# until FIGHT!); match END just settles you on the teleport back (500ms default).
		_movement_lock_until_ms = Time.get_ticks_msec() + int(payload.get("countdown_ms", 500))
	# Spar-team tinting: remember allies/opponents for the match (cleared on end)
	# and re-tint everyone in the map so health bars flip immediately.
	if bool(payload.get("in_match", false)):
		Character.spar_ally_peers = payload.get("allies", [])
		Character.spar_opponent_peers = payload.get("opponents", [])
	else:
		Character.spar_ally_peers = []
		Character.spar_opponent_peers = []
	var map: Node = get_parent()
	if map != null:
		for child: Node in map.get_children():
			if child.has_method(&"_apply_team_bar_color"):
				child.call(&"_apply_team_bar_color")


## Co-op group roster push — set our groupmate peer ids and re-tint everyone in
## the map so their health bars flip to ally immediately (same as spar teams).
func _on_group_roster(payload: Dictionary) -> void:
	Character.group_peers = payload.get("members", [])
	var map: Node = get_parent()
	if map != null:
		for child: Node in map.get_children():
			if child.has_method(&"_apply_team_bar_color"):
				child.call(&"_apply_team_bar_color")


## Generic server-driven teleport (staff /goto, /summon within the same map).
func _on_teleport(payload: Dictionary) -> void:
	var pos: Variant = payload.get("position", null)
	if pos is Vector2:
		global_position = pos
		_movement_lock_until_ms = Time.get_ticks_msec() + 500


# --- Channeling (healing aura, future recall) ---
## True while WE are mid-channel: rooted, actions suppressed, a move key cancels.
## Deliberately NOT the movement lock — that zeroes input, which would make the
## move-to-cancel impossible to detect.
var _channeling: bool = false
## Safety net so a dropped channel.end can't strand us rooted forever.
var _channel_until_ms: int = 0
## A MOBILE channel (a spin) lets us keep moving — slowed to _channel_speed_mult —
## instead of rooting + cancelling on a move key. Set from the channel.start push.
var _channel_mobile: bool = false
var _channel_speed_mult: float = 0.5
## Grace at the START of a rooted channel during which a held move key does NOT cancel
## it — you're rooted in place (so you visibly stop and the aura explains itself), with
## time to release the keys. Without it, activating WHILE running cancels instantly and
## reads as "the button did nothing". Cancel resumes after the grace if you're still
## moving.
const CHANNEL_MOVE_GRACE_MS: int = 850
var _channel_grace_until_ms: int = 0
## Name of the ability WE'RE channeling (empty = none). The ability bar reads
## this off the local player — the HUD lives outside the instance's multiplayer
## context, so it can't identify "us" via get_unique_id; LocalPlayer can.
var channeling_ability_name: String = ""


func _on_channel_start(payload: Dictionary) -> void:
	if int(payload.get("p", -1)) != multiplayer.get_unique_id():
		return # someone else's channel — InstanceClient draws their aura, we don't root
	_channeling = true
	channeling_ability_name = String(payload.get("an", ""))
	_channel_mobile = bool(payload.get("mob", false))
	_channel_speed_mult = float(payload.get("msm", 0.5))
	_channel_grace_until_ms = Time.get_ticks_msec() + CHANNEL_MOVE_GRACE_MS
	_channel_until_ms = Time.get_ticks_msec() + int(float(payload.get("d", 6.0)) * 1000.0) + 750


func _on_channel_end(payload: Dictionary) -> void:
	if int(payload.get("p", -1)) != multiplayer.get_unique_id():
		return
	_channeling = false
	_channel_mobile = false
	channeling_ability_name = ""


## Ask the server to start the universal Recall channel. Shared entry for the B key
## AND the HUD rail button (mobile has no keyboard). No-op while already channeling
## (cancel by moving) or outside an instance.
func request_recall() -> void:
	if _channeling or InstanceClient.current == null:
		return
	Client.request_data(&"recall.start", Callable(), {}, InstanceClient.current.name)


## Area-loot (F): ask the server to pick up every reserved/free pile in range.
func request_area_loot() -> void:
	if InstanceClient.current == null:
		return
	Client.request_data(&"item.pickup_area", func(result: Dictionary) -> void:
		var count: int = int(result.get("picked", 0))
		if count <= 0:
			var reason: String = str(result.get("reason", ""))
			if reason == "none" or reason.is_empty():
				Toaster.toast("Nothing to loot nearby.")
			return
		var names: PackedStringArray = PackedStringArray(result.get("names", []))
		if names.is_empty():
			Toaster.toast("Looted %d pile%s." % [count, "s" if count != 1 else ""])
		else:
			Toaster.toast("Looted: %s" % ", ".join(names))
	, {}, InstanceClient.current.name)


## Tell the server to stop our channel (it pushes channel.end back, which also
## clears the flag — calling this just unroots us a frame early, locally).
func _cancel_channel() -> void:
	_channeling = false
	channeling_ability_name = ""
	if InstanceClient.current != null:
		Client.request_data(&"channel.cancel", Callable(), {}, InstanceClient.current.name)


## Locally roots movement for [param seconds] — heavy attacks plant you while
## you swing (commitment + readability). Reuses the same movement lock, so it
## also blocks re-attacking for that window; fine because the weapons that use
## it have long cooldowns. Called client-side from the weapon on the wielder.
func freeze_movement(seconds: float) -> void:
	if seconds <= 0.0:
		return
	_movement_lock_until_ms = maxi(_movement_lock_until_ms, Time.get_ticks_msec() + int(seconds * 1000.0))


## True while a primary attack is available — a real weapon, or bare-hands punch.
## A held potion / material with no primary attack still reads as UNARMED. The world
## click-to-inspect gate uses this: you only open a player's profile while holstered,
## so a click in a fight is always a swing/shot, never a profile.
## Gathering tools (pickaxe / axe / fishing rod / sickle) are NOT armed for combat —
## they only swing via HarvestController when you click a resource node.
func is_armed() -> bool:
	if is_holding_gather_tool():
		return false
	var weapon: Weapon = equipment_component.mounted_nodes.get(&"weapon", null) as Weapon
	return weapon != null and not weapon.abilities.is_empty() and weapon.abilities[0] != null


## True when the weapon slot holds a ToolItem (pickaxe, axe, fishing rod, sickle).
## Spacebar / free-aim must not attack while a tool is equipped — gathering is a
## separate click-to-harvest action.
func is_holding_gather_tool() -> bool:
	var item: Item = equipment_component.equipped_items.get(&"weapon", null)
	return item is ToolItem


# --- Weapon equip-cast (client) ---
## True while drawing a weapon: abilities are locked (process_input + the touch
## ability bar both read this), but movement + aim stay free. Set from equip.cast,
## cleared on equip.done — or a safety timeout if that push is lost.
var _equip_drawing: bool = false
var _equip_draw_until_ms: int = 0
var _equip_draw_token: int = 0
var _equip_bar: ChannelVisual = null


func _on_equip_cast(payload: Dictionary) -> void:
	var ms: int = int(payload.get("ms", 500)) # fallback; the server always sends ms (= Player.WEAPON_DRAW_MS)
	_equip_drawing = true
	_equip_draw_until_ms = Time.get_ticks_msec() + ms
	_equip_draw_token += 1
	var token: int = _equip_draw_token
	_show_equip_bar(float(ms) / 1000.0)
	# Safety: clear if the equip.done push is lost, so we can't get stuck locked.
	await get_tree().create_timer(float(ms) / 1000.0 + 0.6).timeout
	if _equip_draw_token == token:
		_clear_equip_draw()


func _on_equip_done(_payload: Dictionary) -> void:
	_equip_draw_token += 1 # invalidate the pending safety timeout
	_clear_equip_draw()


func _clear_equip_draw() -> void:
	_equip_drawing = false
	if is_instance_valid(_equip_bar):
		_equip_bar.queue_free()
	_equip_bar = null


func _show_equip_bar(duration: float) -> void:
	if is_instance_valid(_equip_bar):
		_equip_bar.queue_free()
	var bar: ChannelVisual = ChannelVisual.new()
	bar.name = "EquipCastVisual"
	bar.kind = &"equip"
	bar.duration = maxf(0.1, duration)
	add_child(bar)
	_equip_bar = bar


## True while mid weapon-draw / drink-cast — abilities are locked (process_input +
## the touch ability bar read this). A weapon draw stays move-free; a drink also
## roots via the movement lock.
func is_equip_drawing() -> bool:
	return _equip_drawing and Time.get_ticks_msec() < _equip_draw_until_ms


# --- Camera shake (combat juice) ---
## Current trauma (0..1). Shake offset is trauma², so it eases out smoothly and
## a big hit doesn't snap to a hard stop. Decays a bit each frame.
var _trauma: float = 0.0
const SHAKE_DECAY: float = 3.5      ## trauma per second bled off
const SHAKE_MAX_OFFSET: float = 9.0 ## pixels at full trauma

## Adds a kick of camera shake (additive, clamped). Call from a weapon's own
## visual when its hit lands — e.g. the hammer slam. [param amount] ~0.3 light,
## ~0.6 heavy.
func shake_camera(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func _process(delta: float) -> void:
	if _trauma <= 0.0:
		return
	_trauma = maxf(0.0, _trauma - SHAKE_DECAY * delta)
	var shake: float = _trauma * _trauma * SHAKE_MAX_OFFSET
	camera_2d.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake


func _physics_process(delta: float) -> void:
	process_input()
	process_movement()
	process_animation(delta)
	process_synchronization()
	_notify_zone_transition()


## Toast when we cross the SAFE <-> PvP boundary. zone_flags is synced from the
## server (StateSynchronizerManagerServer.update_zone_flags_for_entity), so the
## bit simply flips under us as we move — we watch it rather than adding a
## dedicated push. Local-player only: remote players never run this.
func _notify_zone_transition() -> void:
	var now_pvp: bool = is_pvp()
	if now_pvp == _was_pvp:
		return
	_was_pvp = now_pvp
	if now_pvp:
		Toaster.toast("Entered a PvP zone. Other players can attack you here.", 3.0, PVP_TOAST_COLOR)
	else:
		Toaster.toast("Back in a safe zone. You're protected from other players.", 3.0, SAFE_TOAST_COLOR)


func process_movement() -> void:
	# A ROOTED channel (heal aura) freezes you; a MOBILE channel (spin) lets you
	# walk, slowed (handled below). Death / menu / movement-lock always freeze.
	if _dead or ClientState.menu_open or Time.get_ticks_msec() < _movement_lock_until_ms \
			or (_channeling and not _channel_mobile):
		velocity = Vector2.ZERO
		return
	# Read the server-synced MOVE_SPEED stat so AGILITY (and speed gear) actually
	# move you faster. Fall back to `speed` until the first stat sync lands so the
	# player isn't frozen on spawn.
	var move_speed: float = stats_component.get_stat(Stat.MOVE_SPEED)
	if move_speed <= 0.0:
		move_speed = speed
	if _channeling and _channel_mobile:
		move_speed *= _channel_speed_mult  # spinning slows you
	velocity = input_direction * move_speed
	move_and_slide()


func process_input() -> void:
	# Movement lock (drink / hammer slam root) freezes WASD but must NOT cancel
	# Right-click → Attack — otherwise heavy weapons abort after one hit.
	var rooted: bool = Time.get_ticks_msec() < _movement_lock_until_ms
	if _dead or _has_gui_focus() or ClientState.menu_open:
		_click_navigation.cancel()
		if _harvest_controller != null:
			_harvest_controller.cancel()
		if _pickup_controller != null:
			_pickup_controller.cancel()
		if _combat_target_controller != null:
			_combat_target_controller.cancel()
		if _interact_controller != null:
			_interact_controller.cancel()
		input_direction = Vector2.ZERO
		action_input = false
		return
	if rooted:
		_click_navigation.cancel()
		if _harvest_controller != null:
			_harvest_controller.cancel()
		if _pickup_controller != null:
			_pickup_controller.cancel()
		if _interact_controller != null:
			_interact_controller.cancel()
		input_direction = Vector2.ZERO
		if _combat_target_controller != null and _combat_target_controller.tick():
			action_input = false
			return
		look_direction = controller.get_look_direction()
		action_input = false
		return

	var manual_direction: Vector2 = controller.get_move_direction()
	if manual_direction != Vector2.ZERO:
		_note_input_activity()
		_follow_peer_id = 0
		_click_navigation.cancel()
		if _harvest_controller != null:
			_harvest_controller.cancel()
		if _pickup_controller != null:
			_pickup_controller.cancel()
		if _combat_target_controller != null:
			_combat_target_controller.cancel()
		if _interact_controller != null:
			_interact_controller.cancel()
		input_direction = manual_direction
	else:
		_update_follow_navigation()
		input_direction = _click_navigation.movement_direction()
	look_direction = controller.get_look_direction()
	action_input = controller.is_attack_pressed()
	if action_input:
		_note_input_activity()

	# Mid weapon-draw / drink-cast: abilities are locked (the server gates too). A
	# weapon draw stays move-free; a drink roots via the movement lock above.
	if is_equip_drawing():
		action_input = false
		return

	# Recall (B): a universal channel anyone can start — ask the server to begin
	# it. Not while already channeling (re-press is ignored; cancel by moving).
	if Input.is_action_just_pressed(&"player_recall"):
		_note_input_activity()
		request_recall()

	# Area loot (F / player_interact): vacuum every pile reserved to us (or free)
	# within pickup range.
	if Input.is_action_just_pressed(&"player_interact"):
		_note_input_activity()
		request_area_loot()

	if Input.is_action_just_pressed(&"player_special") \
			or Input.is_action_just_pressed(&"player_special_2"):
		_note_input_activity()

	# Channeling: rooted (process_movement zeroes velocity). A move key CANCELS
	# the channel and frees us from this frame on; otherwise suppress all actions
	# so an attack can't interrupt it. Safety-clear if the end push was lost.
	if _channeling:
		if Time.get_ticks_msec() > _channel_until_ms:
			_channeling = false
			channeling_ability_name = ""
		elif not _channel_mobile:
			# Rooted channel: a move key CANCELS — but only after the start grace, so
			# activating while running roots you (you stop + see the aura) and gives you
			# a beat to release the keys instead of cancelling on the held input.
			if input_direction != Vector2.ZERO and Time.get_ticks_msec() >= _channel_grace_until_ms:
				_cancel_channel()
			else:
				action_input = false
				return
		else:
			# Mobile channel (spin/lash): walk freely (slowed), but NO abilities mid-channel.
			# Re-tap a special to bail early — mobile channels don't cancel on move the way
			# rooted ones do. The start grace stops the launching press from self-cancelling.
			if Time.get_ticks_msec() >= _channel_grace_until_ms and (
					Input.is_action_just_pressed(&"player_special")
					or Input.is_action_just_pressed(&"player_special_2")):
				_cancel_channel()
			action_input = false
			return

	# Attack beats an auto-gather / auto-loot loop. Both of those tick with an early
	# return below, so without this an ambush mid-harvest left Spacebar dead — the
	# acquire block never ran and the player couldn't fight back until they broke the
	# gather by walking. Cancel here so the same press falls through and locks on.
	if controller.is_attack_just_pressed() and is_armed():
		if _harvest_controller != null and _harvest_controller.is_active():
			_harvest_controller.cancel()
		if _pickup_controller != null and _pickup_controller.is_active():
			_pickup_controller.cancel()
		if _interact_controller != null and _interact_controller.is_active():
			_interact_controller.cancel()

	# Click-to-gather overrides hold-to-attack while a vein is locked.
	if _harvest_controller != null and _harvest_controller.is_active():
		if _harvest_controller.tick():
			equipment_component.process_input(self)
			return

	# Click-to-loot: walk into range then request item.pickup.
	if _pickup_controller != null and _pickup_controller.is_active():
		if _pickup_controller.tick():
			return

	# Click-to-talk / use station: walk into range then open the interaction.
	if _interact_controller != null and _interact_controller.is_active():
		if _interact_controller.tick():
			return

	# A lock whose target just died must be dropped HERE, not inside tick() — the
	# is_active() guard below skips tick() entirely once the target reads as dead,
	# so the stale lock would survive the kill and silently re-engage the same NPC
	# the moment it respawned into the same node.
	if _combat_target_controller != null:
		_combat_target_controller.release_if_target_dead()

	# Spacebar: lock onto a hostile (remembered fight target after WASD / click
	# move, else nearest). Persists like Right-click → Attack until cancelled.
	if (
		_combat_target_controller != null
		and controller.is_attack_just_pressed()
		and is_armed()
		and not _combat_target_controller.is_active()
	):
		var space_target: HostileNpc = _combat_target_controller.acquire_for_spacebar()
		if space_target != null:
			_begin_hostile_attack(space_target)

	# Locked Attack: walk into range and keep swinging.
	if _combat_target_controller != null and _combat_target_controller.is_active():
		if _combat_target_controller.tick():
			equipment_component.process_input(self)
			return

	equipment_component.process_input(self)
	# Free-aim hold-fire only when no hostile lock is active — and never while a
	# gathering tool is equipped (tools only swing via HarvestController).
	if (
		action_input
		and not is_holding_gather_tool()
		and equipment_component.can_use(&"weapon", 0)
	):
		Client.request_data(&"action.perform", Callable(),
		{"d": look_direction, "i": 0}, InstanceClient.current.name)


func process_animation(delta: float) -> void:
	if _dead:
		# Play (and hold) the death pose instead of input-driven locomotion. Synced to
		# other clients via the :anim field like any other animation.
		if anim != Animations.DEATH:
			anim = Animations.DEATH
		return
	flipped = look_direction.x < 0
	update_hand_pivot(delta)
	anim = Animations.RUN if input_direction else Animations.IDLE


func update_hand_pivot(delta: float) -> void:
	# Channeling plants you in a fixed stance — the weapon holds its angle rather
	# than swivelling to the cursor (a planted hammer that still tracked aim would
	# look wrong). The pose itself is the weapon's set_channeling_pose.
	if _channeling and not _channel_mobile:
		return  # rooted channels plant the weapon; a spin keeps tracking aim
	var to_flip: int = -1 if flipped else 1
	var look_angle: float = atan2(look_direction.y, look_direction.x * to_flip)
	hand_pivot.rotation = lerp_angle(hand_pivot.rotation, look_angle, delta * hand_pivot_speed)


func process_synchronization() -> void:
	var pairs: Array[Array] = [
		[fid_position, global_position],
		[fid_flipped, flipped],
		[fid_anim, anim],
		[fid_pivot, snappedf(hand_pivot.rotation, 0.05)],
	]
	state_synchronizer.mark_many_by_id(pairs, true)
	# Send at 20 Hz, not per physics frame — see NET_SEND_INTERVAL_S.
	_net_send_accum += get_physics_process_delta_time()
	if _net_send_accum < NET_SEND_INTERVAL_S:
		return
	_net_send_accum = fmod(_net_send_accum, NET_SEND_INTERVAL_S)
	var collected_pairs: Array = state_synchronizer.collect_dirty_pairs()
	if not collected_pairs.is_empty():
		synchronizer_manager.send_my_delta(multiplayer.get_unique_id(), collected_pairs)


## Local movement is client-authoritative — networked :position echoes must keep
## the raw-apply path (process_movement overwrites them next frame by design).
func wants_net_smoothing() -> bool:
	return false


func set_camera_zoom(zoom: Vector2) -> void:
	camera_2d.zoom = zoom


## Starts collision-aware click movement. Called by both the world click input
## and the minimap. WASD cancels the route in [method process_input].
func set_click_move_target(world_target: Vector2) -> void:
	if _dead or ClientState.menu_open or _has_gui_focus():
		return
	_note_input_activity()
	_follow_peer_id = 0
	if _harvest_controller != null:
		_harvest_controller.cancel()
	if _pickup_controller != null:
		_pickup_controller.cancel()
	if _combat_target_controller != null:
		_combat_target_controller.cancel()
	if _interact_controller != null:
		_interact_controller.cancel()
	_click_navigation.request_move(world_target)
	if _click_move_marker != null:
		_click_move_marker.flash_at(world_target)


## Begin commercial-style auto-gather on [param node] (walk in, swing until
## this player's charge pool is depleted, then stop — re-click to resume after
## regen). Cancel with WASD or a ground click.
func start_auto_gather(node: MineableNode) -> void:
	if _harvest_controller == null:
		return
	if _pickup_controller != null:
		_pickup_controller.cancel()
	if _combat_target_controller != null:
		_combat_target_controller.cancel()
	if _interact_controller != null:
		_interact_controller.cancel()
	_harvest_controller.start(node)


## Walk to a ground drop / loot chest and interact. Cancel with WASD or a ground click.
## [param request] defaults to [code]item.pickup[/code]; chests use [code]chest.open[/code].
func start_auto_pickup(
	item: Node2D,
	prop_id: int,
	request: StringName = &"item.pickup"
) -> void:
	if _pickup_controller == null:
		return
	if _combat_target_controller != null:
		_combat_target_controller.cancel()
	if _interact_controller != null:
		_interact_controller.cancel()
	_pickup_controller.start(item, prop_id, request)


## Walk to a station / NPC / other interactable, then run [param on_arrived].
## Shared entry for every talkable NPC and crafting station going forward.
func start_auto_interact(target: Node2D, interact_range: float, on_arrived: Callable) -> void:
	if _interact_controller == null or target == null or not is_instance_valid(target):
		return
	_note_input_activity()
	if _harvest_controller != null:
		_harvest_controller.cancel()
	if _pickup_controller != null:
		_pickup_controller.cancel()
	if _combat_target_controller != null:
		_combat_target_controller.cancel()
	_interact_controller.start(target, interact_range, on_arrived)


## Close the fullscreen craft UI and run a batch with the compact progress chip.
func start_craft_session(
	station_key: String,
	station: CraftingStationResource,
	recipe_index: int,
	qty_target: int
) -> void:
	if _craft_controller == null:
		return
	_craft_controller.start(station_key, station, recipe_index, qty_target)


func cancel_craft_session() -> void:
	if _craft_controller != null:
		_craft_controller.cancel()


func is_crafting() -> bool:
	return _craft_controller != null and _craft_controller.is_active()


## Right-click Attack: walk into range and keep using the primary weapon.
func start_hostile_attack(npc: HostileNpc) -> void:
	_note_input_activity()
	_begin_hostile_attack(npc)


func _begin_hostile_attack(npc: HostileNpc) -> void:
	if _combat_target_controller == null or npc == null:
		return
	if _harvest_controller != null:
		_harvest_controller.cancel()
	if _pickup_controller != null:
		_pickup_controller.cancel()
	if _interact_controller != null:
		_interact_controller.cancel()
	_combat_target_controller.start(npc)


func _note_input_activity() -> void:
	_last_input_ms = Time.get_ticks_msec()


func is_afk_for_retaliate() -> bool:
	return Time.get_ticks_msec() - _last_input_ms >= AFK_RETALIATE_MS


## Server combat.hit on this local player: auto-target the attacking hostile
## unless the player has been AFK for [constant AFK_RETALIATE_MS].
## Does not refresh the AFK timer — retaliate alone cannot keep AFK farming alive.
func try_auto_retaliate(attacker_prop_id: int) -> void:
	if attacker_prop_id < 0 or _dead or is_afk_for_retaliate():
		return
	if InstanceClient.current == null or InstanceClient.current.instance_map == null:
		return
	if _combat_target_controller != null and _combat_target_controller.is_active():
		return
	var map: Map = InstanceClient.current.instance_map as Map
	if map == null or map.replicated_props_container == null:
		return
	# Static bosses (Mecha Golem) live in id_to_node; trash often uses dynamic_nodes.
	var container: ReplicatedPropsContainer = map.replicated_props_container
	var node: Node = container.id_to_node.get(attacker_prop_id, null)
	if node == null:
		node = container.dynamic_nodes.get(attacker_prop_id, null)
	if node is HostileNpc:
		var npc: HostileNpc = node as HostileNpc
		if npc.is_dead:
			return
		_begin_hostile_attack(npc)


func is_auto_gathering() -> bool:
	return _harvest_controller != null and _harvest_controller.is_active()


func notify_gather_result(data: Dictionary) -> void:
	if _harvest_controller != null:
		_harvest_controller.on_gather_result(data)


## Follow a remote player using the same collision-aware pathing as click movement.
## Any manual movement/click destination or instance change cancels the follow.
func follow_peer(peer_id: int) -> bool:
	if peer_id <= 0 or InstanceClient.current == null:
		return false
	var target: Player = InstanceClient.current.players_by_peer_id.get(peer_id, null)
	if target == null or target == self:
		return false
	_follow_peer_id = peer_id
	_follow_repath_at_ms = 0
	_update_follow_navigation()
	return true


func _update_follow_navigation() -> void:
	if _follow_peer_id <= 0 or InstanceClient.current == null:
		return
	var target: Player = InstanceClient.current.players_by_peer_id.get(
		_follow_peer_id,
		null
	)
	if target == null or not is_instance_valid(target):
		_follow_peer_id = 0
		_click_navigation.cancel()
		return
	if global_position.distance_to(target.global_position) <= FOLLOW_STOP_DISTANCE:
		_click_navigation.cancel()
		return
	var now: int = Time.get_ticks_msec()
	if now < _follow_repath_at_ms:
		return
	_follow_repath_at_ms = now + FOLLOW_REPATH_MS
	_click_navigation.request_move(target.global_position)


func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if (
		mouse_event.button_index != MOUSE_BUTTON_LEFT
		or not mouse_event.pressed
	):
		return
	if (
		_dead
		or ClientState.menu_open
		or _has_gui_focus()
		or ClientState.world_interactables_hovered > 0
	):
		return
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered != null and hovered.mouse_filter == Control.MOUSE_FILTER_STOP:
		return
	set_click_move_target(get_global_mouse_position())
	get_viewport().set_input_as_handled()


func _on_instance_changed_camera_limits(instance: InstanceClient) -> void:
	_follow_peer_id = 0
	if _harvest_controller != null:
		_harvest_controller.cancel()
	if _pickup_controller != null:
		_pickup_controller.cancel()
	if _combat_target_controller != null:
		_combat_target_controller.cancel()
	if _interact_controller != null:
		_interact_controller.cancel()
	if _craft_controller != null:
		_craft_controller.cancel()
	_apply_camera_limits(instance.instance_map if instance != null else null)
	if _click_navigation != null:
		_click_navigation.rebuild_for_map(
			instance.instance_map if instance != null else null
		)


## Clamp the camera to [param map]'s per-edge limits. Each edge defaults to ±CAMERA_LIMIT
## (unbounded), so a map that sets none leaves the camera free — and re-applying on every map
## change naturally clears a previous map's clamps. Called on spawn and on each map change.
func _apply_camera_limits(map: Map) -> void:
	if map == null:
		camera_2d.limit_left = CAMERA_LIMIT_MIN
		camera_2d.limit_top = CAMERA_LIMIT_MIN
		camera_2d.limit_right = CAMERA_LIMIT_MAX
		camera_2d.limit_bottom = CAMERA_LIMIT_MAX
		return
	camera_2d.limit_left = map.camera_limit_left
	camera_2d.limit_top = map.camera_limit_top
	camera_2d.limit_right = map.camera_limit_right
	camera_2d.limit_bottom = map.camera_limit_bottom


## Chat composing gate: while a chat field is focused, kill ALL player input (move, aim,
## attack) so typing on mobile doesn't drive the sticks or fire the weapon, and WASD on
## desktop types instead of moving. Releasing player_shoot clears any stick-latched attack
## so it doesn't keep firing once input is re-enabled. (Complements _has_gui_focus, which
## already gates the polling path — this also stops InputComponent from pressing the attack
## action in the first place.)
func set_input_active(active: bool) -> void:
	controller.enabled = active
	if not active:
		Input.action_release(&"player_shoot")


func _apply_settings() -> void:
	var settings: Dictionary = ClientState.settings.data.get(&"general", {})
	for property_name: StringName in settings:
		_on_settings_changed(&"general", property_name, settings[property_name]) 


func _on_settings_changed(section: StringName, property: StringName, value: Variant) -> void:
	match [section, property]:
		[&"general", &"camera_zoom"]:
			set_camera_zoom(clamp(value, 1.0, 4.0) * Vector2.ONE)


func _has_gui_focus() -> bool:
	var focus: Control = get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit
