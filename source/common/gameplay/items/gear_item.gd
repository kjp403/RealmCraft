class_name GearItem
extends Item

# Armor renders in body order, not alphabetically.
const _SLOT_ORDER: Dictionary = {
	&"weapon": 0, &"helmet": 1, &"torso": 2, &"boot": 3, &"ring": 4, &"relic": 5,
	&"ammo": 6,
}

## Character-level gate (mostly legacy). Armor sets use mastery instead.
@export_range(0, 99, 1.0, "suffix:lvl") var required_level: int = 0
## Mastery tree(s) that unlock this piece. Empty = no mastery gate.
## Multiple entries = any-of (e.g. wand OR book for cloth). Use &"any" for
## universal endgame sets (Ancient) that accept any trained mastery.
@export var required_mastery_categories: Array[StringName] = []
@export_range(0, 99, 1.0, "suffix:mstr") var required_mastery_level: int = 0

@export var slot: ItemSlot

## Main Stats (Base stats)
@export var base_modifiers: Array[StatModifier]
func _init() -> void:
	# Smithable gear stacks (armor / weapons); tools override to 1 in their .tres.
	stack_limit = 5


func inventory_tab() -> InventoryTab:
	return InventoryTab.ARMOR


## Armor sections by SET, derived from the "<Set> <Piece>" naming convention
## (Iron Helmet -> &"iron"). KEEP that convention when authoring gear; if a
## multi-word set name ever lands, promote this to an explicit set_key export.
## Rings/relics are upgrade chains, not sets — they get their own sections.
func group_key() -> StringName:
	if slot and slot.key == &"ring":
		return &"rings"
	if slot and slot.key == &"relic":
		return &"relics"
	var set_word: String = String(item_name).get_slice(" ", 0)
	return StringName(set_word.to_lower()) if not set_word.is_empty() else &"armor"


func sort_key() -> Array:
	var slot_rank: int = _SLOT_ORDER.get(slot.key if slot else &"", 9)
	return [slot_rank, required_mastery_level, required_level, String(item_name)]


func stat_lines() -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	for modifier: StatModifier in base_modifiers:
		if modifier == null or is_zero_approx(modifier.value):
			continue
		lines.append({"text": _format_modifier(modifier), "stat": StringName(modifier.stat_name)})
	# The req_* keys carry the gate itself so the tooltip can colour it against the
	# viewing player — a requirement the player already meets shouldn't read as a
	# blocker (see ItemTooltip._requirement_met).
	if required_mastery_level > 0 and not required_mastery_categories.is_empty():
		lines.append({
			"text": "Requires %s mastery %d" % [_mastery_label(), required_mastery_level],
			"kind": &"level",
			"req_kind": &"mastery",
		})
	elif required_level > 0:
		lines.append({
			"text": "Requires level %d" % required_level,
			"kind": &"level",
			"req_char_level": required_level,
		})
	return lines


func _mastery_label() -> String:
	if required_mastery_categories.has(&"any"):
		return "any"
	var names: PackedStringArray = PackedStringArray()
	for category: StringName in required_mastery_categories:
		names.append(String(category).capitalize())
	return " / ".join(names)


## "+5 Attack Damage" / "-3 Armor". Integer when whole, else one decimal.
static func _format_modifier(modifier: StatModifier) -> String:
	var value: float = modifier.value
	var number: String = ("%+d" % int(value)) if is_equal_approx(value, roundf(value)) else ("%+.1f" % value)
	return "%s %s" % [number, Stat.display_name(modifier.stat_name)]


func can_equip(player: Player) -> bool:
	if player == null or player.player_resource == null or slot == null:
		return false
	if not slot.is_unlocked_for(player.player_resource):
		return false
	if player.player_resource.level < required_level:
		return false
	return meets_mastery_requirement(player.player_resource)


## True when mastery gate is empty or the player has the required level in one
## of the listed categories (&"any" = highest mastery across all trees).
func meets_mastery_requirement(res: PlayerResource) -> bool:
	if res == null:
		return false
	if required_mastery_level <= 0 or required_mastery_categories.is_empty():
		return true
	if required_mastery_categories.has(&"any"):
		var best: int = 0
		# Prefer practiced entries on the player; also scan known trees so a
		# /mastery-set category that matches a tree is counted.
		for existing: Variant in res.masteries.keys():
			best = maxi(best, res.mastery_level_of(StringName(str(existing))))
		for category: StringName in MasteryService.trees():
			best = maxi(best, res.mastery_level_of(category))
		return best >= required_mastery_level
	for category: StringName in required_mastery_categories:
		if res.mastery_level_of(category) >= required_mastery_level:
			return true
	return false


## Same gate evaluated against a flat {category: level} map, for callers with no
## PlayerResource to hand. The CLIENT is exactly that case — player_resource is
## assigned server-side only, so client tooltips read ClientState's mastery
## mirror through here instead of silently failing every gate (which painted
## every wear requirement red, met or not).
func meets_mastery_levels(levels: Dictionary) -> bool:
	if required_mastery_level <= 0 or required_mastery_categories.is_empty():
		return true
	if required_mastery_categories.has(&"any"):
		var best: int = 1
		for slug: Variant in levels:
			best = maxi(best, int(levels[slug]))
		return best >= required_mastery_level
	for category: StringName in required_mastery_categories:
		# Missing = never practiced = level 1 (PlayerResource.mastery_level_of).
		if maxi(1, int(levels.get(String(category), 1))) >= required_mastery_level:
			return true
	return false


func equip(_character: Character) -> void:
	# Visual / mount hooks live on WeaponItem and Item. Combat stats from
	# base_modifiers are applied by EquipmentComponent's gear ledger so
	# unequip can't leave orphaned boosts behind.
	pass


func unequip(_character: Character) -> void:
	pass
