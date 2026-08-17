class_name QuestBossInteraction
extends NPCInteraction
## NPC capability: send the player into a private story-boss arena. The button
## always shows; the server refuses unless they have an active unfinished KILL
## for [member enemy_type].

## HostileNpc.enemy_type / quest KILL target (e.g. &"goblin_chief").
@export var enemy_type: StringName = &""


func menu_entry(npc: Node) -> Dictionary:
	if enemy_type == &"":
		return {}
	return {
		"label": _label_or("Send me to the fight"),
		"icon": _icon_or(""),
		"request": &"npc.quest_boss",
		"args": {"npc": String(npc.name)},
	}
