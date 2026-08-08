class_name TheHollowMap
extends Map
## Boss arena for the Mecha-stone Golem. The golem is spawned dynamically on the
## server (same path as world bosses / dungeon bosses) so clients receive a real
## spawn op + prop id — a static scene child kept freezing on clients even after
## bake fixes because its sync id never resolved reliably across instance charge.


const GOLEM_SLUG: StringName = &"mecha_stone_golem"
## Arena center — matches the old static placement in the_hollow.tscn.
const GOLEM_SPAWN: Vector2 = Vector2(464, 240)


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint() or not multiplayer.is_server():
		return
	# Deferred: ReplicatedPropsContainer must finish enter_tree bake first.
	call_deferred(&"_spawn_golem")


func _spawn_golem() -> void:
	if replicated_props_container == null:
		push_error("TheHollowMap: missing replicated_props_container — golem not spawned.")
		return
	for child: Node in replicated_props_container.get_children():
		var existing: HostileNpc = child as HostileNpc
		if existing != null and existing.enemy_type == GOLEM_SLUG:
			return
	var boss: HostileNpc = replicated_props_container.spawn_dynamic(
		ReplicatedPropsContainer.SCENE_HOSTILE_NPC,
		GOLEM_SPAWN,
		{"enemy_type_slug": GOLEM_SLUG}
	) as HostileNpc
	if boss == null:
		push_error("TheHollowMap: failed to spawn Mecha-stone Golem.")
