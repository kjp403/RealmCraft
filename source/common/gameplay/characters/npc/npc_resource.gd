class_name NPCResource
extends Resource
## A complete friendly, interactive NPC definition — the friendly-side mirror of
## EnemyTypeResource. One .tres holds who the NPC is (name, id, look), what it
## greets you with, and everything it can do (its interactions). The NPC node
## just points at this resource.

## Display name — shown as the greeting-dialogue title.
@export var npc_name: String = "Villager"
## Where this NPC stands, in words ("Desert, at the entrance", "DimWood").
## Quests use this so "Speak with X" and "Return to X" name the place, not just
## the person. Empty = no location line (hub fillers, warp animals, etc.).
@export var location_hint: String = ""
## Appearance — same kind of resource EnemyTypeResource.skin uses.
@export var skin: SpriteFrames
## Optional material applied to the sprite on top of [member skin] — the cheap way
## to give one NPC its own colours without duplicating a four-sheet sprite set.
## The Wayfarer is a Scholar recoloured pink this way (wayfarer_pink.tres); a
## second copy of the PNGs would just be two things to keep in sync, and players
## would have no way to tell which blue scholar they were looking at.
## Null = the art as authored.
@export var skin_material: Material
## Line shown above the options when greeted (Beedle/WoW-gossip style).
@export_multiline var greeting: String = "What can I do for you?"
## What this NPC can do. Add ShopInteraction / QuestInteraction entries inline.
@export var interactions: Array[NPCInteraction]


## Stable giver identity for quests, derived from this resource's FILENAME (e.g.
## duel_master.tres -> &"duel_master"). No hand-assigned id to collide: the file you
## already named IS the key. A quest references a giver by dragging in its NPCResource;
## the runtime matches on this slug (both sides resolve to the same .tres, same slug).
##
## INLINE resources (saved inside a scene) have NO file of their own — their
## resource_path is "scene.tscn::ResourceId", so the old basename slug collapsed
## to the SCENE's name, silently colliding every inline NPC in that map (two
## guild-house merchants both keyed 'inside_map' — the shop bug of 2026-07-06).
## Return empty instead so callers fall back to something unique (ShopInteraction
## uses the NPC's node name).
func giver_key() -> StringName:
	if resource_path.is_empty() or resource_path.contains("::"):
		return &""
	return StringName(resource_path.get_file().get_basename())
