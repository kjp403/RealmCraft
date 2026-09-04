extends SceneTree
## Gate for the boss-set combat bonuses.
##
##     godot --headless --path . -s tools/verify_combat_set_bonus.gd
##
## Prints VERIFY_PASS / VERIFY_FAIL. Checks:
##
##  1. Every piece slug in every set resolves in the generated items index, and
##     is a GearItem (a material cannot be worn, so it can never pay a bonus).
##  2. Every piece is on its boss's loot table AND in that boss's collection log —
##     a set piece that is not a log entry is a bonus nobody is told to chase.
##  3. Tier thresholds are sane: >= 2, <= the set's piece count, and the higher
##     tier is at least as strong as the lower on every stat it shares.
##  4. Tiers do NOT stack — 3 pieces pays the 3-row only.
##  5. The bonus stays modest relative to the pieces' own stats, so a set bonus
##     can never quietly become the reason an early set out-scales endgame gear.

const ITEMS_INDEX: String = "res://source/common/registry/indexes/items_index.tres"
const LOGS_PATH: String = "res://source/common/gameplay/collection_log/logs/"
const BOSS_PATH: String = "res://source/common/gameplay/characters/npc/types/bosses/"
## A set bonus worth more than this fraction of the set's own summed stats is a
## balance smell — the bonus should sweeten the set, not be the set.
const MAX_BONUS_FRACTION: float = 0.35

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	_check_pieces()
	_check_in_logs()
	_check_tiers()
	_check_no_stacking()
	_check_magnitude()
	_check_runtime()
	_check_universal_stats()

	print("")
	if _failures.is_empty():
		print("VERIFY_PASS  (%d checks, %d sets)" % [_checks, CombatSetBonus.SETS.size()])
	else:
		for line: String in _failures:
			printerr("  FAIL: %s" % line)
		print("VERIFY_FAIL  (%d failures / %d checks)" % [_failures.size(), _checks])
	quit(0 if _failures.is_empty() else 1)


## Piece slugs must resolve, and must be wearable.
func _check_pieces() -> void:
	var index: ContentIndex = ResourceLoader.load(ITEMS_INDEX) as ContentIndex
	var by_slug: Dictionary = {}
	for entry: Dictionary in index.entries:
		if entry.has(&"slug"):
			by_slug[StringName(entry[&"slug"])] = String(entry.get(&"path", ""))
	for set_slug: StringName in CombatSetBonus.SETS:
		for piece: Variant in _pieces(set_slug):
			var slug: StringName = StringName(str(piece))
			_checks += 1
			if not by_slug.has(slug):
				_f("%s: piece '%s' is not in the items index" % [set_slug, slug])
				continue
			var gear: GearItem = ResourceLoader.load(by_slug[slug]) as GearItem
			_checks += 1
			if gear == null:
				_f("%s: piece '%s' is not a GearItem — it can never be worn, so "
					% [set_slug, slug] + "the bonus is unreachable")
			elif CombatSetBonus.set_of(slug) != set_slug:
				_f("%s: piece '%s' indexes back to set '%s'"
					% [set_slug, slug, CombatSetBonus.set_of(slug)])


## Every set piece must be an entry in some boss's collection log, and drop from
## that boss. A set bonus hanging off an item the log never mentions is a reward
## with no path to it.
func _check_in_logs() -> void:
	var logged: Dictionary = {}
	for path: String in FileUtils.get_all_file_at(LOGS_PATH, "*.tres"):
		var boss_log: BossCollectionLog = ResourceLoader.load(path) as BossCollectionLog
		if boss_log == null:
			continue
		for slug: StringName in boss_log.log_items:
			logged[slug] = boss_log.boss_id
	var droppable: Dictionary = {}
	for path: String in FileUtils.get_all_file_at(BOSS_PATH, "*.tres"):
		var enemy: EnemyTypeResource = ResourceLoader.load(path) as EnemyTypeResource
		if enemy == null:
			continue
		for drop: LootDrop in enemy.loot:
			if drop != null and drop.item != null:
				droppable[StringName(str(drop.item.get_meta(&"slug", &"")))] = true
	for set_slug: StringName in CombatSetBonus.SETS:
		for piece: Variant in _pieces(set_slug):
			var slug: StringName = StringName(str(piece))
			_checks += 2
			if not logged.has(slug):
				_f("%s: piece '%s' is in no collection log" % [set_slug, slug])
			if not droppable.has(slug):
				_f("%s: piece '%s' drops from no boss" % [set_slug, slug])


func _check_tiers() -> void:
	for set_slug: StringName in CombatSetBonus.SETS:
		var total: int = CombatSetBonus.piece_count(set_slug)
		var tiers: Dictionary = (CombatSetBonus.SETS[set_slug] as Dictionary)["tiers"]
		var thresholds: Array = tiers.keys()
		thresholds.sort()
		for threshold: Variant in thresholds:
			var t: int = int(threshold)
			_checks += 2
			if t < 2:
				_f("%s: tier %d pays for fewer than two pieces — that is not a set"
					% [set_slug, t])
			if t > total:
				_f("%s: tier %d needs more pieces than the set has (%d) — unreachable"
					% [set_slug, t, total])
		# A higher tier must never be weaker on a stat both rows carry, or
		# finding the last piece is a downgrade.
		for i: int in thresholds.size() - 1:
			var low: Dictionary = tiers[thresholds[i]]
			var high: Dictionary = tiers[thresholds[i + 1]]
			for stat: Variant in low:
				if not high.has(stat):
					continue
				_checks += 1
				if float(high[stat]) < float(low[stat]):
					_f("%s: tier %d gives less %s than tier %d — completing the "
						% [set_slug, int(thresholds[i + 1]), stat, int(thresholds[i])]
						+ "set would be a downgrade")


## Wearing N pieces must pay the single highest row, never the sum of rows.
func _check_no_stacking() -> void:
	for set_slug: StringName in CombatSetBonus.SETS:
		var tiers: Dictionary = (CombatSetBonus.SETS[set_slug] as Dictionary)["tiers"]
		if tiers.size() < 2:
			continue
		var thresholds: Array = tiers.keys()
		thresholds.sort()
		var top: int = int(thresholds[thresholds.size() - 1])
		var row: Dictionary = CombatSetBonus.tier_row(set_slug, top)
		var expected: Dictionary = tiers[top]
		_checks += 1
		if row.size() != expected.size():
			_f("%s: %d pieces resolved %d stats, expected exactly the %d-row's %d"
				% [set_slug, top, row.size(), top, expected.size()])
			continue
		for stat: Variant in expected:
			_checks += 1
			if not is_equal_approx(float(row.get(stat, 0.0)), float(expected[stat])):
				_f("%s: %d pieces gives %s=%.2f, expected %.2f — tiers are stacking"
					% [set_slug, top, stat, float(row.get(stat, 0.0)),
					float(expected[stat])])


## The bonus must be a sweetener, not the payload.
func _check_magnitude() -> void:
	var index: ContentIndex = ResourceLoader.load(ITEMS_INDEX) as ContentIndex
	var by_slug: Dictionary = {}
	for entry: Dictionary in index.entries:
		if entry.has(&"slug"):
			by_slug[StringName(entry[&"slug"])] = String(entry.get(&"path", ""))
	for set_slug: StringName in CombatSetBonus.SETS:
		var gear_total: float = 0.0
		for piece: Variant in _pieces(set_slug):
			var gear: GearItem = ResourceLoader.load(
				by_slug.get(StringName(str(piece)), "")) as GearItem
			if gear == null:
				continue
			for mod: StatModifier in gear.base_modifiers:
				if mod != null:
					gear_total += absf(float(mod.value))
		var tiers: Dictionary = (CombatSetBonus.SETS[set_slug] as Dictionary)["tiers"]
		var bonus_total: float = 0.0
		for threshold: Variant in tiers:
			var row_total: float = 0.0
			for stat: Variant in (tiers[threshold] as Dictionary):
				row_total += absf(float((tiers[threshold] as Dictionary)[stat]))
			bonus_total = maxf(bonus_total, row_total)
		_checks += 1
		if gear_total <= 0.0:
			_f("%s: pieces carry no stats at all" % set_slug)
		elif bonus_total / gear_total > MAX_BONUS_FRACTION:
			_f("%s: best set bonus is %.0f%% of the set's own stats (cap %.0f%%)"
				% [set_slug, 100.0 * bonus_total / gear_total,
				100.0 * MAX_BONUS_FRACTION])
		else:
			print("%-12s pieces=%.0f  best bonus=%.0f  (%.0f%%)"
				% [set_slug, gear_total, bonus_total, 100.0 * bonus_total / gear_total])


## The resolution path itself, on real Item resources: wear 1, 2 then 3 pieces
## and assert the tier that comes back. This is what the equipment component
## calls, so it is the behaviour players actually get.
func _check_runtime() -> void:
	var index: ContentIndex = ResourceLoader.load(ITEMS_INDEX) as ContentIndex
	var by_slug: Dictionary = {}
	for entry: Dictionary in index.entries:
		if entry.has(&"slug"):
			by_slug[StringName(entry[&"slug"])] = String(entry.get(&"path", ""))

	for set_slug: StringName in CombatSetBonus.SETS:
		var pieces: Array = _pieces(set_slug)
		var worn: Dictionary = {}
		for n: int in pieces.size():
			var slug: StringName = StringName(str(pieces[n]))
			worn[StringName("slot_%d" % n)] = ResourceLoader.load(
				by_slug.get(slug, "")) as Item
			var got: Dictionary = CombatSetBonus.bonuses_for(worn)
			var want: Dictionary = CombatSetBonus.tier_row(set_slug, n + 1)
			_checks += 1
			if got.size() != want.size():
				_f("%s: %d worn resolved %d stats, expected %d"
					% [set_slug, n + 1, got.size(), want.size()])
				continue
			for stat: Variant in want:
				_checks += 1
				if not is_equal_approx(float(got.get(stat, 0.0)), float(want[stat])):
					_f("%s: %d worn gives %s=%.2f, expected %.2f"
						% [set_slug, n + 1, stat, float(got.get(stat, 0.0)),
						float(want[stat])])
		# One piece alone must pay nothing — otherwise a single lucky drop is
		# already the whole reward and the set has no pull.
		var solo: Dictionary = {}
		solo[&"slot_0"] = ResourceLoader.load(
			by_slug.get(StringName(str(pieces[0])), "")) as Item
		_checks += 1
		if not CombatSetBonus.bonuses_for(solo).is_empty():
			_f("%s: a single piece already pays a bonus" % set_slug)

	# The same slug twice must count once, not twice.
	var dupe: Dictionary = {}
	var first: StringName = StringName(str(_pieces(&"ankhemet")[0]))
	for i: int in 3:
		dupe[StringName("slot_%d" % i)] = ResourceLoader.load(
			by_slug.get(first, "")) as Item
	_checks += 1
	if not CombatSetBonus.bonuses_for(dupe).is_empty():
		_f("three copies of one piece paid a set bonus — duplicates are counted")


## No set bonus may be built from a stat only some attack types read.
##
## This is the check that would have caught shipping Ankhemet's 3-piece row with
## DAMAGE_VS_LOW_HP on it: that stat is read only in melee_arc.gd, so a bow, wand
## or book user got literally nothing from the hardest row of a 30,000g contract
## set — and nothing anywhere reported it, because the stat applied fine, it just
## was never read.
func _check_universal_stats() -> void:
	for set_slug: StringName in CombatSetBonus.SETS:
		var tiers: Dictionary = (CombatSetBonus.SETS[set_slug] as Dictionary)["tiers"]
		for threshold: Variant in tiers:
			for stat: Variant in (tiers[threshold] as Dictionary):
				_checks += 1
				var key: StringName = StringName(str(stat))
				if CombatSetBonus.MELEE_ONLY_STATS.has(key):
					_f("%s: tier %d uses '%s', which only some attack types read — "
						% [set_slug, int(threshold), key]
						+ "it pays nothing to the builds that cannot trigger it")


func _pieces(set_slug: StringName) -> Array:
	return (CombatSetBonus.SETS[set_slug] as Dictionary)["pieces"] as Array


func _f(msg: String) -> void:
	_failures.append(msg)
