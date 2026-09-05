extends SceneTree
## Headless gate for the relog-refill exploit: draining a gather node used to be
## forgotten as soon as its ServerInstance was swept (~20s after the last player
## left the zone), so logging out and back in handed the player a full pool.
##
##   godot --headless --path . -s tools/verify_gather_persistence.gd
##
## Exercises [GatherNodeLedger] against a REAL node resource and drives the
## state through the same save_state/load_state boundary that world_store_sqlite
## writes to the players row, because that round trip IS the relog.
##
## Expect: VERIFY_PASS

const VEIN: String = "res://source/common/gameplay/maps/components/mineable_nodes/astralite_vein.tres"
const HERB: String = "res://source/common/gameplay/maps/components/mineable_nodes/healing_herb.tres"

var _fails: PackedStringArray = PackedStringArray()


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok   %s" % label)
	else:
		_fails.append(label)
		print("  FAIL %s" % label)


## The relog: everything the server keeps about this character goes through JSON
## and comes back on a brand-new resource, exactly as it would via the DB row.
func _relog(from: PlayerResource) -> PlayerResource:
	var wire: String = JSON.stringify(GatherNodeLedger.save_state(from))
	var to := PlayerResource.new()
	GatherNodeLedger.load_state(to, JSON.parse_string(wire))
	return to


func _init() -> void:
	var vein: MineableNodeResource = load(VEIN) as MineableNodeResource
	var herb: MineableNodeResource = load(HERB) as MineableNodeResource
	if vein == null or herb == null:
		print("VERIFY_FAIL could not load node resources")
		quit(1)
		return

	var key: String = GatherNodeLedger.node_key("starfall_mining_cave", ^"Nodes/AstraliteVein3")

	print("[key is stable and zone-scoped]")
	_check(
		key == GatherNodeLedger.node_key("starfall_mining_cave", ^"Nodes/AstraliteVein3"),
		"same zone + path produces the same key"
	)
	_check(
		key != GatherNodeLedger.node_key("woodland", ^"Nodes/AstraliteVein3"),
		"the same path in another zone is a different node"
	)

	print("[draining survives a relog]")
	var p := PlayerResource.new()
	var pool: int = GatherNodeLedger.pool(p, key, vein)
	_check(
		pool >= vein.min_charges and pool <= vein.max_charges,
		"fresh pool rolls inside %d-%d (got %d)" % [vein.min_charges, vein.max_charges, pool]
	)
	for i: int in range(pool):
		GatherNodeLedger.consume(p, key, vein)
	_check(GatherNodeLedger.charges(p, key, vein) == 0, "pool reads empty after mining it out")

	var after: PlayerResource = _relog(p)
	_check(
		GatherNodeLedger.charges(after, key, vein) == 0,
		"STILL EMPTY after a relog — this is the exploit that was fixed"
	)
	_check(
		GatherNodeLedger.pool(after, key, vein) == pool,
		"the rolled pool size survives too, so the client's n/max stays honest"
	)

	print("[a partly drained pool survives with the right count]")
	var q := PlayerResource.new()
	var qpool: int = GatherNodeLedger.pool(q, key, vein)
	GatherNodeLedger.consume(q, key, vein)
	GatherNodeLedger.consume(q, key, vein)
	var q2: PlayerResource = _relog(q)
	_check(
		GatherNodeLedger.charges(q2, key, vein) == qpool - 2,
		"two charges spent, %d left after relog" % (qpool - 2)
	)

	print("[the respawn timer runs on wall clock, so it ticks while offline]")
	var r := PlayerResource.new()
	var rpool: int = GatherNodeLedger.pool(r, key, vein)
	for i: int in range(rpool):
		GatherNodeLedger.consume(r, key, vein)
	# Back-date the depletion to one second short of the respawn, then past it.
	var now: int = int(Time.get_unix_time_from_system())
	var e: Dictionary = r.gather_nodes[key]
	e["t"] = now - int(vein.depleted_recharge_seconds) + 2
	_check(
		GatherNodeLedger.charges(r, key, vein) == 0,
		"still empty just before %ds have passed" % int(vein.depleted_recharge_seconds)
	)
	e["t"] = now - int(vein.depleted_recharge_seconds) - 1
	_check(
		GatherNodeLedger.charges(r, key, vein) > 0,
		"refilled once the respawn window elapsed"
	)
	# And the same across the relog boundary, which is the offline case.
	var s := PlayerResource.new()
	var spool: int = GatherNodeLedger.pool(s, key, vein)
	for i: int in range(spool):
		GatherNodeLedger.consume(s, key, vein)
	(s.gather_nodes[key] as Dictionary)["t"] = now - int(vein.depleted_recharge_seconds) - 1
	var s2: PlayerResource = _relog(s)
	_check(
		GatherNodeLedger.charges(s2, key, vein) > 0,
		"a pool that timed out while logged out comes back full"
	)

	print("[a clock that jumps backwards does not freeze a pool]")
	var b := PlayerResource.new()
	var bpool: int = GatherNodeLedger.pool(b, key, vein)
	for i: int in range(bpool):
		GatherNodeLedger.consume(b, key, vein)
	(b.gather_nodes[key] as Dictionary)["t"] = now + 86_400
	GatherNodeLedger.charges(b, key, vein)
	_check(
		int((b.gather_nodes[key] as Dictionary)["t"]) <= now + 1,
		"a future stamp is pulled back to now instead of stalling for a day"
	)

	print("[trickle regen still works on fixed-pool nodes]")
	# Herbs ship with the random pool too, so build a fixed-pool variant to cover
	# the other branch rather than asserting on a path nothing ships.
	var fixed: MineableNodeResource = herb.duplicate()
	fixed.min_charges = 0
	fixed.max_charges = 10
	fixed.charge_regen_seconds = 12.0
	var f := PlayerResource.new()
	var fkey: String = GatherNodeLedger.node_key("woodland", ^"Nodes/Herb1")
	GatherNodeLedger.consume(f, fkey, fixed)
	GatherNodeLedger.consume(f, fkey, fixed)
	_check(GatherNodeLedger.charges(f, fkey, fixed) == 8, "8 of 10 left after two picks")
	(f.gather_nodes[fkey] as Dictionary)["t"] = now - 25
	_check(
		GatherNodeLedger.charges(f, fkey, fixed) == 10,
		"two 12s intervals trickle it back to full"
	)

	print("[a full pool is not written to the row]")
	var u := PlayerResource.new()
	GatherNodeLedger.charges(u, key, vein) # touch it without draining
	_check(
		GatherNodeLedger.save_state(u).is_empty(),
		"an untouched node stores nothing — it is the same state as a full one"
	)

	print("[the ledger cannot grow without bound]")
	var big := PlayerResource.new()
	for i: int in range(GatherNodeLedger.MAX_ENTRIES + 120):
		var k: String = GatherNodeLedger.node_key("woodland", NodePath("Nodes/Rock%d" % i))
		GatherNodeLedger.consume(big, k, vein)
		(big.gather_nodes[k] as Dictionary)["t"] = now + i
	GatherNodeLedger.trim(big)
	_check(
		big.gather_nodes.size() == GatherNodeLedger.MAX_ENTRIES,
		"trimmed to the %d-entry cap (was %d)" % [
			GatherNodeLedger.MAX_ENTRIES, GatherNodeLedger.MAX_ENTRIES + 120
		]
	)
	_check(
		big.gather_nodes.has(GatherNodeLedger.node_key(
			"woodland", NodePath("Nodes/Rock%d" % (GatherNodeLedger.MAX_ENTRIES + 119))
		)),
		"the newest entry is the one kept"
	)

	if _fails.is_empty():
		print("VERIFY_PASS gather_persistence")
		quit(0)
	else:
		print("VERIFY_FAIL (%d)" % _fails.size())
		for line: String in _fails:
			print("  - ", line)
		quit(1)
