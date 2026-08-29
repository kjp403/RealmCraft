class_name MinionWaveManager
extends Node2D
## Runs the five-wave gauntlet in the Ossuran summoning chamber and reports when
## the room is clear.
##
## Node2D, not Node: [method _spawn_point] falls back to this node's own
## `global_position` when the chamber has no spawn markers, so the manager still
## produces a valid wave in a bare test scene.
##
## Completion is driven by [signal Node.tree_exited] on the spawned bodies rather
## than by counting [signal HostileNpc.died]. That is the deliberate choice: a
## mob emits `died` the instant its HP hits zero, but it stays in the world for
## its death animation and only leaves on `despawn_dynamic` (see
## [method HostileNpc._process_death] — single-life mobs despawn instead of
## respawning). Teleporting on `died` therefore yanks the group out from under a
## corpse that is still standing, and — worse — a mob killed by a damage-over-
## time after the wave "ended" could fire a second completion. `tree_exited` is
## the one edge that means GONE, it fires exactly once per body, and it fires
## even for a mob removed by teardown, which is why every exit path below
## re-checks [member _running].
##
## Server-only: it spawns through the map's [ReplicatedPropsContainer], which
## only exists authoritatively on the world server.

## Fired as each wave hits the floor. (index is 1-based, for the HUD.)
signal wave_started(index: int, total: int)
## Fired when a wave's last body leaves the tree — including the final one.
signal wave_cleared(index: int, total: int)
## The gauntlet is done. The arena listens for this and teleports the group back
## down to Ossuran. Fires exactly once per run.
signal all_waves_cleared()

## Beat between a wave clearing and the next one spawning. Long enough to loot
## and reposition, short enough that the room never feels idle.
const WAVE_GAP_S: float = 2.5
## Delay between the last body leaving and the return teleport, so the "chamber
## clear" callout is readable before the screen changes.
const RETURN_DELAY_S: float = 2.0
## Spread of a wave's bodies around its spawn marker.
const SPAWN_SPREAD_PX: float = 34.0

## The five waves, escalating. Each entry is one wave: a list of
## [slug, count] pairs, so a wave can mix archetypes. Data, not code — retuning
## the gauntlet is an edit here and nothing else.
##
## The ramp is deliberate: waves 1-2 teach the room, 3 adds ranged pressure that
## punishes standing still, 4 is the volume spike, and 5 is the smallest body
## count but the heaviest single bodies, so the gauntlet ends on a fight rather
## than on a mop-up.
const WAVES: Array = [
	[[&"ossuran_bonepicker", 4]],
	[[&"ossuran_bonepicker", 5], [&"ossuran_emberling", 2]],
	[[&"ossuran_bonepicker", 4], [&"ossuran_cinder_archer", 3]],
	[[&"ossuran_emberling", 5], [&"ossuran_cinder_archer", 3]],
	[[&"ossuran_marrow_knight", 3], [&"ossuran_emberling", 4]],
]

## Markers the waves spawn on. Assigned by the chamber scene; falls back to this
## node's own position when empty, so the manager is never a hard dependency on
## scene layout.
var spawn_markers: Array[Marker2D] = []
## Health / damage multipliers stamped onto every spawned body, so the gauntlet
## can be tuned per difficulty without editing five EnemyTypeResources.
var minion_health_mult: float = 1.0
var minion_damage_mult: float = 1.0

## Live bodies for the CURRENT wave. The teleport gate the brief asks for is
## exactly `active_minions.size() == 0` — see [method _on_minion_exited].
var active_minions: Array[HostileNpc] = []
## 0 before the run, then 1..TOTAL as each wave lands.
var current_wave: int = 0
## Guards every async continuation. Cleared by [method stop] so a group that
## wipes or leaves mid-wave cannot trigger a teleport afterwards.
var _running: bool = false
## Latches the completion so `all_waves_cleared` can only ever fire once, even
## if two bodies leave the tree on the same frame.
var _finished: bool = false


func total_waves() -> int:
	return WAVES.size()


## Start the gauntlet at wave 1. Safe to call once per chamber activation.
func begin() -> void:
	if _running or not GameMode.is_world_server():
		return
	_running = true
	_finished = false
	current_wave = 0
	active_minions.clear()
	_advance()


## Tear the gauntlet down: despawn anything still alive and make every pending
## continuation a no-op. Called when the group wipes, leaves, or the encounter
## resets.
func stop() -> void:
	_running = false
	for npc: HostileNpc in active_minions:
		if not is_instance_valid(npc):
			continue
		# Disconnect first — despawning is about to fire tree_exited on each of
		# these, and without this the handler would run the wave bookkeeping
		# during teardown.
		if npc.tree_exited.is_connected(_on_minion_exited):
			npc.tree_exited.disconnect(_on_minion_exited)
		var container: ReplicatedPropsContainer = npc.container
		var child_id: int = container.child_id_of_node(npc) if container != null else -1
		if child_id >= 0:
			container.despawn_dynamic(child_id)
		else:
			npc.queue_free()
	active_minions.clear()
	current_wave = 0


## Spawn the next wave, or finish. Called on begin and after each clear.
func _advance() -> void:
	if not _running:
		return
	if current_wave >= WAVES.size():
		_finish()
		return
	current_wave += 1
	_spawn_wave(WAVES[current_wave - 1])
	wave_started.emit(current_wave, WAVES.size())


func _spawn_wave(spec: Array) -> void:
	var map: Map = Map.of(self)
	var container: ReplicatedPropsContainer = map.replicated_props_container if map != null else null
	if container == null:
		push_warning("MinionWaveManager: no ReplicatedPropsContainer — cannot spawn wave.")
		return

	var slot: int = 0
	for entry: Array in spec:
		var slug: StringName = entry[0]
		var count: int = int(entry[1])
		for i: int in count:
			var at: Vector2 = _spawn_point(slot)
			slot += 1
			var node: Node = container.spawn_dynamic(
				ReplicatedPropsContainer.SCENE_HOSTILE_NPC,
				container.to_local(at),
				{"enemy_type_slug": slug}
			)
			var npc: HostileNpc = node as HostileNpc
			if npc == null:
				continue
			# Single-life: the gauntlet must not repopulate itself behind the
			# group, and only a non-respawning body despawns (and so fires
			# tree_exited) when it dies.
			npc.respawns = false
			npc.max_distance_from_spawn = HostileNpc.NO_LEASH_DISTANCE
			_scale_body(npc)
			npc.replicate_visual(&"rp_spawn_effect", [])
			active_minions.append(npc)
			# The bind is what makes the handler usable: by the time tree_exited
			# runs, the node is already out of the tree and cannot be found from
			# the signal alone.
			npc.tree_exited.connect(_on_minion_exited.bind(npc))


## Apply the wave difficulty multipliers to one freshly spawned body. HEALTH is
## raised through both the current and max stat so the body spawns at full.
func _scale_body(npc: HostileNpc) -> void:
	if minion_health_mult != 1.0:
		var hp_max: float = npc.stats_component.get_stat(Stat.HEALTH_MAX) * minion_health_mult
		npc.stats_component.set_stat(Stat.HEALTH_MAX, hp_max)
		npc.stats_component.set_stat(Stat.HEALTH, hp_max)
	if minion_damage_mult != 1.0:
		npc.damage_dealt_mult = minion_damage_mult


## Position for the [param slot]-th body of a wave: round-robin across the
## markers with a deterministic ring offset, so bodies never stack exactly on
## each other (which reads as one mob and breaks Y-sorting).
func _spawn_point(slot: int) -> Vector2:
	var base: Vector2 = global_position
	var marker_count: int = spawn_markers.size()
	if marker_count > 0:
		var marker: Marker2D = spawn_markers[slot % marker_count]
		if marker != null and is_instance_valid(marker):
			base = marker.global_position
	var ring: int = slot / maxi(1, marker_count)
	if ring <= 0:
		return base
	var angle: float = float(slot) * TAU * 0.381966  # golden angle — no clumping
	return base + Vector2.RIGHT.rotated(angle) * (SPAWN_SPREAD_PX * float(ring))


## A body has LEFT THE TREE — the only event that means it is really gone.
## This is the gate the brief specifies: the wave advances (and, on the last
## wave, the return teleport fires) only when `active_minions.size() == 0`.
func _on_minion_exited(npc: HostileNpc) -> void:
	active_minions.erase(npc)
	# Teardown, a wipe, or a reset already stood the gauntlet down: the bodies
	# leaving are cleanup, not progress.
	if not _running or _finished:
		return
	if active_minions.size() > 0:
		return

	wave_cleared.emit(current_wave, WAVES.size())
	if current_wave >= WAVES.size():
		_finish()
		return
	# Breathing room before the next wave. The _running re-check after the await
	# is what stops a group that left during the gap from spawning a wave into
	# an empty room.
	await get_tree().create_timer(WAVE_GAP_S).timeout
	if not _running:
		return
	_advance()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	await get_tree().create_timer(RETURN_DELAY_S).timeout
	if not _running:
		return
	_running = false
	all_waves_cleared.emit()
