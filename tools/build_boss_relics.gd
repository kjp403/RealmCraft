extends SceneTree
## Author the ten boss-drop relics and hang each one off its boss's loot table.
##
## The relic slot only ever held the three smithable necklaces, so it had no
## progression of its own. These ten give it one: five colour families, each a
## LESSER charm from an early boss and a GREATER sigil from a late one, so the
## slot upgrades along the path the player already walks (Woodland -> Fire Forge)
## instead of topping out at the anvil.
##
## Everything here is written as TEXT, never through ResourceSaver. In a
## `--headless -s` run the ResourceUID cache is not loaded, so the text saver
## finds no id for any path and silently drops `uid=` from the file it rewrites
## AND from every ext_resource in it — which would strip the uids the maps use
## to reference these bosses. Dependency uids are read back out of the files
## with ResourceLoader.get_resource_uid (which parses the header directly and
## does not need the cache); the relics' own uids come from
## ResourceUID.create_id, never hand-typed, because a uid holding a character
## outside Godot's base-34 alphabet is silently rewritten on import.
##
## The items index is updated here too, so each relic ships already stamped with
## its `metadata/slug` / `metadata/id`. tools/update_items_index.gd re-saves any
## item it has to stamp, which would strip the uid straight back off — leaving
## nothing for it to do is the only way the relics keep theirs.
##
## Re-running is idempotent: relic files are rewritten from this table (keeping
## the uid and id they already have), and each boss keeps exactly one drop per
## relic — the previous insert is stripped by slug before the new one goes in.
##
##   godot --headless --path . -s tools/build_boss_relics.gd

const RELIC_DIR := "res://source/common/gameplay/items/gears/relics"
const ICON_DIR := "res://assets/sprites/items/icons"
const TYPES := "res://source/common/gameplay/characters/npc/types"
const SLOT := "res://source/common/gameplay/items/item_slot/slots/relic.tres"
const MOD_SCRIPT := "res://source/common/gameplay/combat/attributes/stat_modifier.gd"
const GEAR_SCRIPT := "res://source/common/gameplay/items/gear_item.gd"
const LOOT_SCRIPT := "res://source/common/gameplay/combat/loot_drop.gd"
const INDEX := "res://source/common/registry/indexes/items_index.tres"

## One row per relic. `mods` uses only the nine stats [StatModifier] exposes —
## crit chance/damage, attack speed and lifesteal are declared on [Stat] but no
## gear path reads them, so a relic granting one would be a dead tooltip line.
##
## Values sit in the envelope the rest of the gear already occupies (armour <=15,
## health <=16 per piece, ad <=8, ap <=4, haste <=5, mana_regen <=0.2 on jewelry):
## lesser charms land just above the Gold Necklace's 6 armour / 14 health, and
## greater sigils roughly double a lesser without passing a chest piece.
##
## `[slug, name, boss, chance, vendor, mods, description]`
const RELICS: Array = [
	# --- Lesser charms: one mono-coloured stone, early bosses -------------------
	[
		"relic_mossgrown", "Mossgrown Charm",
		"goblins/goblin_chief", 0.10, 900,
		[["armor", 5.0], ["health_max", 10.0]],
		"Green has grown over it so long it stopped being a stone and started being the moss.",
	],
	[
		"relic_sporebloom", "Sporebloom Charm",
		"fungus/fungal_heart", 0.10, 1100,
		[["mr", 4.0], ["health_max", 14.0]],
		"Still breathing out spores. The cave grew this one on purpose.",
	],
	[
		"relic_bloodbrand", "Bloodbrand Charm",
		"bandit_captain", 0.08, 1300,
		[["ad", 5.0], ["health_max", 8.0]],
		"Taken off a captain who took it off someone else. It keeps changing hands the same way.",
	],
	[
		"relic_duskglass", "Duskglass Charm",
		"skeleton_mage", 0.08, 1400,
		[["ap", 4.0], ["mana_max", 18.0], ["mana_regen", 0.2]],
		"Cave-dark glass with one cold spark left in it, circling like it is looking for the way out.",
	],
	[
		"relic_emberbrand", "Emberbrand Charm",
		"orc_leader", 0.08, 1600,
		[["move_speed", 3.0], ["ability_haste", 3.0]],
		"Warm before you touch it, warmer after. Orc warbands carry them to keep the pace up.",
	],
	# --- Greater sigils: a second energy veined through the same stone ----------
	[
		"relic_rotmire", "Rotmire Sigil",
		"bosses/cistern_sovereign", 0.05, 2600,
		[["armor", 9.0], ["health_max", 18.0], ["mr", 4.0]],
		"Cistern water found its way into the moss and set there in a blue seam. Heavier than it looks.",
	],
	[
		"relic_coreblossom", "Coreblossom Sigil",
		"mecha_stone_golem", 0.05, 3200,
		[["mr", 6.0], ["health_max", 22.0], ["mana_regen", 0.5]],
		"Cut out of a golem's chest, still lit. Whatever the Hollow built it to run on has not run out.",
	],
	[
		"relic_scarabheart", "Scarabheart Sigil",
		"bosses/sand_king", 0.04, 3800,
		[["ad", 9.0], ["health_max", 12.0], ["ability_haste", 3.0]],
		"A green scarab line runs through the red. Ankhemet was buried wearing it and did not stay buried.",
	],
	[
		"relic_netherglass", "Netherglass Sigil",
		"trpg/trpg_necromancer", 0.04, 4400,
		[["ap", 7.0], ["mana_max", 25.0], ["mana_regen", 0.8], ["mr", 3.0]],
		"The violet thread inside moves when nothing else does. It was doing that before the necromancer found it.",
	],
	[
		"relic_cinderheart", "Cinderheart Sigil",
		"bosses/cinderborn", 0.03, 6000,
		[["ad", 7.0], ["move_speed", 5.0], ["ability_haste", 5.0], ["health_max", 10.0]],
		"Vurthek's own coal, banked and never gone out. It burns for whoever carries it next.",
	],
]


func _initialize() -> void:
	var index: ContentIndex = load(INDEX) as ContentIndex
	assert(index != null, "missing items index: %s" % INDEX)

	var indexed: Dictionary = {}
	for entry: Dictionary in index.entries:
		indexed[StringName(entry.get(&"slug", &""))] = entry

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RELIC_DIR))

	var new_entries: Array[Dictionary] = []
	for row: Array in RELICS:
		var slug: String = row[0]
		var path := "%s/%s.tres" % [RELIC_DIR, slug]
		var known: Dictionary = indexed.get(StringName(slug), {})
		var id: int = int(known.get(&"id", 0))
		if id == 0:
			id = index.next_id
			index.next_id += 1

		_write_relic(row, id)
		if known.is_empty():
			new_entries.append({
				&"id": id,
				&"slug": StringName(slug),
				&"path": path,
				&"hash": FileAccess.get_sha256(path),
			})
		else:
			known[&"hash"] = FileAccess.get_sha256(path)
		_wire_drop(row)

	if not new_entries.is_empty():
		var entries: Array[Dictionary] = index.entries.duplicate()
		entries.append_array(new_entries)
		index.entries = entries
		index.version = int(Time.get_unix_time_from_system())
	var err := ResourceSaver.save(index, INDEX)
	assert(err == OK, "index save failed: %s" % error_string(err))

	print("relics: %d (%d newly indexed, next_id %d)" % [
		RELICS.size(), new_entries.size(), index.next_id
	])
	quit(0)


## `uid://...` for an already-imported resource. Reads the file header rather
## than the (unloaded) uid cache, so this works in a headless `-s` run.
func _uid_of(path: String) -> String:
	var id := ResourceLoader.get_resource_uid(path)
	assert(id != ResourceUID.INVALID_ID, "no uid for %s — run --import first" % path)
	return ResourceUID.id_to_text(id)


## This relic's own uid: whatever the file already carries, else a fresh one.
##
## Read straight out of the header rather than via ResourceLoader — a uid this
## tool minted on an earlier run is not in the (unloaded) cache and has never
## been through an import, so the loader reports INVALID_ID for it and every
## re-run would mint a new uid and churn all ten boss files.
func _relic_uid(path: String) -> String:
	var head := FileAccess.get_file_as_string(path).get_slice("\n", 0)
	if head.contains('uid="uid://'):
		return "uid://" + head.get_slice('uid="uid://', 1).get_slice('"', 0)
	return ResourceUID.id_to_text(ResourceUID.create_id())


## Write one relic `.tres`, matching the layout of the hand-authored jewelry.
func _write_relic(row: Array, id: int) -> void:
	var slug: String = row[0]
	var path := "%s/%s.tres" % [RELIC_DIR, slug]
	var icon := "%s/%s.png" % [ICON_DIR, slug]
	var mod_uid := _uid_of(MOD_SCRIPT)

	var mods: Array[String] = []
	var names: Array[String] = []
	var i := 0
	for pair: Array in row[5]:
		names.append('SubResource("Mod_%d")' % i)
		mods.append('[sub_resource type="Resource" id="Mod_%d"]\n' % i
			+ 'script = ExtResource("1_mod")\n'
			+ 'stat_name = "%s"\n' % pair[0]
			+ 'value = %s\n' % _num(pair[1])
			+ 'metadata/_custom_type_script = "%s"\n' % mod_uid)
		i += 1

	var text := '[gd_resource type="Resource" script_class="GearItem" format=3 uid="%s"]\n\n' % _relic_uid(path)
	text += '[ext_resource type="Script" uid="%s" path="%s" id="1_mod"]\n' % [mod_uid, MOD_SCRIPT]
	text += '[ext_resource type="Texture2D" uid="%s" path="%s" id="2_icon"]\n' % [_uid_of(icon), icon]
	text += '[ext_resource type="Script" uid="%s" path="%s" id="3_gear"]\n' % [_uid_of(GEAR_SCRIPT), GEAR_SCRIPT]
	text += '[ext_resource type="Resource" uid="%s" path="%s" id="4_slot"]\n\n' % [_uid_of(SLOT), SLOT]
	text += "\n".join(mods) + "\n"
	text += '[resource]\n'
	text += 'script = ExtResource("3_gear")\n'
	text += 'slot = ExtResource("4_slot")\n'
	# Left ungated on purpose: every relic and ring in the game is level-0, the
	# zone that drops it is the real gate, and a mastery gate would wrongly tie
	# a slot-agnostic trinket to one weapon tree.
	text += 'required_level = 0\n'
	text += 'required_mastery_categories = Array[StringName]([])\n'
	text += 'required_mastery_level = 0\n'
	text += 'base_modifiers = Array[ExtResource("1_mod")]([%s])\n' % ", ".join(names)
	text += 'item_name = &"%s"\n' % row[1]
	text += 'item_icon = ExtResource("2_icon")\n'
	text += 'description = "%s"\n' % String(row[6]).c_escape()
	text += 'can_trade = true\n'
	text += 'vendor_value = %d\n' % int(row[4])
	# One-per-slot keepsakes, not smithable stock — GearItem's default of 5 is
	# for armour you forge in batches.
	text += 'stack_limit = 1\n'
	text += 'metadata/_custom_type_script = "%s"\n' % _uid_of(GEAR_SCRIPT)
	text += 'metadata/slug = &"%s"\n' % slug
	text += 'metadata/id = %d\n' % id

	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "cannot write %s" % path)
	file.store_string(text)
	file.close()


## Value of `<name>="…"` on an `[ext_resource]` line. Matched with its leading
## space so asking for `id` does not return the `uid` — the two attributes sit on
## the same line and a bare `id="` search finds `uid="` first.
func _attr(line: String, name: String) -> String:
	var key := ' %s="' % name
	if not line.contains(key):
		return ""
	return line.get_slice(key, 1).get_slice('"', 0)


## Trailing ".0" the way Godot writes floats, so re-runs are byte-stable.
func _num(value: float) -> String:
	return "%.1f" % value if is_equal_approx(value, snappedf(value, 0.1)) else str(value)


## Insert this relic into its boss's loot table as text, replacing whatever a
## previous run left behind.
func _wire_drop(row: Array) -> void:
	var slug: String = row[0]
	var path := "%s/%s.tres" % [TYPES, row[2]]
	var abs := ProjectSettings.globalize_path(path)
	var text := FileAccess.get_file_as_string(abs)
	assert(text != "", "cannot read %s" % path)

	var drop_id := "Drop_%s" % slug
	text = _strip_previous(text, slug, drop_id)

	# The loot script's ext_resource id differs per file ("2_loot", "3_ew0xl", …).
	var loot_id := ""
	for line: String in text.split("\n"):
		if line.begins_with("[ext_resource") and line.contains(LOOT_SCRIPT):
			loot_id = _attr(line, "id")
			break
	assert(loot_id != "", "no loot_drop.gd ext_resource in %s" % path)

	var lines: PackedStringArray = text.split("\n")
	var out: PackedStringArray = []
	var last_ext := -1
	for i: int in lines.size():
		if lines[i].begins_with("[ext_resource"):
			last_ext = i
	assert(last_ext >= 0, "no ext_resource block in %s" % path)

	var inserted_sub := false
	for i: int in lines.size():
		var line: String = lines[i]
		# The drop's own sub_resource has to precede [resource] that references it.
		if not inserted_sub and line.begins_with("[resource]"):
			out.append('[sub_resource type="Resource" id="%s"]' % drop_id)
			out.append('script = ExtResource("%s")' % loot_id)
			out.append('item = ExtResource("%s")' % slug)
			out.append("chance = %s" % _num(row[3]))
			out.append("")
			inserted_sub = true
		if line.begins_with("loot = Array["):
			line = line.replace("])", ', SubResource("%s")])' % drop_id)
		out.append(line)
		if i == last_ext:
			out.append('[ext_resource type="Resource" uid="%s" path="%s/%s.tres" id="%s"]' % [
				_relic_uid("%s/%s.tres" % [RELIC_DIR, slug]), RELIC_DIR, slug, slug
			])
	assert(inserted_sub, "no [resource] block in %s" % path)

	var file := FileAccess.open(abs, FileAccess.WRITE)
	assert(file != null, "cannot write %s" % path)
	file.store_string("\n".join(out))
	file.close()
	print("  %-22s -> %-28s %.0f%%" % [slug, row[2], float(row[3]) * 100.0])


## Remove the ext_resource line, the sub_resource block and the loot-array entry
## a previous run inserted for this relic.
func _strip_previous(text: String, slug: String, drop_id: String) -> String:
	var out: PackedStringArray = []
	var lines: PackedStringArray = text.split("\n")
	var skipping := false
	for line: String in lines:
		if line.begins_with("[sub_resource") and line.contains('id="%s"' % drop_id):
			skipping = true
			continue
		if skipping:
			# Blocks run until the blank line before the next header.
			if line.begins_with("["):
				skipping = false
			else:
				continue
		if line.begins_with("[ext_resource") and line.contains("%s/%s.tres" % [RELIC_DIR, slug]):
			continue
		if line.begins_with("loot = Array["):
			line = line.replace(', SubResource("%s")' % drop_id, "")
		out.append(line)
	# Strip left a trailing blank where the sub_resource block used to sit.
	var joined := "\n".join(out)
	return joined.replace("\n\n\n", "\n\n")
