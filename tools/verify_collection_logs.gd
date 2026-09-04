extends SceneTree
## Gate for the Boss Collection Log subsystem.
##
##     godot --headless --path . -s tools/verify_collection_logs.gd
##
## Prints VERIFY_PASS / VERIFY_FAIL. Checks, in order:
##
##  1. Every .tres in collection_log/logs/ loads AS a BossCollectionLog. The
##     manager's scan iterates that folder and skips anything else, so a stray
##     file there is a boss that silently never appears in the log menu.
##  2. Every slug in every log_items resolves in the generated items_index. This
##     is the check that catches the ".item" suffix trap: &"sword_fire" looks
##     right, is wrong, and fails invisibly at runtime.
##  3. boss_id matches a real EnemyTypeResource slug in the enemy index.
##  4. No duplicate or empty entries, and a title + VFX scene on every log.
##  5. Each VFX scene instances and builds emitters inside the nameplate budget.
##  6. Every logged item is actually ON that boss's loot table — a log entry
##     nothing drops makes the log permanently unfillable.
##  7. Round-trip: fill a log, assert log_completed fires exactly once, assert a
##     SECOND character is unaffected, then serialize/deserialize through real
##     JSON and assert the state survives.
##  8. add_item_to_log is called from the boss loot pipeline and nowhere else,
##     and that credit still runs after party XP sharing.

const LOGS_PATH: String = "res://source/common/gameplay/collection_log/logs/"
const ITEMS_INDEX: String = "res://source/common/registry/indexes/items_index.tres"
const ENEMY_INDEX: String = "res://source/common/registry/indexes/enemy_types_index.tres"
const BOSS_PATH: String = "res://source/common/gameplay/characters/npc/types/bosses/"
const REWARD_SERVICE: String = "res://source/common/gameplay/combat/reward_service.gd"
const MANAGER: String = "res://source/common/gameplay/collection_log/collection_log_manager.gd"

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	var logs: Array[BossCollectionLog] = _load_logs()
	if logs.is_empty():
		_f("no BossCollectionLog resources loaded from %s" % LOGS_PATH)
	_check_slugs(logs)
	_check_shape(logs)
	_check_vfx(logs)
	_check_obtainable(logs)
	_check_runtime(logs)
	_check_call_sites()
	_check_entries_have_a_use()

	print("")
	if _failures.is_empty():
		print("VERIFY_PASS  (%d checks, %d logs)" % [_checks, logs.size()])
	else:
		for line: String in _failures:
			printerr("  FAIL: %s" % line)
		print("VERIFY_FAIL  (%d failures / %d checks)" % [_failures.size(), _checks])
	quit(0 if _failures.is_empty() else 1)


func _load_logs() -> Array[BossCollectionLog]:
	var out: Array[BossCollectionLog] = []
	for path: String in FileUtils.get_all_file_at(LOGS_PATH, "*.tres"):
		_checks += 1
		var res: Resource = ResourceLoader.load(path)
		if res == null:
			_f("%s failed to load" % path)
			continue
		if not (res is BossCollectionLog):
			_f("%s is NOT a BossCollectionLog — the manager scan will skip it" % path)
			continue
		out.append(res as BossCollectionLog)
	print("loaded %d logs" % out.size())
	return out


## Every item slug must exist in the generated items index, and every boss_id in
## the enemy index. A hand-written slug that is merely plausible resolves to id 0
## at runtime and never matches a drop.
func _check_slugs(logs: Array[BossCollectionLog]) -> void:
	var item_slugs: Dictionary = _index_slugs(ITEMS_INDEX)
	var enemy_slugs: Dictionary = _index_slugs(ENEMY_INDEX)
	for boss_log: BossCollectionLog in logs:
		_checks += 1
		if not enemy_slugs.has(boss_log.boss_id):
			_f("%s: boss_id '%s' is not in the enemy index"
				% [boss_log.boss_name, boss_log.boss_id])
		for slug: StringName in boss_log.log_items:
			_checks += 1
			if item_slugs.has(slug):
				continue
			var hint: String = ""
			# The single most likely authoring mistake, called out by name.
			if item_slugs.has(StringName(String(slug) + ".item")):
				hint = " — did you mean '%s.item'? Weapon slugs keep the suffix" % slug
			_f("%s: item slug '%s' is not in the items index%s"
				% [boss_log.boss_name, slug, hint])


func _index_slugs(path: String) -> Dictionary:
	var out: Dictionary = {}
	var index: ContentIndex = ResourceLoader.load(path) as ContentIndex
	if index == null:
		_f("%s did not load as a ContentIndex" % path)
		return out
	for entry: Dictionary in index.entries:
		if entry.has(&"slug"):
			out[StringName(entry[&"slug"])] = true
	return out


func _check_shape(logs: Array[BossCollectionLog]) -> void:
	var seen_boss: Dictionary = {}
	var seen_title: Dictionary = {}
	for boss_log: BossCollectionLog in logs:
		_checks += 3
		if seen_boss.has(boss_log.boss_id):
			_f("duplicate boss_id '%s' — the manager keeps only the first"
				% boss_log.boss_id)
		seen_boss[boss_log.boss_id] = true
		if boss_log.green_log_title_text.strip_edges().is_empty():
			_f("%s: green_log_title_text is empty" % boss_log.boss_name)
		elif seen_title.has(boss_log.green_log_title_text):
			_f("%s: green_log_title_text '%s' collides with another log"
				% [boss_log.boss_name, boss_log.green_log_title_text])
		seen_title[boss_log.green_log_title_text] = true
		if boss_log.total_items() == 0:
			_f("%s: log_items is empty — the log can never be filled"
				% boss_log.boss_name)
		var seen_item: Dictionary = {}
		for slug: StringName in boss_log.log_items:
			_checks += 1
			if slug.is_empty():
				_f("%s: empty slug in log_items" % boss_log.boss_name)
			elif seen_item.has(slug):
				# Progress is a set, so a repeat makes total_items() unreachable.
				_f("%s: '%s' listed twice — the log becomes unfillable"
					% [boss_log.boss_name, slug])
			seen_item[slug] = true


## The emitter budget, asserted rather than assumed. A title that costs three
## times the others is invisible in a solo test and only shows up as frame time
## in a full boss lobby.
func _check_vfx(logs: Array[BossCollectionLog]) -> void:
	for boss_log: BossCollectionLog in logs:
		_checks += 1
		if boss_log.green_log_vfx == null:
			_f("%s: green_log_vfx is unset" % boss_log.boss_name)
			continue
		var node: Node = boss_log.green_log_vfx.instantiate()
		var fx: GreenLogTitleFx = node as GreenLogTitleFx
		if fx == null:
			_f("%s: green_log_vfx root is not a GreenLogTitleFx" % boss_log.boss_name)
			node.free()
			continue
		# build() explicitly: a node created here never gets _ready, so the
		# emitters would otherwise all measure as absent and report as fine.
		fx.build()
		var emitters: int = 0
		for child: Node in fx.get_children():
			var p: CPUParticles2D = child as CPUParticles2D
			_checks += 1
			if p == null:
				_f("%s: non-CPUParticles2D child '%s' — GPU particles are not safe "
					% [boss_log.boss_name, child.name] + "on the web export")
				continue
			emitters += 1
			if p.amount < GreenLogTitleFx.MIN_AMOUNT or p.amount > GreenLogTitleFx.MAX_AMOUNT:
				_f("%s: emitter amount %d outside [%d, %d]" % [boss_log.boss_name,
					p.amount, GreenLogTitleFx.MIN_AMOUNT, GreenLogTitleFx.MAX_AMOUNT])
			if p.lifetime < GreenLogTitleFx.MIN_LIFETIME \
					or p.lifetime > GreenLogTitleFx.MAX_LIFETIME:
				_f("%s: emitter lifetime %.2f outside [%.2f, %.2f]"
					% [boss_log.boss_name, p.lifetime,
					GreenLogTitleFx.MIN_LIFETIME, GreenLogTitleFx.MAX_LIFETIME])
			if p.texture_filter != CanvasItem.TEXTURE_FILTER_NEAREST:
				_f("%s: emitter is not nearest-filtered — pixel art will smear"
					% boss_log.boss_name)
		if emitters == 0:
			_f("%s: VFX scene built no emitters" % boss_log.boss_name)
		if fx.z_index != GreenLogTitleFx.NAMEPLATE_Z or fx.z_as_relative:
			_f("%s: VFX must sit at absolute z_index %d to clear world art"
				% [boss_log.boss_name, GreenLogTitleFx.NAMEPLATE_Z])
		node.free()


## Every logged item must actually drop from that boss. A log entry nothing on
## the table produces is worse than a missing one: the log sits at 9/10 forever
## and the title is unreachable, with nothing anywhere reporting why.
##
## Scans every EnemyTypeResource whose enemy_type matches the log's boss_id, so
## the overworld and _world (Boss Hunt) variants are considered together — the
## uniques live only on the _world tables by design.
func _check_obtainable(logs: Array[BossCollectionLog]) -> void:
	for boss_log: BossCollectionLog in logs:
		var droppable: Dictionary = {}
		var tables: int = 0
		for path: String in FileUtils.get_all_file_at(BOSS_PATH, "*.tres"):
			var res: Resource = ResourceLoader.load(path)
			var enemy: EnemyTypeResource = res as EnemyTypeResource
			if enemy == null or enemy.enemy_type != boss_log.boss_id:
				continue
			tables += 1
			for drop: LootDrop in enemy.loot:
				if drop == null or drop.item == null:
					continue
				droppable[StringName(str(drop.item.get_meta(&"slug", &"")))] = true
		_checks += 1
		if tables == 0:
			_f("%s: no EnemyTypeResource has enemy_type '%s'"
				% [boss_log.boss_name, boss_log.boss_id])
			continue
		# THE KEY-DRIFT CHECK. The runtime resolves a kill to a log through
		# CollectionLogManager.boss_id_for; if that ever went back to reading the
		# registry slug, the Boss Hunt variant (cinderborn_world.tres, slug
		# &"cinderborn_world") would resolve to no log at all and the whole
		# feature would no-op on the only variant that drops the uniques —
		# silently, with a full loot table and a log stuck at 0.
		for path: String in FileUtils.get_all_file_at(BOSS_PATH, "*.tres"):
			var enemy: EnemyTypeResource = ResourceLoader.load(path) as EnemyTypeResource
			if enemy == null or enemy.enemy_type != boss_log.boss_id:
				continue
			_checks += 1
			if _manager_script().boss_id_for(enemy) != boss_log.boss_id:
				_f("%s: %s resolves to log key '%s', not '%s' — kills on this "
					% [boss_log.boss_name, path.get_file(),
					_manager_script().boss_id_for(enemy), boss_log.boss_id]
					+ "variant would credit nothing")
		for slug: StringName in boss_log.log_items:
			_checks += 1
			if not droppable.has(slug):
				_f("%s: '%s' is in the log but on none of its %d loot tables — "
					% [boss_log.boss_name, slug, tables]
					+ "the log can never reach 100%")


## End to end on a live manager instance and real PlayerResources: fill one log,
## assert the reward fires once, assert a SECOND character is untouched, and
## assert the state survives a save/load round trip.
func _check_runtime(logs: Array[BossCollectionLog]) -> void:
	if logs.is_empty():
		return
	var subject: BossCollectionLog = logs[0]
	var mgr: Node = _new_manager()
	# State lives on the PlayerResource, not on the manager, so a second
	# character must be completely unaffected by the first. Asserted below.
	var alice: PlayerResource = PlayerResource.new()
	var bob: PlayerResource = PlayerResource.new()

	var completions: Array = []
	# A one-slot Array, not an int: GDScript lambdas capture by VALUE, so
	# "item_events += 1" inside the closure would increment a copy and leave the
	# outer counter at zero — a verifier that always agrees with itself.
	var item_events: Array[int] = [0]
	mgr.log_completed.connect(func(res: PlayerResource, bid: StringName,
			title: String, vfx: PackedScene) -> void:
		completions.append({"res": res, "boss": bid, "title": title, "vfx": vfx})
	)
	mgr.item_logged.connect(func(_r: PlayerResource, _b: StringName, _i: StringName,
			_u: int, _t: int) -> void:
		item_events[0] += 1
	)

	_checks += 1
	if mgr.check_green_log_status(alice, subject.boss_id):
		_f("a fresh log reports green before any drop")

	# An item this boss does not own must not advance the log — the "wrong boss
	# credited a shared weapon" case.
	mgr.add_item_to_log(alice, subject.boss_id, &"definitely_not_a_real_slug")
	_checks += 1
	if mgr.unlocked_count(alice, subject.boss_id) != 0:
		_f("an unowned item slug advanced the log")

	mgr.increment_boss_kill(alice, subject.boss_id)
	mgr.increment_boss_kill(alice, subject.boss_id)
	_checks += 2
	if mgr.kill_count(alice, subject.boss_id) != 2:
		_f("kill count is %d, expected 2" % mgr.kill_count(alice, subject.boss_id))
	if mgr.dry_streak(alice, subject.boss_id) != 2:
		_f("dry streak is %d after 2 dry kills, expected 2"
			% mgr.dry_streak(alice, subject.boss_id))

	for i: int in subject.log_items.size():
		mgr.add_item_to_log(alice, subject.boss_id, subject.log_items[i])
		# The same drop again: duplicates are progress-neutral.
		mgr.add_item_to_log(alice, subject.boss_id, subject.log_items[i])
		var expect_green: bool = i == subject.log_items.size() - 1
		_checks += 1
		if mgr.check_green_log_status(alice, subject.boss_id) != expect_green:
			_f("green status wrong after %d/%d items"
				% [i + 1, subject.log_items.size()])

	_checks += 4
	if mgr.dry_streak(alice, subject.boss_id) != 0:
		_f("dry streak did not reset on a unique drop")
	if item_events[0] != subject.total_items():
		_f("item_logged fired %d times for %d unique drops (duplicates leaked)"
			% [item_events[0], subject.total_items()])
	if completions.size() != 1:
		_f("log_completed fired %d times, expected exactly 1" % completions.size())
	elif completions[0]["title"] != subject.green_log_title_text \
			or completions[0]["vfx"] != subject.green_log_vfx \
			or completions[0]["res"] != alice:
		_f("log_completed carried the wrong player/title/VFX payload")

	# THE MULTI-PLAYER CHECK. One world process serves many characters; if any
	# state had stayed on the autoload, Bob would be reading Alice's green log.
	_checks += 3
	if mgr.check_green_log_status(bob, subject.boss_id):
		_f("a second character inherited the first's green log — state is on "
			+ "the autoload, not the PlayerResource")
	if mgr.unlocked_count(bob, subject.boss_id) != 0:
		_f("a second character inherited %d unlocked items"
			% mgr.unlocked_count(bob, subject.boss_id))
	if mgr.kill_count(bob, subject.boss_id) != 0:
		_f("a second character inherited a kill count")

	# Filling an already-green log must not re-award it.
	mgr.add_item_to_log(alice, subject.boss_id, subject.log_items[0])
	_checks += 1
	if completions.size() != 1:
		_f("log_completed re-fired on a duplicate drop into a green log")

	var blob: Dictionary = mgr.serialize_log_data(alice)
	# Through real JSON, not just a Dictionary copy: that is what strips
	# StringName back to String and is where a naive round trip breaks.
	var json_round: Dictionary = JSON.parse_string(JSON.stringify(blob))
	var restored: Node = _new_manager()
	var reloaded: PlayerResource = PlayerResource.new()
	var post_load: Array[int] = [0] # by-value capture again — see above
	restored.log_completed.connect(func(_r: PlayerResource, _b: StringName,
			_t: String, _v: PackedScene) -> void:
		post_load[0] += 1
	)
	restored.deserialize_log_data(reloaded, json_round)
	_checks += 5
	if not restored.check_green_log_status(reloaded, subject.boss_id):
		_f("log is not green after a JSON round trip — StringName keys were lost")
	if not restored.has_green_log(reloaded, subject.boss_id):
		_f("completed flag did not survive the round trip")
	if restored.kill_count(reloaded, subject.boss_id) \
			!= mgr.kill_count(alice, subject.boss_id):
		_f("kill count did not survive the round trip")
	if post_load[0] != 0:
		_f("deserialize re-emitted log_completed — the title would re-award on login")
	# A pre-v24 row has no collection_log_json at all.
	var fresh: PlayerResource = PlayerResource.new()
	restored.deserialize_log_data(fresh, JSON.parse_string("{}"))
	if restored.kill_count(fresh, subject.boss_id) != 0:
		_f("an empty save blob did not load as an empty log")

	mgr.queue_free()
	restored.queue_free()


## Every MATERIAL in a collection log must have somewhere to go.
##
## Gear and weapons justify themselves — you wear them, or you break them down.
## A plain material does not: if nothing consumes it, it is vendor fodder that
## drops forever and the log entry is filler. Both of the materials invented for
## these logs shipped that way in the first pass (Everburning Coal, Sovereign's
## Bloom) and neither read as broken — they just quietly were not worth having.
##
## "Somewhere to go" = a crafting recipe consumes it, OR it can be broken down
## into something else.
func _check_entries_have_a_use() -> void:
	var consumed: Dictionary = {}
	for path: String in FileUtils.get_all_file_at(
			"res://source/common/gameplay/crafting/resources/", "*.tres"):
		var station: CraftingStationResource = ResourceLoader.load(
			path) as CraftingStationResource
		if station == null:
			continue
		for recipe: CraftingRecipe in station.recipes:
			if recipe == null:
				continue
			for ing: CraftIngredient in recipe.ingredients:
				if ing != null and ing.item != null:
					consumed[StringName(str(ing.item.get_meta(&"slug", &"")))] = true
	var breakable: Dictionary = {}
	var table: SalvageTable = ResourceLoader.load(
		SalvageTable.TABLE_PATH) as SalvageTable
	if table != null:
		for recipe: SalvageRecipe in table.recipes:
			if recipe != null and recipe.source_item != null:
				breakable[StringName(str(recipe.source_item.get_meta(&"slug", &"")))] = true

	for path: String in FileUtils.get_all_file_at(LOGS_PATH, "*.tres"):
		var boss_log: BossCollectionLog = ResourceLoader.load(path) as BossCollectionLog
		if boss_log == null:
			continue
		for slug: StringName in boss_log.log_items:
			var item: Item = ContentRegistryHub.load_by_slug(&"items", slug) as Item
			# Only plain materials need this: gear is worn, weapons are salvaged.
			if item == null or item is GearItem or item is WeaponItem:
				continue
			_checks += 1
			if not consumed.has(slug) and not breakable.has(slug):
				_f("%s: '%s' is a log entry that nothing consumes and nothing "
					% [boss_log.boss_name, slug]
					+ "breaks down — it is filler, not a reward")


## The integrity model, asserted against the source rather than trusted: the ONLY
## place allowed to credit the log is the boss loot pipeline in RewardService.
## A call from an inventory / bank / trade / chest path would let players fill a
## log without fighting the boss, and it is the kind of shortcut that looks
## harmless in review.
func _check_call_sites() -> void:
	var allowed: PackedStringArray = [REWARD_SERVICE, MANAGER]
	var offenders: PackedStringArray = []
	for path: String in FileUtils.get_all_file_at("res://source/", "*.gd"):
		if allowed.has(path):
			continue
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var text: String = f.get_as_text()
		f.close()
		if text.contains("add_item_to_log("):
			offenders.append(path)
	_checks += 1
	if not offenders.is_empty():
		_f("add_item_to_log called outside the boss loot pipeline: %s"
			% ", ".join(offenders))

	var rs: FileAccess = FileAccess.open(REWARD_SERVICE, FileAccess.READ)
	_checks += 2
	if rs == null:
		_f("reward_service.gd is unreadable")
		return
	var src: String = rs.get_as_text()
	rs.close()
	var credit_at: int = src.find("_credit_collection_logs(npc, log_credits)")
	if credit_at < 0:
		_f("RewardService.distribute no longer credits the collection log")
	# Ordering is load-bearing: the credit lands after party XP sharing, and a
	# party member who only shared XP must never be credited a kill.
	var share_at: int = src.find("_share_party_xp(npc, seen)")
	if share_at < 0 or credit_at < share_at:
		_f("collection log credit no longer runs AFTER _share_party_xp")


## The manager SCRIPT, for calling its statics. Autoload identifiers do not
## resolve in a `-s` run, so `CollectionLogManager.boss_id_for(...)` would be a
## compile error here even though it is correct in the running server.
func _manager_script() -> GDScript:
	return load(MANAGER) as GDScript


## Autoload identifiers do not resolve in a `-s` run, so the manager has to be
## loaded and instanced by path — the same limitation DailyQuestManager documents.
func _new_manager() -> Node:
	var node: Node = load(MANAGER).new()
	root.add_child(node)
	return node


func _f(msg: String) -> void:
	_failures.append(msg)
