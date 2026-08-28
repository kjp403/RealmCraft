@tool
extends Node
## Gate for the ability-icon set: every ability and every mastery node must carry
## its OWN icon, and that icon must actually load.
##
## Three failures this catches, all of which look fine in the editor:
##
## 1. A missing icon. The HUD degrades to the ability's initials, so an ability
##    with no art still "works" and nobody notices until a screenshot.
## 2. A SHARED icon. Two different abilities drawing the same glyph is the bug
##    the Raven pass fixed — Aftershock borrowed Frost Nova's art, Blood Feast
##    borrowed Berserk's, and four bow passives all drew Juggernaut's heart.
##    Ranks of one chain are exempt: a chain is supposed to read as one move.
## 3. A dangling path. Deleting a superseded icon while a .tres still points at
##    it loads null, which is indistinguishable from case 1 at runtime.
##
## Run: godot --headless --path . tools/verify_ability_icons.tscn

const ABILITY_DIR: String = "res://source/common/gameplay/combat/ability/ability_collection"

var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_check_abilities()
	_check_mastery_nodes()
	_finish()


## Every ability .tres in the collection carries a loadable icon, and no two
## abilities share one.
func _check_abilities() -> void:
	var by_icon: Dictionary = {} # texture path -> first slug that claimed it
	var count: int = 0
	for path: String in _collect(ABILITY_DIR):
		var ability: AbilityResource = load(path) as AbilityResource
		if ability == null:
			continue
		count += 1
		var slug: String = path.get_file().get_basename()
		if not _check(ability.icon != null, "%s has an icon" % slug):
			continue
		var art: String = ability.icon.resource_path
		if by_icon.has(art):
			_check(false, "%s has its OWN icon (shares %s with %s)" % [
				slug, art.get_file(), by_icon[art]
			])
		else:
			by_icon[art] = slug
	_check(count > 100, "the ability collection loaded (%d resources)" % count)
	print("  --   %d abilities, %d distinct icons" % [count, by_icon.size()])


## Every mastery node resolves an icon: ability nodes inherit their ability's,
## passives carry their own. Sharing is allowed only WITHIN one upgrade chain.
func _check_mastery_nodes() -> void:
	for category: StringName in MasteryService.trees():
		var tree: MasteryTreeResource = MasteryService.trees()[category]
		var by_icon: Dictionary = {} # texture path -> chain root that claimed it
		for node: MasteryNode in tree.nodes:
			var art: Texture2D = node.icon
			if art == null and node.ability != null:
				art = node.ability.icon
			if not _check(art != null, "%s/%s resolves an icon" % [category, node.id]):
				continue
			var chain: String = String(MasteryService.chain_root_of(tree, node))
			var key: String = art.resource_path
			if by_icon.has(key) and by_icon[key] != chain:
				_check(false, "%s/%s has its OWN icon (shares %s with the %s chain)" % [
					category, node.id, key.get_file(), by_icon[key]
				])
			else:
				by_icon[key] = chain


func _collect(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full: String = dir_path.path_join(entry)
			if dir.current_is_dir():
				out.append_array(_collect(full))
			elif entry.ends_with(".tres"):
				out.append(full)
		entry = dir.get_next()
	return out


func _check(ok: bool, what: String) -> bool:
	if not ok:
		print("  FAIL " + what)
		_failures.append(what)
	return ok


func _finish() -> void:
	if _failures.is_empty():
		print("VERIFY_PASS")
	else:
		print("VERIFY_FAIL: %d" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
