extends Node
## Prove every biome in the Traveling Peddler's rotation can actually host the cart.
##
## The pool is not a list anyone maintains — PeddlerSites scans the biomes folder,
## so a biome joins the rotation simply by existing. That makes the failure mode
## silent and structural rather than a missing entry: if a map cannot carry a
## dynamic prop, the manager skips it (_skip_biome) and the cart is not where the
## website said it would be, for a whole 30-minute window.
##
## The way a map fails is specific. Map's `replicated_props_container` is a
## Node-typed @export, which stays null unless the scene carries `node_paths=...`;
## map.gd covers that by looking up the conventional child name instead, but that
## only works when the node is BOTH named ReplicatedPropsContainer AND carrying
## replicated_props.gd — a container node with no script casts to null and the
## biome drops out of the rotation. deep_shoals hit exactly that (fixed in
## e2dad166); nothing gated it, so this walks the whole pool the same way the
## manager does: resolve the container, probe a spot, and actually spawn the cart
## and its vault chest.
##   godot --headless --path . --mode=client res://tools/check_peddler_sites.tscn

const BIOMES_DIR: String = "res://source/common/gameplay/maps/instance/instance_collection/biomes/"
## Biomes that must be in the pool. Not the whole pool — that is meant to grow on
## its own — just the ones with a history of falling out of it.
const MUST_INCLUDE: Array[StringName] = [&"pirates_cove"]
## Arbitrary but fixed, so a failure reproduces.
const CYCLE: int = 4711

var _failed: bool = false


func _ready() -> void:
	call_deferred(&"_go")


func _fail(msg: String) -> void:
	push_error(msg)
	print("FAIL  ", msg)
	_failed = true


func _go() -> void:
	var pool: Array[StringName] = PeddlerSites.biome_names()
	print("rotation pool (%d): %s" % [pool.size(), ", ".join(pool)])
	for required: StringName in MUST_INCLUDE:
		if pool.has(required):
			print("ok    %-22s in the rotation pool" % required)
		else:
			_fail("%s is missing from the peddler rotation pool" % required)

	for file_name: String in ResourceLoader.list_directory(BIOMES_DIR):
		if not file_name.ends_with(".tres"):
			continue
		await _check_biome(BIOMES_DIR + file_name)

	print("RESULT ", "FAIL" if _failed else "PASS")
	get_tree().quit(1 if _failed else 0)


func _check_biome(res_path: String) -> void:
	var loaded: Resource = ResourceLoader.load(res_path)
	if loaded == null or not (loaded is InstanceResource):
		_fail("%s does not load as an InstanceResource" % res_path)
		return
	var biome: InstanceResource = loaded as InstanceResource
	var label: String = String(biome.instance_name)

	var packed: PackedScene = load(biome.map_path) as PackedScene
	if packed == null:
		_fail("%s: map_path '%s' does not resolve to a scene" % [label, biome.map_path])
		return
	var map: Node = packed.instantiate()
	add_child(map)
	await get_tree().physics_frame
	await get_tree().physics_frame

	if map is not Map:
		_fail("%s: map root is not a Map" % label)
		map.queue_free()
		return
	# The exact lookup the manager relies on. A container node without the script
	# casts to null here, which is how a biome silently leaves the rotation.
	var container: ReplicatedPropsContainer = (map as Map).replicated_props_container
	if container == null:
		_fail("%s: no ReplicatedPropsContainer (node missing, misnamed, or has no script)" % label)
		map.queue_free()
		return

	var spot: Dictionary = PeddlerSites.pick_spot(map as Map, CYCLE)
	var ok: bool = true
	var ids: Array[int] = []
	for pair: Array in [
		[ReplicatedPropsContainer.SCENE_NPC, "peddler"],
		[ReplicatedPropsContainer.SCENE_PEDDLER_VAULT, "vault"],
	]:
		var node: Node = container.spawn_dynamic(
			pair[0] as int, container.to_local(spot[pair[1] as String])
		)
		if node == null:
			_fail("%s: spawn_dynamic(%s) returned null" % [label, pair[1]])
			ok = false
			continue
		var prop_id: int = container.child_id_of_node(node)
		if prop_id < 0:
			_fail("%s: %s spawned but has no prop id" % [label, pair[1]])
			ok = false
		else:
			ids.append(prop_id)
	if ok:
		print("ok    %-22s container + cart + vault at (%d, %d), prop ids %s" % [
			label, spot["peddler"].x, spot["peddler"].y, ids])
	for prop_id: int in ids:
		container.despawn_dynamic(prop_id)
	map.queue_free()
	await get_tree().process_frame
