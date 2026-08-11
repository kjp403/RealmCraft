extends SceneTree
## Headless gate: biome travel NPCs (Camel / Forge Golem / Swamp Hermit).
## The Hub keeps only their return landing pads; the NPCs themselves stand in the
## Goblin Woodland east wing.
## Pure FileAccess + ResourceLoader duck-typing so ClientState autoloads are not required.
## Run: godot --headless --path . -s tools/verify_hub_biome_npc_warps.gd


func _init() -> void:
	var fails: PackedStringArray = PackedStringArray()

	if not ResourceLoader.exists("res://source/common/gameplay/characters/npc/interactions/warp_interaction.gd"):
		fails.append("warp_interaction.gd missing")
	if not ResourceLoader.exists("res://source/server/world/components/data_request_handlers/npc.warp.gd"):
		fails.append("npc.warp.gd missing")

	var expected: Array[Dictionary] = [
		{
			"path": "res://source/common/gameplay/characters/npc/npcs/desert_camel.tres",
			"name": "Desert Camel",
			"instance": "desert",
			"target_id": 25,
			"skin": "res://source/common/gameplay/characters/sprite_frames/camel.tres",
		},
		{
			"path": "res://source/common/gameplay/characters/npc/npcs/forge_golem.tres",
			"name": "Forge Golem",
			"instance": "fire_forge",
			"target_id": 26,
			"skin": "res://source/common/gameplay/characters/sprite_frames/forge_golem.tres",
		},
		{
			"path": "res://source/common/gameplay/characters/npc/npcs/swamp_hermit.tres",
			"name": "Swamp Hermit",
			"instance": "sewers",
			"target_id": 28,
			"skin": "res://source/common/gameplay/characters/sprite_frames/swamp_hermit.tres",
		},
	]
	for spec: Dictionary in expected:
		var path: String = str(spec["path"])
		if not ResourceLoader.exists(path):
			fails.append("missing NPC %s" % path)
			continue
		var npc: Resource = load(path)
		if npc == null:
			fails.append("failed load NPC %s" % path)
			continue
		if str(npc.get("npc_name")) != str(spec["name"]):
			fails.append("%s name want %s got %s" % [path, spec["name"], npc.get("npc_name")])
		var skin: SpriteFrames = npc.get("skin") as SpriteFrames
		if skin == null or not skin.has_animation(&"idle"):
			fails.append("%s skin missing idle" % path)
		var found_warp: bool = false
		var interactions: Array = npc.get("interactions")
		for inter: Variant in interactions:
			if inter == null:
				continue
			# WarpInteraction exposes target_instance + target_id
			if inter.get("target_instance") == null:
				continue
			if not ("target_id" in inter):
				continue
			found_warp = true
			var dest: Resource = inter.get("target_instance")
			if dest == null:
				fails.append("%s warp has no target_instance" % path)
			elif str(dest.get("instance_name")) != str(spec["instance"]):
				fails.append("%s warp instance want %s got %s" % [
					path, spec["instance"], dest.get("instance_name")
				])
			if int(inter.get("target_id")) != int(spec["target_id"]):
				fails.append("%s warp target_id want %s got %s" % [
					path, spec["target_id"], inter.get("target_id")
				])
		if not found_warp:
			fails.append("%s missing WarpInteraction" % path)
		if not ResourceLoader.exists(str(spec["skin"])):
			fails.append("missing skin %s" % spec["skin"])

	var hub_txt: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/maps/maps/hub.tscn"
	)
	if hub_txt.is_empty():
		fails.append("hub.tscn unreadable")
	else:
		for gone: String in ["DesertPortal", "FireForgePortal", "SewersPortal"]:
			if hub_txt.contains('name="%s"' % gone):
				fails.append("Hub still has outbound portal node %s" % gone)
		for keep: String in ["DesertLanding", "FireForgeLanding", "SewersLanding"]:
			if not hub_txt.contains('name="%s"' % keep):
				fails.append("Hub missing landing warper %s" % keep)
		# Landing pads must keep biome return ids and must not set target_instance.
		if not _hub_landing_ok(hub_txt, "DesertLanding", 25):
			fails.append("DesertLanding warper_id/target mismatch")
		if not _hub_landing_ok(hub_txt, "FireForgeLanding", 26):
			fails.append("FireForgeLanding warper_id/target mismatch")
		if not _hub_landing_ok(hub_txt, "SewersLanding", 28):
			fails.append("SewersLanding warper_id/target mismatch")
		# The travel NPCs moved out to the Woodland east wing; the Hub keeps only
		# the landing pads they warp players back to.
		for n: String in ["DesertCamel", "ForgeGolem", "SwampHermit"]:
			if hub_txt.contains('name="%s"' % n):
				fails.append("Hub still hosts travel NPC %s (they live in Woodland East)" % n)

	var wood_txt: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn"
	)
	if wood_txt.is_empty():
		fails.append("woodland_tiles.tscn unreadable")
	else:
		# East Wilds homes: camel on the East Shore sand, hermit by Murkwood Ponds,
		# golem on the northern shelf.
		var homes: Dictionary = {
			"DesertCamel": "Vector2(4634, 1384)",
			"SwampHermit": "Vector2(4804, 680)",
			"ForgeGolem": "Vector2(4823, 245)",
		}
		for n: String in homes:
			if not wood_txt.contains('name="%s"' % n):
				fails.append("Woodland missing travel NPC %s" % n)
			elif not _node_has_position(wood_txt, n, str(homes[n])):
				fails.append("%s is not at %s" % [n, homes[n]])
		for tres: String in ["desert_camel.tres", "forge_golem.tres", "swamp_hermit.tres"]:
			if not wood_txt.contains(tres):
				fails.append("Woodland does not reference %s" % tres)

	var desert_txt: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/maps/maps/desert/desert.tscn"
	)
	if not desert_txt.contains("warper_id = 125"):
		fails.append("desert interior return portal (warper_id 125) missing — should stay")
	var forge_txt: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/maps/maps/fire_forge/fire_forge.tscn"
	)
	if not forge_txt.contains("warper_id = 126"):
		fails.append("fire_forge interior return portal (warper_id 126) missing — should stay")
	var sewers_txt: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/maps/maps/sewers/sewers.tscn"
	)
	if not sewers_txt.contains("warper_id = 128"):
		fails.append("sewers interior return portal (warper_id 128) missing — should stay")

	for sheet: String in [
		"res://assets/sprites/characters/camel/camel_idle.png",
		"res://assets/sprites/characters/forge_golem/forge_golem_idle.png",
		"res://assets/sprites/characters/swamp_hermit/swamp_hermit_idle.png",
	]:
		if not ResourceLoader.exists(sheet):
			fails.append("missing sprite %s" % sheet)

	if fails.is_empty():
		print("VERIFY_PASS hub_biome_npc_warps")
	else:
		print("VERIFY_FAIL hub_biome_npc_warps")
		for f: String in fails:
			print(" - ", f)
	quit(0 if fails.is_empty() else 1)


## True when the named landing node block has the expected warper_id and no target_instance.
func _hub_landing_ok(hub_txt: String, node_name: String, warper_id: int) -> bool:
	var marker: String = 'name="%s"' % node_name
	var start: int = hub_txt.find(marker)
	if start < 0:
		return false
	var end: int = hub_txt.find("[node name=", start + marker.length())
	var block: String = hub_txt.substr(start, end - start if end > start else hub_txt.length() - start)
	if block.contains("target_instance"):
		return false
	return block.contains("warper_id = %d" % warper_id)


## True when the named node's block sets exactly the expected position.
func _node_has_position(scene_txt: String, node_name: String, position: String) -> bool:
	var marker: String = 'name="%s"' % node_name
	var start: int = scene_txt.find(marker)
	if start < 0:
		return false
	var end: int = scene_txt.find("[node name=", start + marker.length())
	var block: String = scene_txt.substr(start, end - start if end > start else scene_txt.length() - start)
	return block.contains("position = " + position)

