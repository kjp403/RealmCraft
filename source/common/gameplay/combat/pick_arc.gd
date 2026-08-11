class_name PickArc
extends Area2D
## Pickaxe / sickle swing hitbox. Hybrid:
## - bodies (players, NPCs, territory flags) → small "tool as weapon" damage via
##   CombatHit, using the SAME deterministic shape query as MeleeArc so a swing
##   lands on still targets (a flag) that enter-events miss.
## - areas (MineableNode) → register_gather_hit (the actual harvest).
##
## One swing gathers from at most ONE MineableNode (the nearest to the player).
## Without that, two veins under the arc both take extraction damage and award
## XP in the same swing — unacceptable when nodes sit near each other.
##
## Server-only damage / extraction; clients spawn the same scene for visual
## feedback but the gates keep effects server-side.


@export var lifetime: float = 0.2

## Damage dealt to Character bodies + flags. Kept low — a tool is a weak weapon.
var character_damage: float = 2.0
## Extraction damage per swing to MineableNodes (wooden = 1, iron = 2, …).
var extraction_damage: int = 1
## Which tool this swing represents (&"pickaxe", &"sickle", …) — checked against
## a MineableNode's required_tool.
var tool_type: StringName = &"pickaxe"
var source: Character
## Instance ref so register_gather_hit can route the result back to the peer.
var instance: Node

var _hit_bodies: Array[Node] = []
var _gather_candidates: Array[MineableNode] = []
var _gather_applied: bool = false
var _scanned: bool = false


func _ready() -> void:
	collision_mask = PhysicsLayers.HARVEST_TARGET_MASK
	if GameMode.is_world_server():
		body_entered.connect(_on_body_entered)
		area_entered.connect(_on_area_entered)
	else:
		set_physics_process(false)

	var t: Timer = Timer.new()
	t.wait_time = lifetime
	t.one_shot = true
	t.timeout.connect(queue_free)
	add_child(t)
	t.start()


func _physics_process(_delta: float) -> void:
	set_physics_process(false)
	if _scanned:
		return
	_scanned = true
	# Deterministic shape query (same as MeleeArc): enter-events miss targets that
	# are already overlapping when this hitbox spawns. Route MineableNode areas to
	# gather; everything else through the weak combat path.
	for body: Node2D in CombatHit.overlapping_bodies(self):
		if body is MineableNode:
			_queue_gather(body as MineableNode)
		else:
			_on_body_entered(body)
	_apply_nearest_gather()


func _on_body_entered(body: Node2D) -> void:
	if body == source:
		return
	if body is MineableNode:
		# Queue only — resolve after the shape scan so we pick the nearest.
		_queue_gather(body as MineableNode)
		if _scanned:
			_apply_nearest_gather()
		return
	if _hit_bodies.has(body):
		return
	_hit_bodies.append(body)
	# Shared target rules (flags, PvP, sparring, guild friendly-fire) via CombatHit.
	CombatHit.try_damage(source if source is Character else null, body, character_damage)


# Backup path when a node walks/enters mid-swing. Primary hits come from the
# shape query in _physics_process. Do not gather here before the scan, or the
# first enter-event would lock a farther vein and skip a nearer one.
func _on_area_entered(area: Area2D) -> void:
	if area is MineableNode:
		_queue_gather(area as MineableNode)
		if _scanned:
			_apply_nearest_gather()


func _queue_gather(node: MineableNode) -> void:
	if node == null or not (source is Player):
		return
	if _gather_candidates.has(node):
		return
	_gather_candidates.append(node)


## Commit extraction to the single nearest overlapping vein/herb/tree. Later
## candidates that arrive mid-swing are ignored once a gather has landed.
func _apply_nearest_gather() -> void:
	if _gather_applied:
		return
	if _gather_candidates.is_empty() or not (source is Player):
		return

	var origin: Vector2 = (source as Node2D).global_position
	var best: MineableNode = null
	var best_d: float = INF
	for node: MineableNode in _gather_candidates:
		if not is_instance_valid(node):
			continue
		var d: float = origin.distance_squared_to(node.global_position)
		if d < best_d:
			best_d = d
			best = node
	if best == null:
		return

	_gather_applied = true
	var result: Dictionary = best.register_gather_hit(
		source as Player, extraction_damage, instance, tool_type
	)
	if result.get("ok", false) or result.has("reason"):
		var peer_id: int = int((source as Player).player_resource.current_peer_id)
		if peer_id > 0 and WorldServer.curr != null:
			WorldServer.curr.data_push.rpc_id(peer_id, &"mining.gather_result", result)
