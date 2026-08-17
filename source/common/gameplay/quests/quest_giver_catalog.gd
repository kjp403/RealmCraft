class_name QuestGiverCatalog
## Indexes friendly NPCs so quests can name who to talk to and where they stand.
## Built once from the NPC .tres tree: each file's filename slug is the giver
## key, its npc_name / location_hint are the display fields, and any
## QuestInteraction it carries maps offered quests back to that NPC.

const NPC_DIR: String = "res://source/common/gameplay/characters/npc/npcs/"

static var _ready: bool = false
static var _by_key: Dictionary = {}
static var _offerer_key_by_quest: Dictionary = {}


static func location_for(giver_key: Variant) -> String:
	_ensure()
	var info: Dictionary = _by_key.get(StringName(str(giver_key)), {})
	return str(info.get("location", "")).strip_edges()


## Who this quest turns in to: an explicit turn-in NPC if the quest names one,
## otherwise the NPC that offers it.
static func turn_in_info(quest: QuestResource) -> Dictionary:
	_ensure()
	if quest == null:
		return {}
	var key: StringName = quest.turn_in_giver_key()
	if key.is_empty():
		var quest_id: int = int(quest.get_meta(&"id", 0))
		key = _offerer_key_by_quest.get(quest_id, &"")
	if key.is_empty() and quest.turn_in_giver:
		return {
			"name": quest.turn_in_giver.npc_name,
			"location": quest.turn_in_giver.location_hint,
		}
	return _by_key.get(key, {})


static func _ensure() -> void:
	if _ready:
		return
	_ready = true
	_scan(NPC_DIR)


static func _scan(dir: String) -> void:
	for file_name: String in DirAccess.get_files_at(dir):
		if not file_name.ends_with(".tres"):
			continue
		var npc: NPCResource = load(dir + file_name) as NPCResource
		if npc == null:
			continue
		var key: StringName = npc.giver_key()
		if key.is_empty():
			continue
		_by_key[key] = {
			"name": npc.npc_name,
			"location": npc.location_hint,
		}
		for interaction: NPCInteraction in npc.interactions:
			if interaction == null:
				continue
			var quests: QuestInteraction = interaction as QuestInteraction
			if quests == null:
				continue
			for quest: QuestResource in quests.quests:
				if quest == null:
					continue
				var quest_id: int = int(quest.get_meta(&"id", 0))
				if quest_id > 0 and not _offerer_key_by_quest.has(quest_id):
					_offerer_key_by_quest[quest_id] = key
	for sub: String in DirAccess.get_directories_at(dir):
		_scan(dir + sub + "/")
