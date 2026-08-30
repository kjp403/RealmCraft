class_name ColdDebuffController
extends Node
## Phase 3 "Killing Cold": a distance-driven stacking chill that forces the group
## to break off and warm at a brazier instead of standing on the boss.
##
## The loop is a [Timer] tick (not `_process`) on purpose. The mechanic is a
## once-every-half-second question — "are you near a fire?" — and running it per
## frame would do the same distance work 120x more often for identical gameplay,
## on the server, for every player in the instance.
##
## SLOW BOOKKEEPING — the subtle part. The obvious implementation, calling
## [method BuffService.apply] with a negative MOVE_SPEED each tick (what
## melee_arc's slow does), is WRONG here for two reasons: the chill's magnitude
## changes as stacks build, so each new magnitude appends ANOTHER buff entry and
## the slows compound into a full stop; and [method BuffService.clear_stat] —
## the only way to undo that — would also strip the Conjured Ward's movement
## buff, which the brief explicitly requires to survive into phase 3. So this
## controller owns its chill delta directly, per player, and only ever applies
## the DIFFERENCE between the slow a player should have and the slow it has
## already given them. That makes the debuff exactly revertible on any exit path
## (phase end, death, disconnect, wipe) and leaves every other buff untouched.

## How often the proximity question is asked.
const TICK_S: float = 0.5
## Stacks at which the cold starts doing damage. Below this it is only a slow,
## so a player who is simply moving between safe spots is never punished.
const DAMAGE_THRESHOLD: int = 4
## Hard cap. At max stacks a player is at MAX_STACKS * SLOW_PER_STACK slower and
## taking the full tick — there is no death spiral past this point, so a rescue
## is always physically possible.
const MAX_STACKS: int = 10
## Flat MOVE_SPEED removed per stack (base move speed is 112.5, so 10 stacks is
## a ~62% reduction — crippling but never a full stop).
const SLOW_PER_STACK: float = 7.0
## Damage per tick once past the threshold, multiplied by stacks over it.
const DAMAGE_PER_STACK: float = 9.0
## Stacks shed per tick while standing in the warmth. Faster than they build, so
## a warm-up is a short trip and not a second job.
const WARM_RECOVERY: int = 2

## Braziers that count as warmth. Populated by the arena from the scene's
## FireSources group; a source that is extinguished can simply be removed here.
var fire_sources: Array[Node2D] = []
## How close counts as warm. Generous enough to hold two or three players at one
## brazier so the "huddle" reads, tight enough that it is a real commitment.
var warmth_radius: float = 96.0
## Attributed as the damage source, so the death log reads as the boss.
var boss: HostileNpc = null

## Per-player chill state, keyed by instance id:
##   { stacks: int, applied: float }  — `applied` is the NEGATIVE MOVE_SPEED
##   delta this controller has already handed that player.
var _chill: Dictionary = {}
var _timer: Timer = null
var _running: bool = false


func _ready() -> void:
	_timer = Timer.new()
	_timer.name = "ColdTick"
	_timer.wait_time = TICK_S
	_timer.one_shot = false
	_timer.timeout.connect(_tick)
	add_child(_timer)


## Begin the cold. Idempotent.
func begin() -> void:
	if _running or not GameMode.is_world_server():
		return
	_running = true
	_chill.clear()
	_timer.start()


## End the cold and hand every player their movement speed back. MUST be called
## on every exit from phase 3 — including a wipe and an instance teardown — or a
## player carries the slow out of the encounter.
func stop() -> void:
	_running = false
	if _timer != null:
		_timer.stop()
	for id: int in _chill.keys():
		var player: Player = instance_from_id(id) as Player
		if player != null and is_instance_valid(player):
			_set_slow(player, id, 0.0)
	_chill.clear()


## Live chill stacks for [param player] (0 when clean). Read by the HUD push.
func stacks_of(player: Player) -> int:
	return int(_chill.get(player.get_instance_id(), {}).get("stacks", 0))


func _tick() -> void:
	if not _running:
		return
	var players: Array[Player] = _live_players()

	# Drop state for anyone who died or left, refunding their slow first. Without
	# this the dictionary grows for the life of the instance and a player who
	# respawns keeps a phantom delta we would never revert.
	for id: int in _chill.keys():
		var known: Player = instance_from_id(id) as Player
		if known == null or not is_instance_valid(known) or known.is_dead or not players.has(known):
			if known != null and is_instance_valid(known):
				_set_slow(known, id, 0.0)
			_chill.erase(id)

	for player: Player in players:
		_tick_player(player)


func _tick_player(player: Player) -> void:
	var id: int = player.get_instance_id()
	var entry: Dictionary = _chill.get(id, {"stacks": 0, "applied": 0.0})
	var warm: bool = _distance_to_nearest_fire(player) <= warmth_radius

	var stacks: int = int(entry["stacks"])
	if warm:
		stacks = maxi(0, stacks - WARM_RECOVERY)
	else:
		stacks = mini(MAX_STACKS, stacks + 1)
	entry["stacks"] = stacks
	_chill[id] = entry

	_set_slow(player, id, float(stacks) * SLOW_PER_STACK)

	# "Hard to breathe": damage only past the threshold, and it ramps, so the
	# longer someone ignores the braziers the sharper the warning gets.
	if stacks >= DAMAGE_THRESHOLD:
		var over: int = stacks - DAMAGE_THRESHOLD + 1
		var amount: float = DAMAGE_PER_STACK * float(over)
		player.take_damage(amount, boss, CombatHit.DAMAGE_MAGIC)

	_push_hud(player, stacks, warm)


## THE proximity check the mechanic is built on. Returns the distance to the
## closest live fire source, or INF when there are none (which reads as "nowhere
## is warm" — every player chills, which is the correct failure mode if the
## braziers are ever all destroyed).
func _distance_to_nearest_fire(player: Player) -> float:
	var best: float = INF
	for source: Node2D in fire_sources:
		if source == null or not is_instance_valid(source):
			continue
		# An EXTINGUISHED brazier is not warmth. This is the whole point of the
		# phase-3 cycle: the safe spots move, so a group cannot pick one fire at
		# the start of the phase and stand on it until the boss dies. A fire that
		# is out reads as absent here — the same way a destroyed one would.
		if source is Campfire and not (source as Campfire).lit:
			continue
		var d: float = player.global_position.distance_to(source.global_position)
		if d < best:
			best = d
	return best


## Move [param player]'s chill slow to exactly [param target] (a positive
## magnitude), applying only the delta. Passing 0.0 fully reverts.
func _set_slow(player: Player, id: int, target: float) -> void:
	var entry: Dictionary = _chill.get(id, {"stacks": 0, "applied": 0.0})
	var applied: float = float(entry["applied"])
	var delta: float = target - applied
	if is_zero_approx(delta):
		return
	# Negative because a chill REMOVES move speed.
	player.stats_component.modify_stat(Stat.MOVE_SPEED, -delta)
	entry["applied"] = target
	if _chill.has(id):
		_chill[id] = entry


## Per-player HUD push: the frost meter and the warmth prompt. Sent every tick
## while the phase runs so a client that joined late or reconnected is correct
## within half a second without any handshake.
func _push_hud(player: Player, stacks: int, warm: bool) -> void:
	if WorldServer.curr == null or player.player_resource == null:
		return
	var peer_id: int = int(player.player_resource.current_peer_id)
	if peer_id <= 0:
		return
	WorldServer.curr.data_push.rpc_id(peer_id, &"ossuran.chill", {
		"stacks": stacks,
		"max": MAX_STACKS,
		"warm": warm,
		"hurting": stacks >= DAMAGE_THRESHOLD,
	})


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
