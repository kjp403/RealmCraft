class_name SlayerMasterResource
extends Resource
## Editor-authored Slayer master definition — the Slayer-skill equivalent of
## ShopResource/QuestResource. Attach one to an NPC's SlayerInteraction. The
## server resolves + assigns from `pool` when the player requests a task;
## the client renders the master's greeting/flavor from this same resource.
##
## Identity is the FILENAME slug (master_slug()), same convention as
## SlayerTaskDef.task_slug() / NPCResource.giver_key() — no registry id needed.

@export var master_name: String = "Slayer Master"
@export_multiline var greeting: String = "Need a task?"
## Floor to receive ANY task from this master at all (independent of any single
## task's own min_slayer_level — see SlayerTaskDef). Turael = 1, Durael = 20 per
## design (docs/slayer_skill.md) — deliberately a SLAYER-level gate, not a combat-
## level gate like OSRS's Mazchna, to match how every other Arkenelle skill gate
## reads (QuestResource.min_skill_level).
@export var min_slayer_level: int = 1

@export_group("Points economy")
## Slayer points banked on TASK COMPLETION (not skip). Turael = 0 — she is the
## always-free, no-reward entry master by design, exactly like OSRS Turael/Spria.
## Durael = 6, matching Mazchna's base (the level-20 wiki slot she fills).
@export var base_points_per_task: int = 0
## True = Turael-style "get a different task any time, free" — but per OSRS,
## reassigning THIS way resets the player's streak to zero (SlayerTaskService
## enforces this; skipping via points on a paid master does NOT reset streak).
@export var free_reassign: bool = false
## Points cost to reassign when [member free_reassign] is false (Durael). Matches
## OSRS's flat 30-point "Cancel task" cost. A player's skip_discount slayer perk
## can reduce this at spend time — see JobPerks on the &"slayer" job.
@export var reassign_point_cost: int = 30

@export_group("Task table")
@export var pool: Array[SlayerMasterTaskEntry] = []


func master_slug() -> StringName:
	if resource_path.is_empty() or resource_path.contains("::"):
		return &""
	return StringName(resource_path.get_file().get_basename())


## Every pool row whose task is non-null, unblocked for [param player], and whose
## OWN min_slayer_level is met — i.e. what could actually be rolled right now.
## A row can exist in `pool` (so it shows up once the player is high enough) long
## before it's reachable, exactly like a real OSRS master's table.
func eligible_entries(player_slayer_level: int, blocked_task_slugs: Dictionary) -> Array[SlayerMasterTaskEntry]:
	var out: Array[SlayerMasterTaskEntry] = []
	for entry: SlayerMasterTaskEntry in pool:
		if entry == null or entry.task == null or entry.weight <= 0:
			continue
		if player_slayer_level < entry.task.min_slayer_level:
			continue
		if blocked_task_slugs.has(entry.task.task_slug()):
			continue
		out.append(entry)
	return out
