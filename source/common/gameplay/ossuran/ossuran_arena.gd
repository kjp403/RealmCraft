class_name OssuranArena
extends Node2D
## The stage manager for the Ossuran encounter: it owns the boss body, the two
## charge pads, the wave chamber, the three pillars and the cold, and it moves
## between them by listening to [BossStateMachine]. The machine decides WHERE the
## fight is; this node makes that true in the world.
##
## ONE MAP, TWO ROOMS. The summoning chamber is a second region of this same map
## scene, parked far from the arena, not a separate instance. That is a
## deliberate architectural choice: a cross-instance move despawns and respawns
## every player (see [method InstanceManager.teleport_peer_to]), which would tear
## the group out of the encounter's own instance and leave the state machine,
## the boss body and the wave manager stranded in different places with no shared
## authority. Same-instance teleports keep one instance, one state machine and
## one set of players for the whole fight, and cost a position push.
##
## Server-authoritative throughout. Clients receive replicated HP, the pads'
## `ossuran.pad` pushes, `ossuran.phase` for the HUD and ordinary rp_ visuals.

## Phase-1 armor. Deliberately enormous: this is the "substantially high defence"
## the brief opens on, and it is the reason the group cannot simply beat on him
## while a pad charges. Cracked open by the Ember ritual — see
## [method _on_state_changed] on MELEE_TRIAL.
##
## The CRACKED value is not a constant: it is whatever the body spawned with
## (Ossuran's own resource authors 210). Restoring a hardcoded number here would
## quietly re-balance a boss that also runs as a world boss outside this
## encounter — the seal is a temporary state this arena adds and then removes,
## never a new statline it imposes.
const ARMOR_SEALED: float = 4000.0
## Damage multiplier while sealed ("low attack"), and once enraged.
const DAMAGE_SEALED: float = 0.55
const DAMAGE_FROZEN: float = 1.35

## Phase-2 reward for charging the Storm Pad: the buff the pillar run is built
## around. Flat MOVE_SPEED on a 112.5 base (~30% faster), and a flat bump to
## BOTH damage stats — AD and AP — because the group running the pillars is
## mixed, and buffing only one would hand the phase to half the party.
const WARD_SPEED_BONUS: float = 34.0
const WARD_AD_BONUS: float = 22.0
const WARD_AP_BONUS: float = 22.0
## Long enough to cover the pillar phase and bleed into the assault, per the
## brief's "buffs from the 2nd pad remain".
const WARD_DURATION_S: float = 150.0

## Seconds the environment takes to turn from forge to ice.
const FREEZE_LERP_S: float = 2.2
## Final tint of the ice tile sheet. See [method _freeze_environment].
##
## Both the alpha AND the colour matter. The IceSet art is near-white, so at full
## strength it erased the forge completely and the room read as an outdoor
## snowfield rather than a foundry someone had just frozen. Knocking the value
## down and pushing it blue keeps it unmistakably ice while letting the red slate
## underneath show through — which is the whole point of the phase: this is the
## SAME room, taken.
const ICE_LAYER_TINT: Color = Color(0.72, 0.83, 0.98, 0.78)

## How often the arena asks "has anyone walked in / is the room empty".
const ARM_POLL_S: float = 1.0
## How long the room must stay empty before the encounter resets. Long enough to
## ride out a full wipe (everyone dead but still in the instance) and the respawn
## that follows, so a group is never reset out from under a recovery.
const RESET_AFTER_EMPTY_S: float = 20.0

@export_group("Arena")
@export var boss_spawn: Marker2D
@export var ember_pad: ChargePad
@export var storm_pad: ChargePad
## Where the group lands when they come back down from the chamber.
@export var arena_return: Marker2D
## The three pillar pedestals, in EMBER / THORN / HEX order.
@export var pillar_markers: Array[Marker2D] = []
## Braziers that count as warmth in phase 3.
@export var fire_sources: Array[Node2D] = []

@export_group("Summoning chamber")
## Where the group lands in the chamber.
@export var chamber_spawn: Marker2D
@export var wave_manager: MinionWaveManager

@export_group("Phase 3 environment")
## A DECORATIVE ice layer stacked over the forge floor. It carries no collision
## and no navigation polygons — see [method _freeze_environment] for why that is
## load-bearing rather than incidental.
@export var ice_layer: TileMapLayer
## Full-screen frost tint driven by the environment shader.
@export var frost_overlay: CanvasItem

## Which enemy type the boss body is built from.
@export var boss_slug: StringName = &"ossuran"
## Pillar enemy slugs, in the same order as [member pillar_markers].
@export var pillar_slugs: Array[StringName] = [
	&"ossuran_pillar_ember", &"ossuran_pillar_thorn", &"ossuran_pillar_hex",
]

var boss: HostileNpc = null
var state_machine: BossStateMachine = null
var parser: AttackParser = null
var cold: ColdDebuffController = null

## The armor the boss spawned with, captured before the seal is applied so it can
## be handed back exactly. Read from the live stat rather than the resource so a
## zone health/armor multiplier is preserved too.
var _authored_armor: float = 0.0
## Live pillar bodies for the current phase-2 run.
var _pillars: Array[HostileNpc] = []
var _running: bool = false
## Next tick (ms) the arm/reset poll is allowed to run.
var _poll_at_ms: int = 0
## When the room first went empty while running (ms), or 0 while populated.
var _empty_since_ms: int = 0
## Latched the moment Ossuran dies, and only cleared once the room empties.
## Without it the arm poll sees a live player and a stopped encounter one second
## after the kill, and spawns the boss again on top of the group while they are
## still looting him.
var _cleared: bool = false
## Latches the environment shift so a re-entry into phase 3 cannot re-run it.
var _frozen: bool = false


func _ready() -> void:
	# Depth: everything in the arena sorts by its feet. Set here rather than in
	# the scene so a hand-edit to the .tscn cannot silently drop it and leave
	# players drawing through the boss.
	y_sort_enabled = true
	_resolve_scene_refs()
	if not GameMode.is_world_server():
		return
	_build_controllers()
	# Self-arming: the encounter starts when someone walks in and stands itself
	# down when the room empties. Instances are pooled and reused, so a fight
	# that only ever started (and never reset) would hand the next group a boss
	# at 50% health with the cold already running.
	set_process(true)


## Fill any unset @export from a conventional child name.
##
## Node-typed @exports only survive a scene load when the .tscn also carries a
## matching `node_paths=` entry, and an ARRAY of node references is fiddlier
## still — a single typo there is a null the encounter only discovers halfway
## through a fight, as a stage that quietly does nothing. Resolving by name means
## the scene is authorable by hand and by tool, an export left empty is not a
## bug, and Map._ready's own "find the container by child name" safety net is
## followed rather than contradicted. Explicit exports still win: this only ever
## fills in what is missing.
func _resolve_scene_refs() -> void:
	if boss_spawn == null:
		boss_spawn = get_node_or_null(^"BossSpawn") as Marker2D
	if arena_return == null:
		arena_return = get_node_or_null(^"ArenaReturn") as Marker2D
	if chamber_spawn == null:
		chamber_spawn = get_node_or_null(^"ChamberSpawn") as Marker2D
	if ember_pad == null:
		ember_pad = get_node_or_null(^"EmberPad") as ChargePad
	if storm_pad == null:
		storm_pad = get_node_or_null(^"StormPad") as ChargePad
	if wave_manager == null:
		wave_manager = get_node_or_null(^"WaveManager") as MinionWaveManager
	if ice_layer == null:
		ice_layer = get_node_or_null(^"../Tiles/Ice") as TileMapLayer
	if frost_overlay == null:
		frost_overlay = get_node_or_null(^"../FrostOverlay") as CanvasItem
	if pillar_markers.is_empty():
		pillar_markers = _markers_under(^"PillarMarkers")
	if fire_sources.is_empty():
		for child: Node in _children_of(^"FireSources"):
			if child is Node2D:
				fire_sources.append(child as Node2D)
	# The wave manager owns its own spawn points, for the same reason.
	if wave_manager != null and wave_manager.spawn_markers.is_empty():
		wave_manager.spawn_markers = _markers_under(^"WaveManager/Spawns")


func _markers_under(path: NodePath) -> Array[Marker2D]:
	var out: Array[Marker2D] = []
	for child: Node in _children_of(path):
		if child is Marker2D:
			out.append(child as Marker2D)
	return out


func _children_of(path: NodePath) -> Array[Node]:
	var parent: Node = get_node_or_null(path)
	return parent.get_children() if parent != null else []


## Create the server-side brains. Split out of _ready so a test harness can stand
## the encounter up without a map.
func _build_controllers() -> void:
	parser = AttackParser.new()
	parser.name = "AttackParser"

	state_machine = BossStateMachine.new()
	state_machine.name = "BossStateMachine"
	state_machine.parser = parser
	add_child(state_machine)

	cold = ColdDebuffController.new()
	cold.name = "ColdDebuffController"
	cold.fire_sources = fire_sources
	add_child(cold)

	state_machine.state_changed.connect(_on_state_changed)
	state_machine.phase_changed.connect(_on_phase_changed)
	state_machine.threshold_reached.connect(_on_threshold)

	if ember_pad != null:
		ember_pad.charged.connect(_on_pad_charged)
	if storm_pad != null:
		storm_pad.charged.connect(_on_pad_charged)
	if wave_manager != null:
		wave_manager.all_waves_cleared.connect(_on_waves_cleared)
		wave_manager.wave_started.connect(_on_wave_started)


## Poll for arrival and for the room emptying. One second apart — this is a
## "has anyone walked in" question, not a per-frame one.
func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	if now < _poll_at_ms:
		return
	_poll_at_ms = now + int(ARM_POLL_S * 1000.0)

	var populated: bool = not _live_players().is_empty()
	if not _running:
		# A cleared room re-arms only after everyone has left, so the victors get
		# to loot and walk out instead of being handed a fresh boss.
		if _cleared:
			if not populated:
				_cleared = false
			return
		if populated:
			begin()
		return

	# Running but empty: give it a grace window (a wipe leaves everyone dead but
	# still present, and a respawn brings them back) before tearing down.
	if populated:
		_empty_since_ms = 0
		return
	if _empty_since_ms == 0:
		_empty_since_ms = now
	elif now - _empty_since_ms >= int(RESET_AFTER_EMPTY_S * 1000.0):
		stop()
		_empty_since_ms = 0


## Start the encounter: spawn Ossuran sealed, open the first pad.
func begin() -> void:
	if _running or not GameMode.is_world_server():
		return
	_running = true
	_frozen = false
	_spawn_boss()
	if boss == null:
		_running = false
		return
	state_machine.boss = boss
	parser.boss = boss
	cold.boss = boss
	state_machine.begin()


## Tear the whole encounter down (wipe, last player left, instance recycling).
## Every subsystem that can outlive the fight is stopped here.
func stop() -> void:
	_running = false
	if wave_manager != null:
		wave_manager.stop()
	if cold != null:
		cold.stop()
	if ember_pad != null:
		ember_pad.close()
	if storm_pad != null:
		storm_pad.close()
	_clear_pillars()
	if state_machine != null:
		state_machine.reset()
	if is_instance_valid(boss):
		_despawn(boss)
	boss = null


func _spawn_boss() -> void:
	var container: ReplicatedPropsContainer = _container()
	if container == null:
		push_warning("OssuranArena: no ReplicatedPropsContainer — cannot spawn boss.")
		return
	var at: Vector2 = boss_spawn.global_position if boss_spawn != null else global_position
	var node: Node = container.spawn_dynamic(
		ReplicatedPropsContainer.SCENE_HOSTILE_NPC,
		container.to_local(at),
		{"enemy_type_slug": boss_slug}
	)
	var npc: HostileNpc = node as HostileNpc
	if npc == null:
		return
	npc.respawns = false
	npc.max_distance_from_spawn = HostileNpc.NO_LEASH_DISTANCE

	# The damage gate rides on the BODY, where HostileNpc.incoming_damage_factor
	# can find it (see _attack_parser there).
	npc.add_child(parser)

	# The stock boss kit — slams, meteors, the enrage pose — is driven by the
	# shared BossController from the .tres. This encounter adds structure on top
	# of that; it does not reimplement a boss's moveset.
	var brain: BossController = BossController.new()
	brain.name = "BossController"
	brain.boss = npc
	npc.add_child(brain)

	npc.action_root_until_ms = Time.get_ticks_msec() + int(HostileNpc.SPAWN_FREEZE_S * 1000.0)
	npc.replicate_visual(&"rp_spawn_effect", [])
	npc.died.connect(_on_boss_died, CONNECT_ONE_SHOT)
	boss = npc

	# Capture BEFORE sealing, or the seal's own 4000 becomes "authored" and the
	# boss stays effectively immune for the rest of the fight.
	_authored_armor = npc.stats_component.get_stat(Stat.ARMOR)
	# Sealed: enormous armor, muted damage.
	_seal_boss(true)


## Apply (or lift) the phase-1 "sealed" statline. Lifting restores the armor the
## body actually spawned with, captured in [member _authored_armor].
func _seal_boss(sealed: bool) -> void:
	if not is_instance_valid(boss):
		return
	boss.stats_component.set_stat(
		Stat.ARMOR, ARMOR_SEALED if sealed else _authored_armor
	)
	boss.damage_dealt_mult = DAMAGE_SEALED if sealed else 1.0


# --- Stage transitions -------------------------------------------------------


func _on_state_changed(_from: BossStateMachine.State, to: BossStateMachine.State) -> void:
	match to:
		BossStateMachine.State.EMBER_PAD:
			_callout("Ossuran: \"Kindle it, then. Let me see you try.\"")
			if ember_pad != null:
				ember_pad.open()
		BossStateMachine.State.GAUNTLET:
			if ember_pad != null:
				ember_pad.close()
			_teleport_group(_chamber_point(), "The floor opens beneath you.")
			if wave_manager != null:
				wave_manager.begin()
		BossStateMachine.State.MELEE_TRIAL:
			_teleport_group(_arena_point(), "You are dragged back to the forge.")
			# The ritual cracks his guard: this is the moment the fight becomes
			# winnable, and it is the payoff for the pad and the gauntlet.
			_seal_boss(false)
			_callout("Ossuran's guard splits. STEEL ONLY.")
		BossStateMachine.State.STORM_PAD:
			if storm_pad != null:
				storm_pad.open()
			_callout("Ossuran: \"Conjure, then. I will break what you build.\"")
		BossStateMachine.State.PILLARS:
			if storm_pad != null:
				storm_pad.close()
			_grant_ward()
			_spawn_pillars()
			_callout("Three pillars rise. Break them all.")
		BossStateMachine.State.OPEN_ASSAULT:
			_clear_pillars()
			_callout("The pillars fall. Ossuran is open — hit him with everything.")
		BossStateMachine.State.FROZEN_END:
			_freeze_environment()
			_callout("Ossuran: \"Then FREEZE.\"  Keep to the fires. Ranged and magic only.")
		BossStateMachine.State.DEFEATED:
			_on_defeated()
		_:
			pass


func _on_phase_changed(phase: int) -> void:
	_push_phase(phase)


func _on_threshold(fraction: float) -> void:
	var pct: int = int(round(fraction * 100.0))
	_callout("Ossuran staggers at %d%%." % pct)


## Both pads land here; the state machine's linear spine decides what that means,
## so the pads never have to know which stage they belong to.
func _on_pad_charged() -> void:
	if not _running:
		return
	state_machine.advance()


func _on_wave_started(index: int, total: int) -> void:
	_callout("Wave %d of %d" % [index, total])


func _on_waves_cleared() -> void:
	if not _running:
		return
	state_machine.advance()


# --- Pillars -----------------------------------------------------------------


func _spawn_pillars() -> void:
	_clear_pillars()
	var container: ReplicatedPropsContainer = _container()
	if container == null:
		return
	var kinds: Array = [
		OssuranPillar.Kind.EMBER, OssuranPillar.Kind.THORN, OssuranPillar.Kind.HEX,
	]
	for i: int in mini(pillar_markers.size(), pillar_slugs.size()):
		var marker: Marker2D = pillar_markers[i]
		if marker == null or not is_instance_valid(marker):
			continue
		var node: Node = container.spawn_dynamic(
			ReplicatedPropsContainer.SCENE_HOSTILE_NPC,
			container.to_local(marker.global_position),
			{"enemy_type_slug": pillar_slugs[i]}
		)
		var npc: HostileNpc = node as HostileNpc
		if npc == null:
			continue
		npc.respawns = false
		npc.max_distance_from_spawn = HostileNpc.NO_LEASH_DISTANCE
		var brain: OssuranPillar = OssuranPillar.new()
		brain.name = "PillarBrain"
		brain.pillar = npc
		brain.kind = kinds[i % kinds.size()]
		npc.add_child(brain)
		npc.replicate_visual(&"rp_spawn_effect", [])
		npc.tree_exited.connect(_on_pillar_gone.bind(npc))
		_pillars.append(npc)


## A pillar has left the tree. Same reasoning as [MinionWaveManager]: leaving the
## tree is the only event that means gone, and the phase ends only when the last
## one has.
func _on_pillar_gone(npc: HostileNpc) -> void:
	_pillars.erase(npc)
	if not _running:
		return
	if state_machine.state != BossStateMachine.State.PILLARS:
		return
	if _pillars.size() > 0:
		return
	state_machine.advance()


func _clear_pillars() -> void:
	for npc: HostileNpc in _pillars:
		if not is_instance_valid(npc):
			continue
		if npc.tree_exited.is_connected(_on_pillar_gone):
			npc.tree_exited.disconnect(_on_pillar_gone)
		_despawn(npc)
	_pillars.clear()


# --- Phase 2 ward ------------------------------------------------------------


## The Storm Pad's payoff: speed and damage for everyone in the instance.
func _grant_ward() -> void:
	for player: Player in _live_players():
		BuffService.apply(player, Stat.MOVE_SPEED, WARD_SPEED_BONUS, WARD_DURATION_S)
		BuffService.apply(player, Stat.AD, WARD_AD_BONUS, WARD_DURATION_S)
		BuffService.apply(player, Stat.AP, WARD_AP_BONUS, WARD_DURATION_S)


# --- Phase 3 environment -----------------------------------------------------


## Turn the forge to ice.
##
## NAVIGATION SAFETY — the reason this fades a layer instead of swapping one:
## the Ground layer that carries the collision polygons and feeds the navigation
## bake is never touched. [member ice_layer] is a decorative layer stacked above
## it with no physics and no navigation, so the walkable world is byte-identical
## before and after the shift and no agent's path is invalidated mid-fight.
## Clearing or re-filling the Ground layer at runtime would rebuild its polygons
## and strand every mob that was pathing across it.
func _freeze_environment() -> void:
	if _frozen:
		return
	_frozen = true

	_seal_boss(false)
	if is_instance_valid(boss):
		boss.damage_dealt_mult = DAMAGE_FROZEN
		boss.replicate_visual(&"rp_frost_nova", [boss.global_position, 260.0])

	if ice_layer != null:
		ice_layer.visible = true
		# Start transparent but already at the target COLOUR, so the tween only
		# has to bring alpha up — fading the tint in as well makes the sheet pass
		# through a washed-out white on the way, which is the exact look this
		# tint exists to avoid.
		ice_layer.modulate = Color(
			ICE_LAYER_TINT.r, ICE_LAYER_TINT.g, ICE_LAYER_TINT.b, 0.0
		)
		var tween: Tween = create_tween()
		tween.tween_property(ice_layer, ^"modulate:a", ICE_LAYER_TINT.a, FREEZE_LERP_S)
	if frost_overlay != null:
		frost_overlay.visible = true
		var material: ShaderMaterial = frost_overlay.material as ShaderMaterial
		if material != null:
			var shift: Tween = create_tween()
			shift.tween_method(
				func(v: float) -> void:
					material.set_shader_parameter(&"freeze", v),
				0.0, 1.0, FREEZE_LERP_S
			)

	if cold != null:
		cold.fire_sources = fire_sources
		cold.begin()


# --- Teleport ----------------------------------------------------------------


## Move every living player to [param destination] and tell their clients.
##
## Server state and the client push are BOTH required: movement is
## client-authoritative in this project, so setting the server-side position
## alone is overwritten on the player's next input frame. The push is what
## actually moves them (and freezes input briefly on arrival); the server write
## is what every OTHER viewer sees. Velocity and animation are reset here so
## nobody arrives still sliding or mid-swing.
func _teleport_group(destination: Vector2, reason: String) -> void:
	var instance: Node = _instance()
	if instance == null or WorldServer.curr == null:
		return
	var index: int = 0
	for peer_id: int in instance.players_by_peer_id:
		var player: Player = instance.players_by_peer_id[peer_id]
		if player == null or not is_instance_valid(player):
			continue
		# Fan the group out so they never land stacked on one pixel, which reads
		# as a single body and breaks y-sorting for a frame.
		var spread: Vector2 = Vector2.RIGHT.rotated(float(index) * TAU / 6.0) * 26.0
		var at: Vector2 = destination + (spread if index > 0 else Vector2.ZERO)
		index += 1

		player.velocity = Vector2.ZERO
		player.anim = Character.Animations.IDLE
		player.mark_just_teleported()
		player.global_position = at
		if player.state_synchronizer != null:
			player.state_synchronizer.set_by_path(^":position", at)
		WorldServer.curr.data_push.rpc_id(peer_id, &"player.teleport", {"position": at})
	if not reason.is_empty():
		_callout(reason)


func _chamber_point() -> Vector2:
	if chamber_spawn != null and is_instance_valid(chamber_spawn):
		return chamber_spawn.global_position
	return global_position


func _arena_point() -> Vector2:
	if arena_return != null and is_instance_valid(arena_return):
		return arena_return.global_position
	if boss_spawn != null and is_instance_valid(boss_spawn):
		return boss_spawn.global_position + Vector2(0.0, 120.0)
	return global_position


# --- Finish ------------------------------------------------------------------


func _on_boss_died(_killer: Character) -> void:
	if state_machine != null:
		state_machine.defeat()


func _on_defeated() -> void:
	_running = false
	_cleared = true
	if cold != null:
		cold.stop()
	if wave_manager != null:
		wave_manager.stop()
	_clear_pillars()
	_callout("Ossuran falls. The forge goes quiet.")


# --- Shared helpers ----------------------------------------------------------


func _push_phase(phase: int) -> void:
	var instance: Node = _instance()
	if instance == null or WorldServer.curr == null:
		return
	var label: String = state_machine.label() if state_machine != null else ""
	for peer_id: int in instance.players_by_peer_id:
		WorldServer.curr.data_push.rpc_id(peer_id, &"ossuran.phase", {
			"phase": phase,
			"label": label,
		})


func _callout(text: String) -> void:
	var instance: Node = _instance()
	if instance == null or WorldServer.curr == null:
		return
	for peer_id: int in instance.players_by_peer_id:
		WorldServer.curr.data_push.rpc_id(peer_id, &"boss.callout", {"text": text})


func _despawn(npc: HostileNpc) -> void:
	var container: ReplicatedPropsContainer = npc.container
	var child_id: int = container.child_id_of_node(npc) if container != null else -1
	if child_id >= 0:
		container.despawn_dynamic(child_id)
	else:
		npc.queue_free()


func _container() -> ReplicatedPropsContainer:
	var map: Map = Map.of(self)
	return map.replicated_props_container if map != null else null


func _live_players() -> Array[Player]:
	var out: Array[Player] = []
	var instance: Node = _instance()
	if instance == null:
		return out
	for peer_id: int in instance.players_by_peer_id:
		var player: Player = instance.players_by_peer_id[peer_id]
		if player != null and is_instance_valid(player) and not player.is_dead:
			out.append(player)
	return out


func _instance() -> Node:
	var map: Map = Map.of(self)
	var owner_node: Node = map.get_parent() if map != null else null
	return owner_node if _is_server_instance(owner_node) else null


## True when [param node] is a live ServerInstance — i.e. it actually carries the
## player roster the encounter iterates.
##
## Guard, not paranoia: a map is only parented to a ServerInstance on the world
## server. Mounted anywhere else (a preview renderer, a test harness, an editor
## scene) its parent is a SubViewport or a plain Node, and every `for peer_id in
## instance.players_by_peer_id` in this file throws on it. Returning null here
## makes all of them no-op instead, which is the correct behaviour off-server.
static func _is_server_instance(node: Node) -> bool:
	return node != null and node.get(&"players_by_peer_id") is Dictionary
