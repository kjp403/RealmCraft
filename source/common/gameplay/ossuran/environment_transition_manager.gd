class_name EnvironmentTransitionManager
extends Node
## Owns the phase-3 environment shift: the forge floor freezing over at 50% HP.
##
## Three jobs, and it is the only thing that does any of them:
##   1. Cross-fade the floor from forge to ice by tweening `transition_progress`
##      on the floor layers' shared material.
##   2. Run that transition ON EVERY PEER, not just the server.
##   3. Publish the ice as a surface volume, so movement code can ask what it is
##      standing on without knowing anything about this encounter.
##
## WHY IT IS REPLICATED, and the bug it fixes. [OssuranArena] only builds its
## controllers on the world server, so everything hanging off
## `BossStateMachine.state_changed` — including the freeze — ran server-side
## only. The server dutifully tweened a shader nobody was looking at while every
## client kept playing in an unfrozen forge. Visual state driven off server-only
## signals has to be pushed explicitly, so [method begin_freeze] sends
## `ossuran.environment` and the client half of this same script runs the
## identical tween locally.
##
## The push carries the REMAINING duration rather than a per-frame value: a
## client that joins or reconnects mid-transition gets the end state and the time
## left, and lands in the same place as everyone else without a stream of
## updates. One message per transition, not one per frame.
##
## WHAT IT DELIBERATELY DOES NOT DO — navigation. This project has no navmesh:
## there is no NavigationServer2D, NavigationRegion2D or NavigationAgent2D
## anywhere in `source/`, and every agent steers by
## `velocity = direction * move_speed` + `move_and_slide()` straight against
## collision. There is nothing to re-bake, and re-baking is not merely
## unnecessary here but harmful: the encounter's contract is that the freeze
## changes NOTHING about the walkable world, which is what stops mobs and players
## being stranded mid-fight, and `verify_ossuran_encounter` asserts it
## (`sealed=true, 0 wall pockets`). The frost is a material on existing layers
## and a rect in a lookup table — not one collision polygon moves. What the brief
## actually needs from that requirement is agent HANDLING, which is
## [IceSlip] plus the cold's existing MOVE_SPEED slow.

## Fired when a transition finishes, on whichever peer ran it.
signal transition_finished(frozen: bool)

## Seconds the forge takes to freeze over.
const FREEZE_SECONDS: float = 2.2
## Seconds to thaw on reset. Faster than freezing — a reset is bookkeeping
## between groups, not a moment anyone is meant to watch.
const THAW_SECONDS: float = 0.6
## The uniform every floor layer's material exposes.
const PROGRESS_UNIFORM: StringName = &"transition_progress"
## Key this manager registers its ice volume under.
const VOLUME_ID: StringName = &"ossuran_arena_ice"
## Client push channel.
const PUSH_CHANNEL: StringName = &"ossuran.environment"

## The floor layers that carry the freeze material. Both the ground and the prop
## layer, so the anvils and hazard chevrons frost with the slate under them
## instead of staying summer-warm on an iced floor.
@export var floor_layers: Array[TileMapLayer] = []
## World-space rect of the room that freezes. Drives both the shader's room mask
## and the surface volume, from ONE number — a shader that frosted a different
## area than the one players slip on is a bug you can see but not explain.
@export var arena_rect: Rect2 = Rect2(32.0, 32.0, 704.0, 480.0)
## Ambient particles swapped at the freeze.
@export var ember_particles: CPUParticles2D
@export var frost_particles: CPUParticles2D

## 0 = forge, 1 = ice. Authoritative on whichever peer is running the tween.
var progress: float = 0.0
var frozen: bool = false

var _tween: Tween = null
var _subscribed: bool = false


func _ready() -> void:
	_resolve_scene_refs()
	_apply_progress(0.0)
	# Clients listen for the server's announcement; the server does not, or it
	# would answer its own push and restart the tween it is already running.
	if not GameMode.is_world_server():
		Client.subscribe(PUSH_CHANNEL, _on_environment_push)
		_subscribed = true


func _exit_tree() -> void:
	# The volume is static state that outlives this node. An instance torn down
	# mid-freeze would otherwise leave a permanent patch of ice in the lookup
	# table, and the next group to load a map overlapping that rect would slide
	# around on a floor with no ice on it.
	SurfaceQuery.unregister_volume(VOLUME_ID)
	if _subscribed and is_instance_valid(Client):
		Client.unsubscribe(PUSH_CHANNEL, _on_environment_push)


## Fill any unset @export from a conventional sibling name.
##
## Same reasoning as [method OssuranArena._resolve_scene_refs]: a node-typed
## @export only survives a scene load when the .tscn carries a matching
## `node_paths=` entry, and an ARRAY of them is worse — one typo is a null the
## encounter discovers halfway through a fight as a stage that quietly does
## nothing. Resolving by name lets the map be authored by hand and by tool.
## Explicit exports still win; this only fills what is missing.
func _resolve_scene_refs() -> void:
	if floor_layers.is_empty():
		for path: NodePath in [^"../Tiles/Ground", ^"../Tiles/Deco"]:
			var layer: TileMapLayer = get_node_or_null(path) as TileMapLayer
			if layer != null:
				floor_layers.append(layer)
	if ember_particles == null:
		ember_particles = get_node_or_null(^"../ArenaEmbers") as CPUParticles2D
	if frost_particles == null:
		frost_particles = get_node_or_null(^"../ArenaFrost") as CPUParticles2D


# --- Server entry points ------------------------------------------------------


## Freeze the forge. Server-side; announces to every client in the instance.
func begin_freeze() -> void:
	if frozen:
		return
	frozen = true
	_broadcast(1.0, FREEZE_SECONDS)
	_run(1.0, FREEZE_SECONDS)


## Thaw back to the forge. Called on encounter reset so a pooled instance never
## hands the next group a room that is already dead.
func begin_thaw() -> void:
	if not frozen and is_zero_approx(progress):
		return
	frozen = false
	_broadcast(0.0, THAW_SECONDS)
	_run(0.0, THAW_SECONDS)


## Snap to a state with no animation, for teardown.
func reset_immediate() -> void:
	_kill_tween()
	frozen = false
	_apply_progress(0.0)


# --- The transition -----------------------------------------------------------


## Tween `transition_progress` to [param target] over [param seconds].
##
## One tween drives every consumer — both floor layers and the surface volume —
## because they must agree at every instant. Two tweens can drift by a frame,
## and a frame where the floor looks frozen but the volume says stone is a frame
## where the player does not slide and cannot be told why.
func _run(target: float, seconds: float) -> void:
	_kill_tween()
	# Particles flip at the START of the transition, not the end: embers stop
	# rising the moment the cold arrives, and `emitting = false` lets the ones
	# already in flight live out their lifetime instead of vanishing on a frame.
	_apply_particles(target > 0.5)
	_tween = create_tween()
	_tween.tween_method(_apply_progress, progress, target, seconds)
	_tween.tween_callback(func() -> void: transition_finished.emit(frozen))


## Push one value into every consumer. This is the only place `progress` changes.
func _apply_progress(value: float) -> void:
	progress = clampf(value, 0.0, 1.0)
	for layer: TileMapLayer in floor_layers:
		if layer == null or not is_instance_valid(layer):
			continue
		var material: ShaderMaterial = layer.material as ShaderMaterial
		if material == null:
			continue
		material.set_shader_parameter(PROGRESS_UNIFORM, progress)
		# The room mask travels with it, so the shader and the surface volume can
		# never disagree about where the ice is.
		material.set_shader_parameter(&"arena_rect", Vector4(
			arena_rect.position.x, arena_rect.position.y,
			arena_rect.size.x, arena_rect.size.y
		))

	# The floor becomes slippery once the sheet has actually taken, not the
	# instant the tween starts — sliding on a floor that still looks like stone
	# reads as a bug rather than as ice.
	if progress >= SLIP_THRESHOLD:
		SurfaceQuery.register_volume(
			VOLUME_ID, arena_rect, SurfaceQuery.ICE, Map.of(self)
		)
	else:
		SurfaceQuery.unregister_volume(VOLUME_ID)


## Coverage at which the floor starts behaving as ice. Matched to the point the
## creep visibly dominates the room rather than to 1.0, so handling changes while
## the player can still see it happening.
const SLIP_THRESHOLD: float = 0.6


func _apply_particles(to_ice: bool) -> void:
	if ember_particles != null and is_instance_valid(ember_particles):
		ember_particles.emitting = not to_ice
	if frost_particles != null and is_instance_valid(frost_particles):
		frost_particles.visible = to_ice
		frost_particles.emitting = to_ice


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


# --- Replication --------------------------------------------------------------


func _broadcast(target: float, seconds: float) -> void:
	if not GameMode.is_world_server() or WorldServer.curr == null:
		return
	var instance: Node = _instance()
	if instance == null:
		return
	for peer_id: int in instance.players_by_peer_id:
		WorldServer.curr.data_push.rpc_id(peer_id, PUSH_CHANNEL, {
			"target": target,
			"seconds": seconds,
			"rect": arena_rect,
		})


## CLIENT: adopt the announced transition and run it locally.
func _on_environment_push(payload: Dictionary) -> void:
	var target: float = clampf(float(payload.get("target", 0.0)), 0.0, 1.0)
	var seconds: float = maxf(0.0, float(payload.get("seconds", FREEZE_SECONDS)))
	var rect: Variant = payload.get("rect", null)
	if rect is Rect2:
		arena_rect = rect
	frozen = target > 0.5
	if seconds <= 0.0:
		_kill_tween()
		_apply_particles(frozen)
		_apply_progress(target)
		transition_finished.emit(frozen)
		return
	_run(target, seconds)


## The ServerInstance this manager's map belongs to, or null anywhere else.
## Guarded the same way the rest of the encounter is: off-server the map's parent
## is a SubViewport or a plain Node, and iterating it would throw.
func _instance() -> Node:
	var map: Map = Map.of(self)
	var owner_node: Node = map.get_parent() if map != null else null
	if owner_node != null and owner_node.get(&"players_by_peer_id") is Dictionary:
		return owner_node
	return null
