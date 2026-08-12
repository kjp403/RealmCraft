class_name PickArc
extends Area2D
## Pickaxe / sickle / axe / rod swing hitbox. Harvest-only:
## - MineableNode areas → register_gather_hit (the actual gather).
## - Never queries HurtBoxes / flags / combatants — tools are not weapons.
##   (PickSwingAbility also forces character_damage = 0 as defense in depth.)
##
## One swing gathers from at most ONE MineableNode (the nearest to the player).
## Without that, two veins under the arc both take extraction damage and award
## XP in the same swing — unacceptable when nodes sit near each other.
##
## Server-only extraction; clients spawn the same scene for visual feedback
## but the gates keep effects server-side.


@export var lifetime: float = 0.2

## Legacy field — gather tools always leave this at 0. Kept so old call sites
## that assign it stay compatible; combat path is skipped when <= 0.
var character_damage: float = 0.0
## Extraction damage per swing to MineableNodes (wooden = 1, iron = 2, …).
var extraction_damage: int = 1
## Which tool this swing represents (&"pickaxe", &"sickle", …) — checked against
## a MineableNode's required_tool.
var tool_type: StringName = &"pickaxe"
var source: Character
## Instance ref so register_gather_hit can route the result back to the peer.
var instance: Node

var _gather_candidates: Array[MineableNode] = []
var _gather_applied: bool = false
var _scanned: bool = false


func _ready() -> void:
	# HARVESTABLE only — do NOT widen to combat layers (hurtbox/flag).
	# Overwriting the scene mask with a combat-inclusive mask was why pickaxe
	# swings near bats still called take_damage(0) and pulled aggro.
	collision_mask = PhysicsLayers.HARVESTABLE
	if GameMode.is_world_server():
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
	# are already overlapping when this hitbox spawns. Harvest mask only returns
	# MineableNodes — never NPCs.
	for body: Node2D in CombatHit.overlapping_bodies(self):
		if body is MineableNode:
			_queue_gather(body as MineableNode)
	_apply_nearest_gather()


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
