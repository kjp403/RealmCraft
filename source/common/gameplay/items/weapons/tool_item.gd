class_name ToolItem
extends WeaponItem
## A gathering tool (pickaxe, axe, fishing rod, ...). Equips in the weapon slot like
## any weapon (so it reuses the whole equip path), but is identified by its tool_type
## so gathering nodes can require a matching tool. Carries no special combat behavior
## by default — it can still define hand scenes for a visible in-hand tool.

## What this tool can gather, e.g. &"pickaxe", &"axe". A MineableNode requires a
## matching tool_type to be worked.
@export var tool_type: StringName
## Extraction damage applied to gather nodes per swing (fish holes, ore, trees).
## Higher = fewer swings to catch/yield. -1 = leave the swing ability's default.
@export var extraction_damage: int = -1
## Primary-swing cooldown override in seconds. Lower = faster casts.
## -1 = leave the swing ability's default.
@export var swing_cooldown: float = -1.0
## Optional profession skill gate (e.g. &"fishing"). Empty = no skill gate.
@export var required_skill: StringName = &""
@export_range(0, 99, 1.0, "suffix:lvl") var required_skill_level: int = 0
## Extra chance to yield +1 resource on a successful gather (0.0–1.0). Stacks
## with job perk / level bonus yield, still soft-capped by JobPerks.abs_max.
@export_range(0.0, 0.5, 0.01) var bonus_yield_chance: float = 0.0


func group_key() -> StringName:
	return &"tools"


func sort_key() -> Array:
	return [String(tool_type), required_skill_level, required_level, String(item_name)]


func can_equip(player: Player) -> bool:
	if not super.can_equip(player):
		return false
	if required_skill != &"" and required_skill_level > 0:
		var skill: Dictionary = player.player_resource.get_skill(required_skill)
		if int(skill.get("level", 1)) < required_skill_level:
			return false
	return true


func equip(character: Character) -> void:
	super.equip(character)
	_apply_swing_stats(character)


## Push per-item gather stats onto the equipped swing ability (server + client).
func _apply_swing_stats(character: Character) -> void:
	if character == null or character.equipment_component == null or slot == null:
		return
	var weapon: Node = character.equipment_component.mounted_nodes.get(slot.key, null)
	var mounted: Weapon = weapon as Weapon
	if mounted == null:
		return
	for ability: AbilityResource in mounted.abilities:
		if ability is PickSwingAbility:
			var swing: PickSwingAbility = ability as PickSwingAbility
			# Gathering tools never deal combat damage — mining/woodcutting near
			# mobs must not aggro (pickaxe, axe, sickle, fishing rod).
			swing.character_damage = 0.0
			if extraction_damage > 0:
				swing.extraction_damage = extraction_damage
			if swing_cooldown > 0.0:
				swing.cooldown = swing_cooldown


func stat_lines() -> Array[Dictionary]:
	var lines: Array[Dictionary] = super()
	if required_skill != &"" and required_skill_level > 0:
		# req_skill/req_skill_level let the tooltip check the gate against the
		# viewing player instead of painting every requirement as unmet — a
		# fresh character is already Woodcutting 1, so "Requires Woodcutting 1"
		# has no business rendering red.
		lines.append({
			"text": "Requires %s Lv %d" % [
				JobRegistry.display_name(required_skill),
				required_skill_level,
			],
			"kind": &"level",
			"req_skill": required_skill,
			"req_skill_level": required_skill_level,
		})
	if bonus_yield_chance > 0.0:
		lines.append({
			"text": "+%d%% double resources" % roundi(bonus_yield_chance * 100.0),
			"kind": &"weapon",
		})
	if tool_type == &"fishing_rod" and extraction_damage > 0:
		lines.append({"text": "Catch power %d" % extraction_damage, "kind": &"weapon"})
		if swing_cooldown > 0.0 and swing_cooldown < 0.49:
			lines.append({"text": "Faster casts", "kind": &"weapon"})
	elif extraction_damage > 1:
		lines.append({"text": "Gather power %d" % extraction_damage, "kind": &"weapon"})
	return lines
