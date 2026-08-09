class_name TheHollowMap
extends Map
## Boss arena for the Mecha-stone Golem.
##
## The golem is a STATIC HostileNPC under ReplicatedPropsContainer (same pattern
## as FungalHeart in fungus_cave). Dynamic-only spawn was unreliable across
## instance charge / client bootstrap; baked static IDs sync every join.


const GOLEM_NODE: StringName = &"MechaGolem"
const GOLEM_SPAWN: Vector2 = Vector2(472, 296)


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	if not GameMode.is_world_server():
		return
	call_deferred(&"_ensure_golem_brain")


## Server-only: guarantee the scene-placed boss has a named BossController.
func _ensure_golem_brain() -> void:
	if replicated_props_container == null:
		replicated_props_container = get_node_or_null(^"ReplicatedPropsContainer") as ReplicatedPropsContainer
	if replicated_props_container == null:
		push_error("TheHollowMap: missing ReplicatedPropsContainer.")
		return
	var boss: HostileNpc = replicated_props_container.get_node_or_null(NodePath(GOLEM_NODE)) as HostileNpc
	if boss == null:
		# Safety net if the scene child was deleted — spawn once like world boss.
		boss = replicated_props_container.spawn_dynamic(
			ReplicatedPropsContainer.SCENE_HOSTILE_NPC,
			GOLEM_SPAWN,
			{"enemy_type_slug": &"mecha_stone_golem", "position": GOLEM_SPAWN}
		) as HostileNpc
		if boss == null:
			push_error("TheHollowMap: MechaGolem missing and dynamic spawn failed.")
			return
		boss.name = String(GOLEM_NODE)
		print("TheHollowMap: dynamic fallback spawned MechaGolem at %s" % str(GOLEM_SPAWN))
	for child: Node in boss.get_children():
		if child is BossController:
			return
	var brain: BossController = BossController.new()
	brain.name = "BossController"
	brain.boss = boss
	boss.add_child(brain)
	print("TheHollowMap: BossController attached to MechaGolem at %s" % str(boss.position))
