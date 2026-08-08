extends ChatCommand
## Set a profession skill level (Mining / Woodcutting / …) for testing.
## Accepts job slugs or common aliases (farming → harvesting, crafting → outfitting).
## `/skill self all 99` maxes every registered job.


## Friendly aliases → JobRegistry slugs.
const ALIASES: Dictionary[StringName, StringName] = {
	&"farming": &"harvesting",
	&"farm": &"harvesting",
	&"harvest": &"harvesting",
	&"crafting": &"outfitting",
	&"craft": &"outfitting",
	&"outfit": &"outfitting",
	&"woodcut": &"woodcutting",
	&"fish": &"fishing",
	&"cook": &"cooking",
	&"mine": &"mining",
	&"smith": &"smithing",
}


func _init() -> void:
	command_name = "skill"
	command_priority = 100 # senior_admin
	command_usage = "/skill <self|@account|#id> <skill|all> <level>"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 4:
		return "Usage: " + command_usage

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if not target.online:
		return "%s must be online." % target.label()

	var level: int = args[3].to_int()
	if level < 1 or level > SkillXp.LEVEL_CAP:
		return "Level must be between 1 and %d." % SkillXp.LEVEL_CAP

	var token: String = args[2].to_lower()
	var res: PlayerResource = target.resource

	if token == "all":
		var names: PackedStringArray = PackedStringArray()
		for job_slug: StringName in JobRegistry.JOBS:
			_set_skill_level(res, job_slug, level)
			names.append(JobRegistry.display_name(job_slug))
		server_instance.world_server.database.save_player(res)
		return "Set all skills for %s to level %d (%s)." % [
			target.label(), level, ", ".join(names)
		]

	var skill_name: StringName = _resolve_skill(StringName(token))
	if skill_name == &"":
		return "Unknown skill '%s'. Try: mining, smithing, woodcutting, fishing, cooking, farming, crafting, or all." % args[2]

	_set_skill_level(res, skill_name, level)
	server_instance.world_server.database.save_player(res)
	return "Set %s %s to level %d." % [
		target.label(), JobRegistry.display_name(skill_name), level
	]


func _resolve_skill(token: StringName) -> StringName:
	if JobRegistry.has_job(token):
		return token
	if ALIASES.has(token):
		return ALIASES[token]
	# Match display names ("Farming", "Crafting") case-insensitively.
	for job_slug: StringName in JobRegistry.JOBS:
		if String(JobRegistry.display_name(job_slug)).to_lower() == String(token):
			return job_slug
	return &""


func _set_skill_level(res: PlayerResource, skill_name: StringName, level: int) -> void:
	var skill: Dictionary = res.get_skill(skill_name)
	skill["level"] = level
	skill["xp"] = 0
