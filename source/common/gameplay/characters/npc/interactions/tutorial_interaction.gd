class_name TutorialInteraction
extends NPCInteraction
## NPC capability: hand the player a GUIDED lesson instead of a wall of dialogue.
##
## A DialogueInteraction can only talk. This one hands a topic to the client's
## onboarding coach (source/client/ui/hud/onboarding_coach.gd), which walks the
## player through the real interface — "open your Inventory", wait until they do,
## then explain what they are looking at — and can be re-run any time by picking
## the option again.
##
## Purely client-side: nothing to register server-side, because a lesson changes
## no game state.

## Which lesson to run. Must match a key in OnboardingCoach.LESSONS
## (&"menus", &"mastery", &"food").
@export var topic: StringName = &""


func menu_entry(_npc: Node) -> Dictionary:
	if topic.is_empty():
		return {}
	return {
		"label": _label_or("Show me how this works"),
		"icon": _icon_or(""),
		"tutorial": String(topic),
	}
