class_name MasteryEquipmentGuide
extends RefCounted
## Builds mastery-gated weapon lists for the Skills → Combat guide.
## Loads WeaponItems on demand (after Client is up) so JobRegistry preload
## stays free of weapon scenes.


const CATEGORY_ORDER: Array[StringName] = [
	&"sword",
	&"hammer",
	&"bow",
	&"wand",
	&"book",
]

## Display labels matching the Combat tab (Swordsmanship, etc.).
static func display_name_for(category: StringName) -> String:
	var tree: MasteryTreeResource = MasteryService.tree_for(category)
	if tree != null and not tree.display_name.is_empty():
		return tree.display_name
	return String(category).capitalize()


## All WeaponItems that use [param category] for mastery XP / equip gates,
## sorted by required_mastery_level then name. Includes wood (level 0).
static func weapons_for(category: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var index: ContentIndex = load(
		"res://source/common/registry/indexes/items_index.tres"
	) as ContentIndex
	if index == null:
		return out
	for entry: Dictionary in index.entries:
		var path: String = str(entry.get(&"path", entry.get("path", "")))
		if path.find("/weapons/") < 0:
			continue
		if path.ends_with(".tscn"):
			continue
		var res: Resource = ResourceLoader.load(path)
		var weapon: WeaponItem = res as WeaponItem
		if weapon == null:
			continue
		if not _matches_category(weapon, category):
			continue
		var lvl: int = int(weapon.required_mastery_level)
		out.append({"item": weapon, "level": lvl})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var la: int = int(a["level"])
		var lb: int = int(b["level"])
		if la != lb:
			return la < lb
		var ia: Item = a["item"] as Item
		var ib: Item = b["item"] as Item
		return String(ia.item_name) < String(ib.item_name)
	)
	return out


static func _matches_category(weapon: WeaponItem, category: StringName) -> bool:
	if weapon.category == category:
		return true
	for cat: StringName in weapon.required_mastery_categories:
		if cat == category:
			return true
	return false
