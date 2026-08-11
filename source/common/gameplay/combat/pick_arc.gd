class_name PickArc
extends Area2D
## Gathering-tool swing hitbox (pickaxe / axe / fishing rod / sickle):
## - areas / overlapping MineableNodes → register_gather_hit (the actual harvest).
## - Characters / flags are ignored — tools are not weapons and must not aggro.
##
## Server-only extraction; clients spawn the same scene for visual feedback.


@export var lifetime: float = 0.2

## Legacy field — gathering tools always deal 0 combat damage.
var character_damage: float = 0.0
## Extraction damage per swing to MineableNodes (wooden = 1, iron = 2, …).
var extraction_damage: int = 1
## Which tool this swing represents (&"pickaxe", &"sickle", …) — checked against
## a MineableNode's required_tool.
var tool_type: StringName = &"pickaxe"
var source: Character
## Instance ref so register_gather_hit can route the result back to the peer.
var instance: Node

var _hit_nodes: Array[Node] = []
var _scanned: bool = false


func _ready() -> void:
	# Harvestables only — do not overlap combat hurtboxes / bodies.
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
	# Deterministic shape query: enter-events miss targets already overlapping
	# when this hitbox spawns. Gather only — never combat-damage.
	for body: Node2D in CombatHit.overlapping_bodies(self):
		if body is MineableNode:
			_try_gather(body as MineableNode)


# Backup path when a node walks/enters mid-swing. Primary hits come from the
# shape query in _physics_process.
func _on_area_entered(area: Area2D) -> void:
	if area is MineableNode:
		_try_gather(area as MineableNode)


func _try_gather(node: MineableNode) -> void:
	if node == null or not (source is Player):
		return
	if _hit_nodes.has(node):
		return
	_hit_nodes.append(node)
	var result: Dictionary = node.register_gather_hit(
		source as Player, extraction_damage, instance, tool_type
	)
	if result.get("ok", false) or result.has("reason"):
		var peer_id: int = int((source as Player).player_resource.current_peer_id)
		if peer_id > 0 and WorldServer.curr != null:
			WorldServer.curr.data_push.rpc_id(peer_id, &"mining.gather_result", result)
