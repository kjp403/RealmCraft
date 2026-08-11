class_name MasteryEquipmentGuide
extends RefCounted
## Builds mastery-gated weapon / armor lists for the Skills → Combat guide.
## Loads items on demand (after Client is up) so JobRegistry preload stays
## free of weapon scenes.


const CATEGORY_ORDER: Array[StringName] = [
	&"sword",
	&"hammer",
	&"bow",
	&"wand",
	&"book",
	&"armor",
]

const ARMOR_CATEGORY := &"armor"

## Display labels matching the Combat tab (Swordsmanship, etc.).
static func display_name_for(category: StringName) -> String:
	if category == ARMOR_CATEGORY:
		return "Armor"
	var tree: MasteryTreeResource = MasteryService.tree_for(category)
	if tree != null and not tree.display_name.is_empty():
		return tree.display_name
	return String(category).capitalize()


## All WeaponItems that use [param category] for mastery XP / equip gates,
## sorted by required_mastery_level then name. Includes wood (level 0).
static func weapons_for(category: StringName) -> Array[Dictionary]:
	if category == ARMOR_CATEGORY:
		return armor_for()
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
	out.sort_custom(_sort_by_level_then_name)
	return out


## Every wearable armor piece (helmet / torso / boots). Jewelry, rings, and
## silver plate (jewelry-only metal) are excluded. Level is mastery req when
## set, else character [member GearItem.required_level] (0 → shown as Any).
static func armor_for() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var index: ContentIndex = load(
		"res://source/common/registry/indexes/items_index.tres"
	) as ContentIndex
	if index == null:
		return out
	for entry: Dictionary in index.entries:
		var path: String = str(entry.get(&"path", entry.get("path", "")))
		if path.find("/gears/") < 0:
			continue
		if path.find("/jewelry/") >= 0 or path.find("/rings/") >= 0:
			continue
		# Silver is jewelry-only — keep amulets/rings, drop silver plate.
		var base: String = path.get_file().get_basename()
		if base.begins_with("silver_"):
			continue
		if path.ends_with(".tscn"):
			continue
		var res: Resource = ResourceLoader.load(path)
		var gear: GearItem = res as GearItem
		if gear == null or gear is WeaponItem:
			continue
		if gear.slot == null:
			continue
		var slot_key: StringName = gear.slot.key
		if slot_key != &"helmet" and slot_key != &"torso" and slot_key != &"boot":
			continue
		var lvl: int = int(gear.required_mastery_level)
		if lvl <= 0:
			lvl = int(gear.required_level)
		out.append({"item": gear, "level": lvl})
	out.sort_custom(_sort_by_level_then_name)
	return out


static func _sort_by_level_then_name(a: Dictionary, b: Dictionary) -> bool:
	var la: int = int(a["level"])
	var lb: int = int(b["level"])
	if la != lb:
		return la < lb
	var ia: Item = a["item"] as Item
	var ib: Item = b["item"] as Item
	return String(ia.item_name) < String(ib.item_name)


static func _matches_category(weapon: WeaponItem, category: StringName) -> bool:
	if weapon.category == category:
		return true
	for cat: StringName in weapon.required_mastery_categories:
		if cat == category:
			return true
	return false
