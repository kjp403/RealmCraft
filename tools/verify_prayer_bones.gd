extends Node

## Guards the Prayer bone economy, whose two halves are authored in places that
## never see each other: the XP is one number in altar_offerings.tres, and the
## supply is a max_amount buried in every boss's loot table. Raising one without
## the other is how 99 Prayer ends up either trivial or unreachable, and neither
## shows up until someone grinds it.
##
##   godot --path . --mode=client res://tools/verify_prayer_bones.tscn
##
## Scene mode, not `-s`: AltarOfferingTable reaches Item, which pulls autoloads
## a bare SceneTree run does not provide -- the same reason
## verify_high_tier_arrows runs as a scene.
##
## Regular and big bones are DELIBERATELY left low: they are meant to be potion
## inputs, with dragon bones carrying Prayer XP from bosses. They are pinned
## here so a future "bones give nothing" bug report does not get 'fixed' by
## quietly reversing that decision.

const ALTAR := "res://source/common/gameplay/prayer/resources/altar_offerings.tres"
const NPC_DIR := "res://source/common/gameplay/characters/npc/types"

## slug -> exact XP the altar must pay.
const EXPECT_XP: Dictionary = {
	&"bone": 109,
	&"big_bones": 326,
	&"dragon_bones": 9000,
}
## No single kill may hand out more than this many dragon bones.
const MAX_DRAGON_BONES_PER_KILL: int = 1

var _bad: int = 0


func _fail(msg: String) -> void:
	_bad += 1
	print("  FAIL ", msg)


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	_check_altar()
	_check_boss_drops()
	print("PRAYER_BONES bad=", _bad)
	if _bad == 0:
		print("VERIFY_PASS prayer_bones")
	get_tree().quit(0)


func _check_altar() -> void:
	var table: Resource = load(ALTAR)
	if table == null:
		_fail("could not load " + ALTAR)
		return
	var seen: Dictionary = {}
	for offering: Resource in table.get(&"offerings"):
		if offering == null or offering.get(&"item") == null:
			_fail("altar has an empty offering row")
			continue
		var slug: StringName = StringName(offering.get(&"item").get_meta(&"slug", &""))
		var xp: int = int(offering.get(&"xp"))
		seen[slug] = xp
		if not EXPECT_XP.has(slug):
			print("ok  %-14s %d xp (unpinned)" % [slug, xp])
			continue
		if xp != int(EXPECT_XP[slug]):
			_fail("%s pays %d xp, expected %d" % [slug, xp, EXPECT_XP[slug]])
			continue
		print("ok  %-14s %d xp" % [slug, xp])
	for slug: StringName in EXPECT_XP:
		if not seen.has(slug):
			_fail("altar has no offering for %s" % slug)

	# The cap is the reason the number matters: state it, so a future edit sees
	# what it is really changing.
	var dragon: int = int(seen.get(&"dragon_bones", 0))
	if dragon > 0:
		print("    99 Prayer = %d dragon bones (%d boss kills at %d/kill)" % [
			ceili(13034431.0 / float(dragon)),
			ceili(13034431.0 / float(dragon) / float(MAX_DRAGON_BONES_PER_KILL)),
			MAX_DRAGON_BONES_PER_KILL,
		])


## Loot tables are scanned as TEXT rather than loaded: an NPC .tres pulls the
## HostileNpc script and its scene dependencies, which a `-s` run has no
## autoloads for. The drop amount is a literal in the file either way.
func _check_boss_drops() -> void:
	var checked: int = 0
	for path: String in _tres_under(NPC_DIR):
		var text: String = FileAccess.get_file_as_string(path)
		if not text.contains("dragon_bones"):
			continue
		# Resolve the ext_resource id the dragon-bone rows point at.
		var bone_ids: Array[String] = []
		for m: RegExMatch in _re(r'\[ext_resource[^\]]*path="[^"]*dragon_bones\.tres"[^\]]*id="([^"]+)"').search_all(text):
			bone_ids.append(m.get_string(1))
		if bone_ids.is_empty():
			continue
		checked += 1
		for block: String in text.split("[sub_resource"):
			var uses_bone: bool = false
			for id: String in bone_ids:
				if block.contains('item = ExtResource("%s")' % id):
					uses_bone = true
			if not uses_bone:
				continue
			var amount: int = 1
			var found: RegExMatch = _re(r"max_amount = (\d+)").search(block)
			if found != null:
				amount = int(found.get_string(1))
			if amount > MAX_DRAGON_BONES_PER_KILL:
				_fail("%s drops up to %d dragon bones, cap is %d"
					% [path.get_file(), amount, MAX_DRAGON_BONES_PER_KILL])
	print("ok  %d npcs drop dragon bones, none above %d per kill"
		% [checked, MAX_DRAGON_BONES_PER_KILL])


func _re(pattern: String) -> RegEx:
	var rx := RegEx.new()
	rx.compile(pattern)
	return rx


func _tres_under(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		_fail("could not open " + dir_path)
		return out
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var full: String = dir_path.path_join(entry)
		if dir.current_is_dir():
			out.append_array(_tres_under(full))
		elif entry.ends_with(".tres"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return out
