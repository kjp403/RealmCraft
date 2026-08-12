extends SceneTree
## Integration audit for the Cleetus work. Deliberately NOT scoped to Cleetus:
## the change touched HostileNpc, BossController, EnemyTypeResource and
## AttackTelegraph, which every mob, every boss and every lunging wolf in the game
## runs. This loads the whole content set and checks the shared contracts.
##
##   godot --headless --path . -s tools/audit_boss_integration.gd
##
## Pre-existing `-s` noise (client autoloads absent, melee_arc.tscn) is expected
## and is NOT what this reports; it only reports things that would be regressions.

const ENEMY_INDEX := "res://source/common/registry/indexes/enemy_types_index.tres"
const HOSTILE_NPC := "res://source/common/gameplay/characters/npc/hostile_npc.gd"
const CONTROLLER := "res://source/common/gameplay/dungeon/boss_controller.gd"
const NPC_SCENE := "res://source/common/gameplay/characters/npc/hostile_npc.tscn"
## Clips removed during the work — nothing may still ask for them.
const DEAD_CLIPS: Array[String] = ["cast_beam", "cast_storm"]

var _fail: Array[String] = []
var _warn: Array[String] = []


func _f(m: String) -> void:
	_fail.append(m)
	printerr("FAIL: ", m)


func _w(m: String) -> void:
	_warn.append(m)
	print("WARN: ", m)


func _init() -> void:
	print("=== 1. every registered enemy still loads and is self-consistent")
	_audit_enemies()
	print("\n=== 2. shared rp_ contract: every replicated call resolves")
	_audit_rp_contract()
	print("\n=== 3. removed clips are not referenced anywhere")
	_audit_dead_clips()
	print("\n=== 4. content indexes are internally consistent")
	_audit_indexes()
	print("\n=== 5. server/client agree on the cast origin")
	_audit_muzzle_symmetry()
	print("\n=== 6. loot beams light the right things")
	_audit_loot_beams()
	print("\n=== 7. every .gd under source/ parses")
	_audit_scripts()

	print("")
	if _warn.size() > 0:
		print("%d warning(s)" % _warn.size())
	if _fail.is_empty():
		print("AUDIT_PASS")
	else:
		print("AUDIT_FAIL (%d)" % _fail.size())
	quit(0 if _fail.is_empty() else 1)


## Every enemy in the index: loads, has a skin, and that skin exposes the clips
## the mob chassis will actually ask it for.
func _audit_enemies() -> void:
	var index: ContentIndex = load(ENEMY_INDEX)
	if index == null:
		_f("enemy index will not load")
		return
	var ids: Dictionary = {}
	var slugs: Dictionary = {}
	var bosses: int = 0
	var checked: int = 0
	for e: Dictionary in index.entries:
		var slug: StringName = e.get(&"slug", &"")
		var path: String = e.get(&"path", "")
		var id: int = e.get(&"id", -1)
		if ids.has(id):
			_f("duplicate id %d (%s and %s)" % [id, ids[id], slug])
		ids[id] = slug
		if slugs.has(slug):
			_f("duplicate slug %s" % slug)
		slugs[slug] = true
		if not ResourceLoader.exists(path):
			_f("%s: path missing (%s)" % [slug, path])
			continue
		var res: EnemyTypeResource = load(path) as EnemyTypeResource
		if res == null:
			_f("%s: does not load as EnemyTypeResource" % slug)
			continue
		checked += 1
		if res.skin == null:
			_w("%s: no skin assigned" % slug)
		else:
			# The chassis drives these three by name through the AnimationTree.
			for need: StringName in [&"idle", &"run", &"death"]:
				if not res.skin.has_animation(need):
					_f("%s: skin has no '%s' — locomotion will break" % [slug, need])
		if res.is_boss:
			bosses += 1
			_audit_boss(slug, res)
	print("  %d enemies loaded, %d bosses, ids unique, slugs unique" % [checked, bosses])
	if index.next_id <= ids.keys().max():
		_f("next_id %d is not above the highest id %d" % [index.next_id, ids.keys().max()])


## A boss gets a BossController, which will replicate cast clips at it.
func _audit_boss(slug: StringName, res: EnemyTypeResource) -> void:
	if res.skin == null:
		return
	# cast_anim (or its "attack" fallback) must resolve to SOMETHING, else the
	# cast plays no animation at all. Not fatal — it is how several shipped
	# bosses already behave — but it must be visible, not silent.
	if not res.skin.has_animation(res.cast_anim) and not res.skin.has_animation(&"attack"):
		_w("%s: no cast clip and no 'attack' fallback — casts animate nothing" % slug)
	if not res.phase2_skin.is_empty():
		if not ResourceLoader.exists(res.phase2_skin):
			_f("%s: phase2_skin missing (%s)" % [slug, res.phase2_skin])
			return
		var cold: SpriteFrames = load(res.phase2_skin) as SpriteFrames
		if cold == null:
			_f("%s: phase2_skin is not SpriteFrames" % slug)
			return
		# The swap keeps clip NAMES; a missing one freezes the body after enrage.
		for anim: StringName in res.skin.get_animation_names():
			if not cold.has_animation(anim):
				_f("%s: phase2 skin lacks '%s'" % [slug, anim])
	# A spell gated to phase 2 on a boss that cannot enrage is unreachable.
	if res.enrage_health_fraction <= 0.0:
		for pair: Array in [["meteor", res.meteor_count > 0, res.meteor_phase],
				["sweep", res.sweep_arc_deg > 0.0, res.sweep_phase],
				["frost", res.frost_safe_radius > 0.0, res.frost_phase],
				["chain", res.chain_targets > 0, res.chain_phase]]:
			if bool(pair[1]) and int(pair[2]) == 2:
				_f("%s: %s is phase-2 only but the boss never enrages" % [slug, pair[0]])
	# An enabled spell with a zero interval would re-fire every frame.
	for pair: Array in [["meteor", res.meteor_count > 0, res.meteor_interval_s],
			["sweep", res.sweep_arc_deg > 0.0, res.sweep_interval_s],
			["frost", res.frost_safe_radius > 0.0, res.frost_interval_s],
			["chain", res.chain_targets > 0, res.chain_interval_s],
			["laser", res.laser_range > 0.0, res.laser_interval_s]]:
		if bool(pair[1]) and float(pair[2]) <= 0.0:
			_f("%s: %s enabled with a 0s interval" % [slug, pair[0]])


## Every rp_ name BossController replicates must exist on HostileNpc, and every
## call must fit the method's arity. A mismatch is silent in Godot — the client
## just does nothing — so it has to be caught here.
func _audit_rp_contract() -> void:
	var body := FileAccess.open(HOSTILE_NPC, FileAccess.READ)
	var ctrl := FileAccess.open(CONTROLLER, FileAccess.READ)
	if body == null or ctrl == null:
		_f("could not read hostile_npc.gd / boss_controller.gd")
		return
	var btext: String = body.get_as_text()
	var ctext: String = ctrl.get_as_text()
	body.close()
	ctrl.close()

	# arity of each rp_ definition (required args, total args)
	var arity: Dictionary = {}
	for line: String in btext.split("\n"):
		var s: String = line.strip_edges()
		if not s.begins_with("func rp_"):
			continue
		var name: String = s.substr(5, s.find("(") - 5)
		var args: String = s.substr(s.find("(") + 1)
		args = args.substr(0, args.rfind(")"))
		var req: int = 0
		var tot: int = 0
		if args.strip_edges() != "":
			for a: String in args.split(","):
				tot += 1
				if not a.contains("="):
					req += 1
		arity[name] = [req, tot]
	# multi-line signatures lose their args to the split above; re-read those
	for name: String in arity:
		if int(arity[name][1]) == 0 and btext.contains("func %s(\n" % name):
			arity[name] = [-1, -1]   # unknown, skip arity check

	var seen: int = 0
	for raw: String in ctext.split("replicate_visual(&\""):
		if raw == ctext.split("replicate_visual(&\"")[0]:
			continue
		var name: String = raw.substr(0, raw.find("\""))
		if not name.begins_with("rp_"):
			continue
		seen += 1
		if not arity.has(name):
			_f("BossController replicates %s() which HostileNpc does not define" % name)
			continue
		var span: String = raw.substr(0, raw.find("])") + 1)
		var depth: int = 0
		var count: int = 0
		var started := false
		for i: int in span.length():
			var ch: String = span[i]
			if ch == "[":
				depth += 1
				if depth == 1:
					started = true
					count = 1
				continue
			if ch == "]":
				depth -= 1
				continue
			if depth == 1 and ch == ",":
				count += 1
		if not started:
			continue
		if span.find("[]") >= 0:
			count = 0
		var req: int = arity[name][0]
		var tot: int = arity[name][1]
		if req >= 0 and (count < req or count > tot):
			_f("%s called with %d arg(s); it takes %d..%d" % [name, count, req, tot])
	print("  %d replicated calls checked against %d rp_ definitions" % [seen, arity.size()])


func _audit_dead_clips() -> void:
	var hits: int = 0
	for path: String in _all_files("res://source", [".gd", ".tres", ".tscn"]):
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var txt: String = f.get_as_text()
		f.close()
		for clip: String in DEAD_CLIPS:
			if txt.contains('&"%s"' % clip) or txt.contains('cleetus_%s.png' % clip):
				_f("%s still references removed clip '%s'" % [path, clip])
				hits += 1
	if hits == 0:
		print("  no references to %s" % ", ".join(DEAD_CLIPS))


func _audit_indexes() -> void:
	for path: String in _all_files("res://source/common/registry/indexes", [".tres"]):
		var idx: ContentIndex = load(path) as ContentIndex
		if idx == null:
			continue
		var stale: int = 0
		var missing: int = 0
		for e: Dictionary in idx.entries:
			var p: String = e.get(&"path", "")
			if not ResourceLoader.exists(p):
				missing += 1
				continue
			if e.has(&"hash") and FileAccess.get_sha256(p) != e[&"hash"]:
				stale += 1
		if missing > 0:
			_f("%s: %d entries point at missing files" % [path.get_file(), missing])
		if stale > 0:
			_w("%s: %d stale hashes (cosmetic — nothing reads hash at runtime)"
				% [path.get_file(), stale])
		print("  %-26s %3d entries, %d missing, %d stale hash"
			% [path.get_file(), idx.entries.size(), missing, stale])


## The beam is DRAWN from muzzle_position() on the client and hit-tested from the
## same call on the server. Both read `flipped` and `enemy_data.visual_scale`, so
## those must be server-owned and replicated, or the two diverge.
func _audit_muzzle_symmetry() -> void:
	var f := FileAccess.open(HOSTILE_NPC, FileAccess.READ)
	if f == null:
		return
	var t: String = f.get_as_text()
	f.close()
	if not t.contains("func muzzle_position("):
		_f("muzzle_position() is gone")
		return
	if t.contains("multiplayer.is_server()") and t.split("func muzzle_position(")[1] \
			.split("\nfunc ")[0].contains("multiplayer.is_server()"):
		_f("muzzle_position() branches on peer — server and client would disagree")
	if not t.contains("_flipped_fid"):
		_f("`flipped` is no longer replicated — muzzle would mirror differently per peer")
	else:
		print("  muzzle_position() is peer-agnostic; `flipped` is replicated")


func _audit_scripts() -> void:
	var files: PackedStringArray = _all_files("res://source", [".gd"])
	var bad: int = 0
	for path: String in files:
		var s: Script = load(path) as Script
		if s == null:
			bad += 1
			_w("did not load: %s" % path)
	print("  %d scripts, %d failed to load" % [files.size(), bad])


func _all_files(root: String, exts: Array) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var dirs: Array[String] = [root]
	while dirs.size() > 0:
		var d: String = dirs.pop_back()
		var da := DirAccess.open(d)
		if da == null:
			continue
		da.list_dir_begin()
		var n: String = da.get_next()
		while n != "":
			var full: String = d.path_join(n)
			if da.current_is_dir():
				if not n.begins_with("."):
					dirs.append(full)
			else:
				for e: String in exts:
					if n.ends_with(e):
						out.append(full)
						break
			n = da.get_next()
		da.list_dir_end()
	return out


## Loot beams are threshold-driven, so the risk is silent drift: reprice an item
## and half the game glows, or the relics quietly stop glowing. Assert the SHAPE
## of the result, not just that the code runs.
func _audit_loot_beams() -> void:
	var idx: ContentIndex = load("res://source/common/registry/indexes/items_index.tres")
	if idx == null:
		_f("items index will not load")
		return
	var counts: Dictionary = {0: 0, 1: 0, 2: 0, 3: 0}
	var relics_lit: int = 0
	var relics_total: int = 0
	for e: Dictionary in idx.entries:
		var it: Item = load(e[&"path"]) as Item
		if it == null:
			continue
		var tier: int = LootBeam.tier_for(it)
		counts[tier] = int(counts[tier]) + 1
		var g: GearItem = it as GearItem
		if g != null and g.slot != null and g.slot.key == &"relic":
			relics_total += 1
			if tier == LootBeam.Tier.RELIC:
				relics_lit += 1
	# STALENESS: the index is generated. If a loot table moved and nobody reran
	# the builder, every beam silently tiers off yesterday's rates. Recompute and
	# compare rather than trusting the committed file.
	var live: Dictionary = {}
	var enemies: ContentIndex = load(ENEMY_INDEX)
	if enemies != null:
		for e: Dictionary in enemies.entries:
			var res: EnemyTypeResource = load(e.get(&"path", "")) as EnemyTypeResource
			if res == null:
				continue
			for d: LootDrop in res.loot:
				if d == null or d.item == null:
					continue
				var iid: int = int(d.item.get_meta("id", 0))
				if iid > 0:
					live[iid] = maxf(float(live.get(iid, 0.0)), d.chance)
	var drift: int = 0
	for iid: int in live:
		if absf(float(live[iid]) - DropRarityIndex.chance_for(iid)) > 0.00001:
			drift += 1
	if drift > 0:
		_f("drop rarity index is STALE for %d item(s) — rerun tools/build_drop_rarity_index.gd"
			% drift)
	else:
		print("  rarity index matches the live loot tables (%d droppable items)" % live.size())

	var lit: int = int(counts[1]) + int(counts[2]) + int(counts[3])
	var total: int = int(counts[0]) + lit
	print("  %d items: %d dark, %d cyan, %d gold, %d purple"
		% [total, counts[0], counts[1], counts[2], counts[3]])
	# The rarest drops in the game are worth 0 at a vendor; they MUST still beam.
	if relics_total > 0 and relics_lit != relics_total:
		_f("%d of %d relics get no beam — the value rule swallowed them"
			% [relics_total - relics_lit, relics_total])
	# A beam is only special if it stays rare.
	var pct: float = 100.0 * float(lit) / float(maxi(1, total))
	if pct > 15.0:
		_f("%.0f%% of all items raise a beam — thresholds have drifted" % pct)
	else:
		print("  %.1f%% of the item table beams; all %d relics lit" % [pct, relics_total])
