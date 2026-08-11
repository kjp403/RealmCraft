extends ChatCommand
## Turns off /godmode, restoring the HP/Mana/AD snapshot taken when godmode was
## enabled. Self only.


const META_SNAPSHOT: StringName = &"godmode_snapshot"


func _init() -> void:
	command_name = "godmodeoff"
	command_priority = 100 # senior_admin+
	command_usage = "/godmodeoff [self]"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() > 2:
		return "Usage: " + command_usage
	if args.size() == 2 and args[1].strip_edges().to_lower() != "self":
		return "Godmodeoff can only be used on yourself (self)."

	var target: CommandTarget.Result = CommandTarget.resolve("self", peer_id, server_instance)
	if not target.ok:
		return target.error
	var player: Player = CommandTarget.player_node(target, server_instance)
	if player == null:
		return "You must be online."

	if not player.has_meta(META_SNAPSHOT):
		return "Godmode is not active."

	var snapshot: Dictionary = player.get_meta(META_SNAPSHOT)
	player.remove_meta(META_SNAPSHOT)
	var stats: StatsComponent = player.stats_component
	var health_max: float = float(snapshot.get("health_max", PlayerResource.BASE_STATS[Stat.HEALTH_MAX]))
	var mana_max: float = float(snapshot.get("mana_max", PlayerResource.BASE_STATS[Stat.MANA_MAX]))
	var ad: float = float(snapshot.get("ad", PlayerResource.BASE_STATS[Stat.AD]))
	stats.set_stat(Stat.HEALTH_MAX, health_max)
	stats.set_stat(Stat.MANA_MAX, mana_max)
	stats.set_stat(Stat.AD, ad)
	stats.set_stat(Stat.HEALTH, minf(float(snapshot.get("health", health_max)), health_max))
	stats.set_stat(Stat.MANA, minf(float(snapshot.get("mana", mana_max)), mana_max))
	return "Godmode OFF — stats restored."
