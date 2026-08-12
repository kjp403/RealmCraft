class_name SkillToolsGuide
extends RefCounted
## Builds skill-gated ToolItem lists for Skills → Mining / Woodcutting /
## Farming / Fishing "Tools" tabs. Loads items on demand (after Client is up)
## so JobRegistry preload stays free of weapon scenes.


## Skill slug → gathering tool_type that belongs on that skill's Tools tab.
const SKILL_TOOL_TYPES := {
	&"mining": &"pickaxe",
	&"woodcutting": &"axe",
	&"harvesting": &"sickle",
	&"fishing": &"fishing_rod",
}

## skill -> Array[Dictionary] of { "item": ToolItem, "level": int }
static var _tools_cache: Dictionary = {}


static func has_tools(skill: StringName) -> bool:
	return SKILL_TOOL_TYPES.has(skill)


## All ToolItems for [param skill], sorted by required_skill_level then name.
## Entries are { "item": ToolItem, "level": int }.
static func tools_for(skill: StringName) -> Array[Dictionary]:
	if _tools_cache.has(skill):
		return _tools_cache[skill] as Array[Dictionary]

	var out: Array[Dictionary] = []
	var want_type: StringName = SKILL_TOOL_TYPES.get(skill, &"")
	if want_type == &"":
		return out
	var index: ContentIndex = load(
		"res://source/common/registry/indexes/items_index.tres"
	) as ContentIndex
	if index == null:
		return out
	for entry: Dictionary in index.entries:
		var path: String = str(entry.get(&"path", entry.get("path", "")))
		if path.find("/weapons/tools/") < 0:
			continue
		if path.ends_with(".tscn"):
			continue
		var res: Resource = ResourceLoader.load(path)
		var tool: ToolItem = res as ToolItem
		if tool == null:
			continue
		if tool.tool_type != want_type:
			continue
		# Prefer the authored skill gate; fall back to 0 for wood starters
		# that omit required_skill (wooden pickaxe / axe).
		var lvl: int = int(tool.required_skill_level)
		if tool.required_skill != &"" and tool.required_skill != skill:
			continue
		out.append({"item": tool, "level": lvl})
	out.sort_custom(_sort_by_level_then_name)
	_tools_cache[skill] = out
	return out


## Compact bonus blurb for a Tools-tab row (yield / power / speed).
static func bonus_blurb(tool: ToolItem) -> String:
	if tool == null:
		return ""
	var parts: PackedStringArray = []
	if tool.bonus_yield_chance > 0.0:
		parts.append("+%d%% double resources" % roundi(tool.bonus_yield_chance * 100.0))
	if tool.tool_type == &"fishing_rod":
		if tool.extraction_damage > 0:
			parts.append("Catch power %d" % tool.extraction_damage)
		if tool.swing_cooldown > 0.0 and tool.swing_cooldown < 0.49:
			parts.append("Faster casts")
	elif tool.extraction_damage > 1:
		parts.append("Gather power %d" % tool.extraction_damage)
	return " · ".join(parts)


static func _sort_by_level_then_name(a: Dictionary, b: Dictionary) -> bool:
	var la: int = int(a["level"])
	var lb: int = int(b["level"])
	if la != lb:
		return la < lb
	var ia: Item = a["item"] as Item
	var ib: Item = b["item"] as Item
	return String(ia.item_name) < String(ib.item_name)
