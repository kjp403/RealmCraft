class_name QuestObjective
extends Resource
## One step of a quest. KILL tracks an enemy type; COLLECT/CRAFT track an item;
## VISIT tracks talking to a specific QuestGiver (resolved by giver_id).

enum Type { KILL, COLLECT, CRAFT, VISIT }

@export var type: Type = Type.KILL
## KILL only: matched against HostileNpc.enemy_type (e.g. &"slime").
@export var enemy_type: StringName
## COLLECT (have N in the bag) / CRAFT (craft N) target item.
@export var item: Item
@export var required_amount: int = 1
## Optional display name for COLLECT/CRAFT items and KILL targets
## (e.g. "Sewer Skeletons" instead of the raw `trpg_sewer_skeleton` slug).
@export var label_override: String = ""
## VISIT only: the NPC to talk to (drag in its NPCResource). The objective advances
## when the player opens the quest menu at this NPC.
@export var target_giver: NPCResource
## VISIT only: NPCResource filename slug (e.g. &"hall_keeper") used when
## [member target_giver] is empty. Prefer this over dragging an NPCResource when
## that NPC also lists this quest — ExtResource cycles fail to load in Godot.
@export var target_giver_key: StringName = &""
## VISIT only: human-readable target name used in the objective description
## (e.g. "Mira the Herbalist"). Lets the quest read cleanly without a runtime
## lookup of the giver's name.
@export var target_giver_name: String
## Portal / travel-NPC labels to pin on the minimap when the real target is on
## another map (e.g. "The Sewers", "The Gutterworks"). Matched against
## Portal.destination_label and WarpInteraction.destination_label.
@export var waypoint_labels: PackedStringArray = PackedStringArray()
## Optional item granted once, the moment this objective's required count is
## met (KILL / VISIT / CRAFT). Used for quest-gated boss drops and hand-offs
## ("the Heart yields the true root", "the Courier found Calder's blade").
@export var grant_item: Item


## The key this objective tracks. Used to match incoming kill/craft/visit
## events against active quests.
func target_key() -> Variant:
	match type:
		Type.KILL:
			return enemy_type
		Type.VISIT:
			if target_giver:
				return target_giver.giver_key()
			return target_giver_key
		_:
			return int(item.get_meta(&"id", 0)) if item else 0


func describe() -> String:
	match type:
		Type.KILL:
			return "Defeat %s" % kill_label()
		Type.COLLECT:
			# "Bring", not "Collect": COLLECT items are consumed and handed to the
			# giver on turn-in (see QuestService.apply_turn_in), so it's a delivery,
			# not a gather. (Daily COLLECT is NOT consumed — it keeps "Collect".)
			return "Bring %s" % _item_label()
		Type.CRAFT:
			return "Craft %s" % _item_label()
		Type.VISIT:
			var who: String = target_giver_name if not target_giver_name.is_empty() else "the indicated person"
			return "Speak with %s" % who
	return ""


## Player-facing kill target ("Sewer Skeleton"), never the raw slug
## (`trpg_sewer_skeleton` → "Trpg Sewer Skeleton").
func kill_label() -> String:
	if not label_override.is_empty():
		return label_override
	if ContentRegistryHub.registry_of(&"enemy_types") != null:
		var data: EnemyTypeResource = (
			ContentRegistryHub.load_by_slug(&"enemy_types", enemy_type)
			as EnemyTypeResource
		)
		if data != null and not data.display_name.is_empty():
			return data.display_name
	var raw: String = String(enemy_type)
	if raw.begins_with("trpg_"):
		raw = raw.substr(5)
	return raw.replace("_", " ").capitalize()


func _item_label() -> String:
	if not label_override.is_empty():
		return label_override
	return str(item.item_name) if item else "?"
