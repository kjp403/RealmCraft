@tool
extends Node
## Probe for "arrows are not equipping": walks the same gates item.equip.gd walks,
## on a real Player + PlayerResource, and prints which one says no.
##
## Run: godot --headless --path . tools/verify_ammo_equip.tscn

const ARROWS: Array[String] = [
	"bronze_arrow", "iron_arrow", "steel_arrow",
	"mithril_arrow", "adamant_arrow", "runite_arrow",
]


func _ready() -> void:
	var player: Player = Player.new()
	var resource: PlayerResource = PlayerResource.new()
	resource.level = 99
	resource.masteries[&"bow"] = {"level": 40, "spent": {}}
	player.player_resource = resource

	for slug: String in ARROWS:
		var id: int = ContentRegistryHub.id_from_slug(&"items", StringName(slug))
		var item: Item = ContentRegistryHub.load_by_id(&"items", id)
		if item == null:
			print("  %-16s id=%d  LOAD FAILED" % [slug, id])
			continue
		var ammo: AmmoItem = item as AmmoItem
		if ammo == null:
			print("  %-16s id=%d  NOT an AmmoItem (script_class did not resolve)" % [slug, id])
			continue
		var unlocked: bool = ammo.slot != null and ammo.slot.is_unlocked_for(resource)
		print("  %-16s id=%-4d slot=%-6s unlocked=%s mastery_ok=%s can_equip=%s holdable=%s stack=%d" % [
			slug, id,
			ammo.slot.key if ammo.slot else "NONE",
			unlocked,
			ammo.meets_mastery_requirement(resource),
			ammo.can_equip(player),
			ammo.holdable,
			ammo.stack_limit,
		])
	player.free()
	get_tree().quit(0)
