class_name TheHollowMap
extends Map
## Boss arena for the Mecha-stone Golem. The golem is spawned dynamically on the
## server (same path as world bosses / dungeon bosses) so clients receive a real
## spawn op + prop id — a static scene child kept freezing on clients even after
## bake fixes because its sync id never resolved reliably across instance charge.


const GOLEM_SLUG: StringName = &"mecha_stone_golem"
## Arena boss pad center (matches BossPad / BossLight in the_hollow.tscn).
const GOLEM_SPAWN: Vector2 = Vector2(472, 296)


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	# Dedicated world + listen-server both count; prefer GameMode so a late
	# multiplayer peer flip can't skip the spawn.
	if not GameMode.is_world_server() and not multiplayer.is_server():
		return
	call_deferred(&"_spawn_golem")


func _spawn_golem() -> void:
	if replicated_props_container == null:
		replicated_props_container = get_node_or_null(^"ReplicatedPropsContainer") as ReplicatedPropsContainer
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
		push_error("TheHollowMap: failed to spawn Mecha-stone Golem (slug '%s')." % GOLEM_SLUG)
		return
	# Attach a named brain up-front (same as EventService / RoomNode) so
	# HostileNPC._ensure_boss_brain does not double-attach.
	var has_brain: bool = false
	for child: Node in boss.get_children():
		if child is BossController:
			has_brain = true
			break
	if not has_brain:
		var brain: BossController = BossController.new()
		brain.name = "BossController"
		brain.boss = boss
		boss.add_child(brain)
	# common/ can't reference ServerLog (server tree is stripped from clients).
	print("TheHollowMap: spawned Mecha-stone Golem at %s" % str(GOLEM_SPAWN))
