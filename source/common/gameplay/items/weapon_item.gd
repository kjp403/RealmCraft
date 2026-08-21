class_name WeaponItem
extends GearItem


## Mastery category this weapon belongs to (&"sword", &"bow", &"wand",
## &"hammer"). Killing with it earns mastery xp for the category; empty = no
## mastery (tools, special-case weapons). See docs/mastery.md.
@export var category: StringName
## Legacy "power" flavor number shown on tooltips. Abilities are no longer
## gated by this budget — mastery level + ownership decide what channels.
@export_range(0, 5) var capacity: int = 0

@export var right_hand_scene: PackedScene

@export var left_hand_scene: PackedScene

## Optional per-skin nudge for the in-hand sprite, when a skin's art sits
## differently than the type scene's default (e.g. a taller blade). ZERO =
## use the scene's placement as-is. See Weapon.apply_skin.
@export var sprite_offset: Vector2 = Vector2.ZERO


func inventory_tab() -> InventoryTab:
	return InventoryTab.WEAPON


## Weapons section by mastery category (&"sword" -> its own "Swords" section);
## uncategorized ones share a generic bucket.
func group_key() -> StringName:
	return category if not category.is_empty() else &"weapons"


func sort_key() -> Array:
	return [String(category), required_mastery_level, required_level, String(item_name)]


func stat_lines() -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	# Mastery weapons lead with type. Tools (empty category) skip it.
	if not category.is_empty():
		lines.append({"text": String(category).capitalize(), "kind": &"weapon"})
	lines.append_array(super())
	return lines


func equip(character: Character) -> void:
	super.equip(character)

	if right_hand_scene:
		var right_hand_weapon: Weapon = right_hand_scene.instantiate()
		right_hand_weapon.character = character
		character.equipment_component.mounted_nodes[slot.key] = right_hand_weapon
		character.right_hand_spot.add_child(right_hand_weapon)
		# Skin the in-hand sprite from this item's icon, so one type-scene
		# (sword.tscn) serves every sword skin (fire, rustic, ...).
		right_hand_weapon.apply_skin(item_icon, sprite_offset, shimmer_material())
		# Ascended cosmetic glow, if this character has it equipped AND this weapon
		# has an authored effect. Both checks live in one place so a remount can
		# never leave a stale overlay behind.
		right_hand_weapon.apply_cosmetic_fx(_cosmetic_fx_for(character))
	
	if left_hand_scene:
		var left_hand_weapon: Weapon = left_hand_scene.instantiate()
		left_hand_weapon.character = character
		character.left_hand_spot.add_child(left_hand_weapon)
	else:
		if character.left_hand_spot.get_child_count():
			character.left_hand_spot.get_child(0).queue_free()
			#character.left_hand_spot.remove_child(character.left_hand_spot.get_child(0))


## Overlay frames for this item on this character, or null. Null whenever the
## character has no weapon cosmetic equipped, or this weapon is not Ascended.
func _cosmetic_fx_for(character: Character) -> SpriteFrames:
	if character == null or not Cosmetics.is_weapon_slot(character.weapon_cosmetic_id):
		return null
	return Cosmetics.weapon_fx_for(item_icon)


func unequip(character: Character) -> void:
	super.unequip(character)

	var weapon: Node = character.equipment_component.mounted_nodes.get(slot.key, null)
	if weapon:
		weapon.queue_free()
	character.equipment_component.mounted_nodes.erase(slot.key)
	for child in character.left_hand_spot.get_children():
		child.queue_free()
