@tool
extends SceneTree
## Read-only check that the Skeletons Slayer task is completable OUTSIDE the
## Dark Cave: the three cave_* archetypes load, carry registry slugs, are listed
## on the task, and are actually spawned in the Mining Cave scene.
##
## Also holds the line on the Mining Cave being SKILLER-SAFE — every hostile in
## it must stay chase_on_area=false so a player mining veins is never auto-aggroed
## (see HostileNpc._find_targets). Skeletons pack-assist when one is attacked,
## which is deliberate: that only fires once the player swings first.
##
##   godot --headless --path . -s tools/verify_skeleton_overworld.gd

const TASK: String = "res://source/common/gameplay/slayer/tasks/skeletons.tres"
const MAP: String = "res://source/common/gameplay/maps/maps/mining_cave/mining_cave.tscn"
const OVERWORLD: Array[StringName] = [&"cave_skeleton", &"cave_skeleton_warrior", &"cave_skeleton_rogue"]

var _failures: int = 0


func _init() -> void:
	var task: SlayerTaskDef = ResourceLoader.load(TASK) as SlayerTaskDef
	if task == null:
		_fail("could not load %s" % TASK)
		_finish()
		return

	for slug: StringName in OVERWORLD:
		var res: EnemyTypeResource = ContentRegistryHub.load_by_slug(&"enemy_types", slug) as EnemyTypeResource
		if res == null:
			_fail("'%s' does not resolve through the enemy_types registry" % slug)
			continue
		if res.enemy_type != slug:
			_fail("'%s' enemy_type is '%s' — kill credit keys off enemy_type, so they must match" % [slug, res.enemy_type])
		if not task.matches(slug):
			_fail("'%s' is not listed on the Skeletons task" % slug)
		if res.max_health < 400.0:
			_fail("'%s' has %.0f HP — below overworld tier, these are not dungeon-multiplied" % [slug, res.max_health])
		if not res.respawns:
			_fail("'%s' does not respawn — an overworld task target must" % slug)
		if not res.leashes:
			_fail("'%s' does not leash — dungeon-only behavior" % slug)

	_check_skiller_safe()

	var counts: Dictionary[StringName, int] = _spawn_counts()
	var total: int = 0
	for slug: StringName in OVERWORLD:
		var n: int = counts.get(slug, 0)
		total += n
		if n == 0:
			_fail("'%s' has no spawner in the Mining Cave" % slug)
		else:
			print("  %s x%d" % [slug, n])
	if total < 6:
		_fail("only %d overworld skeletons spawn — too thin to serve a task" % total)

	print("task '%s' now matches %d enemy types" % [task.display_name, task.enemy_types.size()])
	_finish()


## Every distinct archetype spawned in the Mining Cave must be passive. A skiller
## stood at a vein shares the floor with these, so auto-aggro would make the zone
## unusable for its primary purpose.
func _check_skiller_safe() -> void:
	for data: EnemyTypeResource in _spawned_types():
		if data.chase_on_area:
			_fail("'%s' has chase_on_area=true — it would auto-aggro skillers in the Mining Cave" % data.enemy_type)
		else:
			print("  passive: %s" % data.enemy_type)


## enemy_type slug -> number of spawner nodes in the Mining Cave scene.
func _spawn_counts() -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = {}
	for data: EnemyTypeResource in _spawned_types(false):
		out[data.enemy_type] = out.get(data.enemy_type, 0) + 1
	return out


## Every EnemyTypeResource attached to a spawner in the Mining Cave. [param unique]
## collapses repeats, so callers that care about archetypes rather than head-count
## check each type once.
func _spawned_types(unique: bool = true) -> Array[EnemyTypeResource]:
	var out: Array[EnemyTypeResource] = []
	var seen: Dictionary[StringName, bool] = {}
	var packed: PackedScene = ResourceLoader.load(MAP) as PackedScene
	if packed == null:
		_fail("could not load %s" % MAP)
		return out
	var state: SceneState = packed.get_state()
	for i: int in state.get_node_count():
		for p: int in state.get_node_property_count(i):
			if state.get_node_property_name(i, p) != &"enemy_data":
				continue
			var data: EnemyTypeResource = state.get_node_property_value(i, p) as EnemyTypeResource
			if data == null:
				continue
			if unique:
				if seen.has(data.enemy_type):
					continue
				seen[data.enemy_type] = true
			out.append(data)
	return out


func _fail(msg: String) -> void:
	printerr("FAIL: ", msg)
	_failures += 1


func _finish() -> void:
	if _failures > 0:
		printerr("%d check(s) failed" % _failures)
		quit(1)
		return
	print("OK — Skeletons is completable in the open world")
	quit(0)
