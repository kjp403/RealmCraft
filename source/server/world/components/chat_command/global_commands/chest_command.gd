extends ChatCommand
## Spawn a world loot chest at your feet for QA / boss-drop tuning.
## For a tradeable bag chest use /give instead (same slug), e.g.
## /give self gold_pink_large
## Examples: /chest wood_silver_small   |   /chest gold_pink_large


const KNOWN: PackedStringArray = [
	"wood_silver_small",
	"wood_silver_medium",
	"wood_gold_small",
	"wood_gold_medium",
	"gold_blue_large",
	"gold_red_large",
	"gold_pink_large",
	"wood_silver_large",
	"wood_gold_large",
	"gold_steel_large",
	"gold_steel_grand",
	"gold_red_grand",
	"gold_blue_grand",
	"gold_pink_grand",
	"gold_steel_masterwork",
	"gold_blue_masterwork",
	"gold_red_masterwork",
	"gold_pink_masterwork",
]


func _init() -> void:
	command_name = "chest"
	command_priority = 2 # admin+
	command_usage = "/chest <slug>  (e.g. wood_silver_small, gold_blue_large)"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 2:
		return "Usage: " + command_usage + "\nSlugs: " + ", ".join(KNOWN)

	var slug: StringName = StringName(args[1].strip_edges().to_lower())
	if ChestResource.load_by_slug(slug) == null:
		return "Unknown chest '%s'. Slugs: %s" % [String(slug), ", ".join(KNOWN)]

	var player: Player = server_instance.players_by_peer_id.get(peer_id, null)
	if player == null:
		return "Couldn't locate you."

	var map: Map = server_instance.instance_map
	if map == null or map.replicated_props_container == null:
		return "No map props container."

	var chest: LootChest = LootChest.spawn_at(
		map.replicated_props_container,
		slug,
		player.global_position + Vector2(0, 24),
		peer_id,
		int(LootChest.EXCLUSIVE_S * 1000.0)
	)
	if chest == null:
		return "Failed to spawn chest."
	return "Spawned %s at your feet." % String(slug)
