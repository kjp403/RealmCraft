extends SceneTree
## Quick check that SkillToolsGuide returns tools + blurbs for gathering skills.


func _initialize() -> void:
	var skills: Array[StringName] = [
		&"mining", &"woodcutting", &"harvesting", &"fishing"
	]
	var failed := false
	for skill: StringName in skills:
		if not SkillToolsGuide.has_tools(skill):
			push_error("missing tools mapping for %s" % skill)
			failed = true
			continue
		var entries: Array[Dictionary] = SkillToolsGuide.tools_for(skill)
		print("%s tools=%d" % [skill, entries.size()])
		if entries.is_empty():
			push_error("no tools for %s" % skill)
			failed = true
			continue
		for entry: Dictionary in entries:
			var tool: ToolItem = entry.get("item", null) as ToolItem
			var lvl: int = int(entry.get("level", 0))
			var blurb: String = SkillToolsGuide.bonus_blurb(tool)
			print("  Lv %d %s | %s" % [lvl, tool.item_name, blurb])
			if tool.item_icon == null:
				push_error("missing icon on %s" % tool.item_name)
				failed = true
	if failed:
		print("VERIFY_FAIL")
		quit(1)
	else:
		print("VERIFY_PASS")
		quit(0)
