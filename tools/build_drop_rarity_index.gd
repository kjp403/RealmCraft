extends SceneTree
## Regenerate source/common/registry/indexes/drop_rarity_index.tres — the lookup
## loot beams tier on. Run after changing any enemy loot table:
##
##   godot --headless --path . -s tools/build_drop_rarity_index.gd
##
## Scans every registered enemy type and records, per item, the BEST chance any
## source drops it at (see DropRarityIndex for why "best" and not "worst").
## Boss ornate-chest grants count too — a chest handed out by RewardService is a
## drop as far as a player is concerned.
##
## Writes the .tres as TEXT rather than via ResourceSaver: saving a resource from
## a headless tool run strips uid= from the file and from every ext_resource in
## it, which quietly breaks references elsewhere.

const ENEMY_INDEX := "res://source/common/registry/indexes/enemy_types_index.tres"
const OUT := "res://source/common/registry/indexes/drop_rarity_index.tres"
const SCRIPT_PATH := "res://source/common/registry/drop_rarity_index.gd"


func _init() -> void:
	var index: ContentIndex = load(ENEMY_INDEX)
	if index == null:
		printerr("FAIL: enemy index will not load")
		quit(1)
		return

	var best: Dictionary = {}          # item id -> best chance
	var names: Dictionary = {}         # item id -> name, for the report only
	var scanned: int = 0

	for entry: Dictionary in index.entries:
		var res: EnemyTypeResource = load(entry.get(&"path", "")) as EnemyTypeResource
		if res == null:
			continue
		scanned += 1
		for drop: LootDrop in res.loot:
			if drop == null or drop.item == null:
				continue
			_record(best, names, drop.item, drop.chance)
		# The ranked ornate-chest grant is a real acquisition path. Treat the
		# consolation roll as its chance, since that is what most contributors
		# actually roll against; top-DPS grants are strictly better than this.
		if res.ornate_chest_top_max > 0 and res.ornate_chest_item != null:
			var c: float = maxf(res.ornate_chest_consolation_chance, 0.0)
			_record(best, names, res.ornate_chest_item, maxf(c, 0.01))

	var lines: PackedStringArray = PackedStringArray()
	lines.append('[gd_resource type="Resource" script_class="DropRarityIndex" format=3]')
	lines.append("")
	lines.append('[ext_resource type="Script" path="%s" id="1_script"]' % SCRIPT_PATH)
	lines.append("")
	lines.append("[resource]")
	lines.append('script = ExtResource("1_script")')
	lines.append("generated_at = %d" % int(Time.get_unix_time_from_system()))
	lines.append("sources_scanned = %d" % scanned)
	var ids: Array = best.keys()
	ids.sort()
	var pairs: PackedStringArray = PackedStringArray()
	for id: int in ids:
		pairs.append("%d: %s" % [id, String.num(float(best[id]), 6)])
	lines.append("best_chance = {%s}" % ", ".join(pairs))
	lines.append("")

	var f: FileAccess = FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		printerr("FAIL: cannot write ", OUT)
		quit(1)
		return
	f.store_string("\n".join(lines))
	f.close()

	print("scanned %d enemy types, indexed %d droppable items" % [scanned, ids.size()])
	var buckets: Dictionary = {"<=0.2%": 0, "<=1%": 0, "<=5%": 0, ">5%": 0}
	for id: int in ids:
		var c: float = best[id]
		if c <= 0.002: buckets["<=0.2%"] += 1
		elif c <= 0.01: buckets["<=1%"] += 1
		elif c <= 0.05: buckets["<=5%"] += 1
		else: buckets[">5%"] += 1
	for k: String in ["<=0.2%", "<=1%", "<=5%", ">5%"]:
		print("  %-7s %d items" % [k, buckets[k]])
	print("rarest:")
	var by_rate: Array = ids.duplicate()
	by_rate.sort_custom(func(a, b): return float(best[a]) < float(best[b]))
	for i: int in mini(6, by_rate.size()):
		var id: int = by_rate[i]
		print("  %7.4f%%  %s" % [float(best[id]) * 100.0, names.get(id, "?")])
	print("BUILD_OK")
	quit()


func _record(best: Dictionary, names: Dictionary, item: Item, chance: float) -> void:
	var id: int = int(item.get_meta("id", 0))
	if id <= 0:
		return
	names[id] = String(item.item_name)
	best[id] = maxf(float(best.get(id, 0.0)), chance)
