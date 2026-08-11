extends ChatCommand
## Senior-admin / owner self-buff for testing: 10,000,000 HP + Mana (full) and
## +10,000 Attack Damage. Self only — cannot grant godmode to anyone else.
## Pair with /godmodeoff to restore the pre-buff snapshot.


const META_SNAPSHOT: StringName = &"godmode_snapshot"
const GOD_POOL: float = 10_000_000.0
const GOD_AD_BONUS: float = 10_000.0


func _init() -> void:
	command_name = "godmode"
	command_priority = 100 # senior_admin+
	command_usage = "/godmode [self]"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() > 2:
		return "Usage: " + command_usage
	if args.size() == 2 and args[1].strip_edges().to_lower() != "self":
		return "Godmode can only be used on yourself (self)."

	var target: CommandTarget.Result = CommandTarget.resolve("self", peer_id, server_instance)
	if not target.ok:
		return target.error
	var player: Player = CommandTarget.player_node(target, server_instance)
	if player == null:
		return "You must be online."

	var stats: StatsComponent = player.stats_component
	if player.has_meta(META_SNAPSHOT):
		# Already on — refresh pools to full without stacking another +AD.
		stats.set_stat(Stat.HEALTH, GOD_POOL)
		stats.set_stat(Stat.MANA, GOD_POOL)
		return "Godmode already active — HP/Mana topped up."

	var snapshot: Dictionary = {
		"health_max": stats.get_stat(Stat.HEALTH_MAX),
		"mana_max": stats.get_stat(Stat.MANA_MAX),
		"ad": stats.get_stat(Stat.AD),
		"health": stats.get_stat(Stat.HEALTH),
		"mana": stats.get_stat(Stat.MANA),
	}
	player.set_meta(META_SNAPSHOT, snapshot)

	stats.set_stat(Stat.HEALTH_MAX, GOD_POOL)
	stats.set_stat(Stat.MANA_MAX, GOD_POOL)
	stats.set_stat(Stat.HEALTH, GOD_POOL)
	stats.set_stat(Stat.MANA, GOD_POOL)
	stats.set_stat(Stat.AD, float(snapshot["ad"]) + GOD_AD_BONUS)
	return "Godmode ON — 10,000,000 HP/Mana (full) and +10,000 AD. Use /godmodeoff to revert."
