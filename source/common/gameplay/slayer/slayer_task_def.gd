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
## FALLBACK Slayer XP per kill, used only when the killed enemy reports no combat
## skill XP at all. The live number is derived per-monster from that monster's own
## stat block — EnemyTypeResource.combat_skill_xp_for(hp, armor) ×
## SlayerTaskService.SLAYER_XP_RATIO — so a wide group never pays the same XP for
## its weakest and strongest member. Kept in sync with the group average so it
## still reads as documentation of the task's typical value.
##
## NOTE this is NOT derived from EnemyTypeResource.xp_reward: that number serves
## the character 1–20 curve and is ~980× too small for the 1–99 skill curve.
@export var xp_per_kill: int = 10
## Hand-tuned per-monster Slayer XP, overriding the derived value for the listed
## enemy_types. Currently unused — the stat-derived rule handles the whole roster,
## including trpg_necromancer, the one boss deliberately left on a task table.
## Kept as the escape hatch for any monster that should not follow the HP rule.
@export var xp_overrides: Dictionary[StringName, int] = {}
## Flavor + a one-line strategy tip, shown in the in-game Slayer Guide panel.
@export_multiline var guide_notes: String = ""
## Where to hunt this task, in words ("Goblin Woodland", "Mining Cave · Dark Cave").
## Shown on the HUD tracker tooltip so you don't have to open the guide.
@export var location_hint: String = ""


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


## Base Slayer XP/kill across this task's roster, boss bonus included (perk
## multipliers applied by [method SlayerTaskService.status_payload]). A roster with
## a boss in it therefore advertises a wide range — which is the honest read: the
## Goblin Chief really is worth many runts. Falls back to [member xp_per_kill]
## when no enemy type loads.
func xp_per_kill_range() -> Vector2i:
	var lo: int = 0
	var hi: int = 0
	for slug: StringName in enemy_types:
		var xp: int = 0
		if xp_overrides.has(slug):
			xp = int(xp_overrides[slug])
		else:
			var enemy: EnemyTypeResource = ContentRegistryHub.load_by_slug(
				&"enemy_types", slug
			) as EnemyTypeResource
			if enemy != null:
				xp = maxi(1, roundi(
					float(enemy.combat_skill_xp())
					* SlayerTaskService.SLAYER_XP_RATIO
					* SlayerTaskService.boss_xp_bonus(enemy.is_boss)
				))
		if xp <= 0:
			continue
		if lo <= 0:
			lo = xp
			hi = xp
		else:
			lo = mini(lo, xp)
			hi = maxi(hi, xp)
	if lo <= 0:
		var fallback: int = maxi(1, xp_per_kill)
		return Vector2i(fallback, fallback)
	return Vector2i(lo, hi)
