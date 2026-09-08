extends Node
## Regression gate for "my arrow died on a dropped item".
##
## A projectile's shape query masks HURTBOX + FLAG. Anything else parked on one of
## those two layers reads to CombatHit.try_damage as "a solid body that isn't a
## combatant" and comes back BLOCKED — the shot stops dead on it. Every node that
## belongs there (HurtBox, DeflectBubble, TerritoryFlag) assigns its layer in CODE
## from a PhysicsLayers const, so a SCENE hard-coding one of them is always a
## mistake. WORLD is deliberately not audited: a scene-authored world collider is
## a wall, and stopping shots is what a wall is for.
##
## It is a mistake that shipped: the collectibles wrote `collision_layer = 4`
## meaning "layer 4, pickup" — Godot wanted the BIT (8), so every coin, ground
## item and loot chest sat on layer 3, hurtbox, the exact layer arrows and bolts
## hunt for. Nothing errored; ranged combat just quietly died on the loot it had
## earned. This audit is the thing that says so out loud.
##   godot --path . --mode=client res://tools/audit_projectile_blockers.tscn

const SCAN_ROOT: String = "res://source"

## The layers a projectile's shape query hunts for. Owned by code, never by a
## scene — see the header.
const CODE_OWNED: int = PhysicsLayers.HURTBOX | PhysicsLayers.FLAG

## Scenes whose collectible root must be on PICKUP and nothing else. Named
## explicitly (not just "not sensitive") so a future edit that parks them on some
## other borrowed layer is caught too.
const PICKUPS: PackedStringArray = [
	"res://source/common/gameplay/maps/props/collectibles/coin.tscn",
	"res://source/common/gameplay/maps/props/collectibles/ground_item.tscn",
	"res://source/common/gameplay/maps/props/collectibles/loot_chest.tscn",
]

var _failures: int = 0


func _ready() -> void:
	print("=== projectile blocker audit ===")
	_audit_scene_layers()
	_audit_pickup_layer()
	print("")
	if _failures == 0:
		print("PASS — nothing unexpected sits where a projectile looks.")
	else:
		print("FAIL — %d problem(s)." % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


## Every .tscn under source/, read as TEXT (not instantiated — a map scene costs
## seconds to build and we only need the authored numbers). Flags any node whose
## hard-coded collision_layer overlaps a layer projectiles react to.
func _audit_scene_layers() -> void:
	print("\n-- hard-coded combat layers in scenes --")
	var hits: int = 0
	for path: String in _scenes(SCAN_ROOT):
		var text: String = FileAccess.get_file_as_string(path)
		if text.is_empty():
			continue
		var node: String = "?"
		for raw: String in text.split("\n"):
			var line: String = raw.strip_edges()
			if line.begins_with("[node name="):
				node = line
			if not line.begins_with("collision_layer = "):
				continue
			var layer: int = line.trim_prefix("collision_layer = ").to_int()
			if (layer & CODE_OWNED) == 0:
				continue
			hits += 1
			_failures += 1
			printerr("  %s\n    %s\n    collision_layer = %d overlaps %s" % [
				path, node, layer, _role_names(layer & CODE_OWNED)
			])
	if hits == 0:
		print("  clean (hurtbox / flag are assigned in code, from PhysicsLayers)")


## The three collectible scenes, instantiated for real, so this checks the layer
## the engine actually gives the node — not the text we hope it parses to.
func _audit_pickup_layer() -> void:
	print("\n-- collectibles on the pickup layer --")
	for path: String in PICKUPS:
		var scene: PackedScene = load(path) as PackedScene
		if scene == null:
			_failures += 1
			printerr("  %s — will not load" % path)
			continue
		var node: CollisionObject2D = scene.instantiate() as CollisionObject2D
		if node == null:
			_failures += 1
			printerr("  %s — root is not a CollisionObject2D" % path)
			continue
		var layer: int = node.collision_layer
		node.free()
		if layer == PhysicsLayers.PICKUP:
			print("  ok   %s (layer %d)" % [path.get_file(), layer])
		else:
			_failures += 1
			printerr("  FAIL %s — collision_layer = %d, expected %d (pickup). %s" % [
				path.get_file(), layer, PhysicsLayers.PICKUP,
				"Overlaps " + _role_names(layer & CODE_OWNED) if (layer & CODE_OWNED) != 0 else "",
			])


func _role_names(mask: int) -> String:
	var out: PackedStringArray = []
	if (mask & PhysicsLayers.HURTBOX) != 0:
		out.append("hurtbox")
	if (mask & PhysicsLayers.FLAG) != 0:
		out.append("flag")
	return ", ".join(out)


static func _scenes(dir_path: String, out: PackedStringArray = []) -> PackedStringArray:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var full: String = dir_path.path_join(name)
		if dir.current_is_dir():
			_scenes(full, out)
		elif name.ends_with(".tscn"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return out
