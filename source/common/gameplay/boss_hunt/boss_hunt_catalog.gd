class_name BossHuntCatalog
## The huntable-boss roster: every BossHuntTarget .tres under
## boss_hunt/targets/, scanned once and cached. Adding a boss to the mode is a
## data drop into that folder — no code change, same shape as the instance
## collection scan in InstanceManager.set_instance_collection.

const TARGETS_PATH: String = "res://source/common/gameplay/boss_hunt/targets/"

## contract_id -> BossHuntTarget. Empty until the first _scan().
static var _by_id: Dictionary[StringName, BossHuntTarget] = {}
## Cheapest-first, so the contract board reads as a ladder.
static var _ordered: Array[BossHuntTarget] = []
static var _scanned: bool = false


## Every valid target, cheapest first.
static func all() -> Array[BossHuntTarget]:
	_scan()
	return _ordered


## One target by its contract id, or null.
static func find(contract_id: StringName) -> BossHuntTarget:
	_scan()
	return _by_id.get(contract_id, null)


## Client/server payload rows for the contract board.
static func to_payload() -> Array:
	var out: Array = []
	for target: BossHuntTarget in all():
		out.append({
			"id": String(target.contract_id()),
			"name": target.title(),
			"description": target.description,
			"cost": target.cost,
			"level": target.recommended_level,
			"respawn_s": target.respawn_delay_s,
			# Surfaced so the board can state the trade-off outright rather than
			# letting players discover the XP cut by feel after they've paid.
			"xp_pct": roundi(target.xp_mult * 100.0),
			"hp_solo": roundi(target.party_health(1)),
			"hp_full": roundi(target.party_health(BossHuntService.PARTY_SIZE)),
		})
	return out


static func _scan() -> void:
	if _scanned:
		return
	_scanned = true
	for file_path: String in FileUtils.get_all_file_at(TARGETS_PATH, "*.tres"):
		if not file_path.ends_with(".tres"):
			continue
		# Untyped load: in exports the custom-class loader may not be registered
		# when this scan first runs, and a "BossHuntTarget" hint would trip the
		# resource loader. Same reason as the instance-collection scan.
		var loaded: Resource = ResourceLoader.load(file_path)
		if loaded == null or not (loaded is BossHuntTarget):
			continue
		var target: BossHuntTarget = loaded
		if target.enemy_type == null:
			push_warning("BossHuntTarget '%s' has no enemy_type — skipped." % file_path)
			continue
		var id: StringName = target.contract_id()
		if id.is_empty() or _by_id.has(id):
			continue
		_by_id[id] = target
		_ordered.append(target)
	_ordered.sort_custom(func(a: BossHuntTarget, b: BossHuntTarget) -> bool: return a.cost < b.cost)
