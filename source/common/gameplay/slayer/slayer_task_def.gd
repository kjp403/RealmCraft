class_name SlayerTaskDef
extends Resource
## A single Slayer task "category" — the OSRS-style monster group a task targets
## (e.g. "Goblins" covers goblin_runt, goblin_cutter, goblin_slinger, goblin_shaman
## all at once). Mirrors how QuestObjective.KILL matches ONE enemy_type, except a
## Slayer task fans out over several — killing ANY listed enemy_type advances it.
##
## Identity is the FILENAME slug (task_slug()), exactly like NPCResource.giver_key()
## and ShopResource's map-registered key: no hand-assigned int id, no content-registry
## Generate step needed. Drop a new .tres under slayer/tasks/, reference it from a
## SlayerMasterResource pool entry, done — pure content, same workflow JobRegistry
## documents for jobs.

@export var display_name: String = "Monsters"
## Monster slugs (EnemyTypeResource.enemy_type) this task counts. A kill of ANY of
## these while this task is active advances the counter.
@export var enemy_types: Array[StringName] = []
## Floor for this task to ever be ROLLED, independent of which master offers it — a
## master's own min_slayer_level (SlayerMasterResource) is a separate, usually lower,
## gate. Mirrors QuestResource.min_skill_level's role for skill-gated quests.
@export var min_slayer_level: int = 1
## Slayer XP granted per kill while this task is active. Flat per task (not
## per-monster) — see docs/slayer_skill.md for the balancing formula
## (≈1.3× the group's average EnemyTypeResource.xp_reward, rounded).
@export var xp_per_kill: int = 10
## Flavor + a one-line strategy tip, shown in the in-game Slayer Guide panel.
@export_multiline var guide_notes: String = ""


## Stable slug used as the persisted task key (PlayerResource.current_slayer_task
## and slayer_blocked_tasks) and for pool lookups. Empty for an INLINE resource
## (no file of its own) — see NPCResource.giver_key() for why that's the right
## fallback behavior (never silently collide two inline tasks on one key).
func task_slug() -> StringName:
	if resource_path.is_empty() or resource_path.contains("::"):
		return &""
	return StringName(resource_path.get_file().get_basename())


## True if a kill of [param enemy_type] advances this task.
func matches(enemy_type: StringName) -> bool:
	return enemy_types.has(enemy_type)
