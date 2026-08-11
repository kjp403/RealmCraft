extends ChatCommand
## Senior-admin / owner: reset every profession skill to level 1 (xp 0). Works on
## self or another online player. Use this after testing with /skill /setlevel so
## grind progression can be re-checked from a fresh character state.


func _init() -> void:
	command_name = "resetstats"
	command_priority = 100 # senior_admin+
	command_usage = "/resetstats <self|@account|#id>"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 2:
		return "Usage: " + command_usage

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if not target.online:
		return "%s must be online." % target.label()

	var res: PlayerResource = target.resource
	var names: PackedStringArray = PackedStringArray()
	for job_slug: StringName in JobRegistry.JOBS:
		var skill: Dictionary = res.get_skill(job_slug)
		skill["level"] = 1
		skill["xp"] = 0
		names.append(JobRegistry.display_name(job_slug))

	server_instance.world_server.database.save_player(res)
	_push_skills(target, server_instance)
	return "Reset all skills for %s to level 1 (%s)." % [target.label(), ", ".join(names)]


## Push a skills.get-shaped payload so open Skills panels refresh immediately.
func _push_skills(target: CommandTarget.Result, server_instance: ServerInstance) -> void:
	if target.peer_id <= 0:
		return
	var out: Dictionary = {}
	for skill_name: StringName in JobRegistry.JOBS:
		var jp: JobPerks = JobRegistry.JOBS[skill_name]
		var entry: Dictionary = target.resource.get_skill(skill_name)
		var level: int = int(entry.get("level", 1))
		out[String(skill_name)] = {
			"level": level,
			"xp": int(entry.get("xp", 0)),
			"xp_to_next": target.resource.skill_xp_to_next(level),
			"display_name": jp.display_name if jp != null else String(skill_name).capitalize(),
			"category": String(jp.category) if jp != null else "",
			"perks": entry.get("perks", {}),
		}
	server_instance.world_server.data_push.rpc_id(target.peer_id, &"skills.get", {"skills": out})
