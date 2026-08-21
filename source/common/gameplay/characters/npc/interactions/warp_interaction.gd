class_name WarpInteraction
extends NPCInteraction
## NPC capability: travel to a target instance (replaces Hub biome portals).
## Selecting the option fires [code]npc.warp[/code]; the server resolves this
## interaction off the NPC node, range-checks, then reuses warper travel
## ([method InstanceManager.player_switch_instance]).

@export var target_instance: InstanceResource
@export var target_id: int = 0
## Button / toast label, e.g. "Desert".
@export var destination_label: String = ""
## Optional skill gate: the player needs this profession at
## [member required_skill_level] before the NPC will take them. Empty = no gate.
## Enforced SERVER-side in npc.warp.gd — this only hides the option early.
@export var required_skill: StringName = &""
@export var required_skill_level: int = 0


func menu_entry(npc: Node) -> Dictionary:
	if target_instance == null:
		return {}
	if not required_skill.is_empty():
		# Client-side courtesy only. The label still shows so the destination is
		# discoverable — a gate you cannot see is a gate players never train for.
		var have: int = int(ClientState.skill_levels.get(String(required_skill), 1))
		if have < required_skill_level:
			# A spoken line, NOT a disabled button: npc_menu has no "disabled"
			# key, so the entry would render as a live option, close the
			# dialogue and fire an empty request at the server. This keeps the
			# destination discoverable and says what it costs to get there.
			return {
				"label": _label_or("%s — needs %s %d" % [
					_destination_label(), JobRegistry.display_name(required_skill),
					required_skill_level,
				]),
				"icon": _icon_or(""),
				"lines": ["Come back when you have %s %d and I'll take you out there." % [
					JobRegistry.display_name(required_skill), required_skill_level,
				]],
			}
	return {
		"label": _label_or("Travel to %s" % _destination_label()),
		"icon": _icon_or(""),
		"request": &"npc.warp",
		"args": {"npc": String(npc.name)},
	}


func _destination_label() -> String:
	if not destination_label.is_empty():
		return destination_label
	return target_instance.display_title() if target_instance != null else "there"
