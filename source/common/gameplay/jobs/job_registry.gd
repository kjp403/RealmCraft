class_name JobRegistry
## Single source of truth for which jobs exist. Each entry maps a job's
## internal slug to its [JobPerks] resource. Adding a new job is now a
## **content** change: drop a `<name>.tres` under jobs/ and add one line
## here.
##
## `static var` (not `const`) because preload() expressions, while
## constant-folded at parse time, can't initialise typed `const Dictionary`
## with class-shaped values in GDScript 4 — `Assigned value isn't a
## constant expression`. `static var` initialises lazily, no issue.

static var JOBS: Dictionary[StringName, JobPerks] = {
	&"mining": preload("res://source/common/gameplay/jobs/mining.tres"),
	&"harvesting": preload("res://source/common/gameplay/jobs/harvesting.tres"),
	&"woodcutting": preload("res://source/common/gameplay/jobs/woodcutting.tres"),
	&"fishing": preload("res://source/common/gameplay/jobs/fishing.tres"),
	&"smithing": preload("res://source/common/gameplay/jobs/smithing.tres"),
	&"outfitting": preload("res://source/common/gameplay/jobs/outfitting.tres"),
	&"cooking": preload("res://source/common/gameplay/jobs/cooking.tres"),
	&"herblore": preload("res://source/common/gameplay/jobs/herblore.tres"),
	&"fletching": preload("res://source/common/gameplay/jobs/fletching.tres"),
	# Combat skill, not gathering/crafting — reuses this same registry purely for
	# its xp curve + perk-point plumbing (SkillXp, PlayerResource.skills). See
	# docs/slayer_skill.md. category == &"combat" is new; the Jobs UI's
	# gathering/crafting bucketing needs a third bucket to show it.
	&"slayer": preload("res://source/common/gameplay/jobs/slayer.tres"),
	# Combat skill too, trained by burning bones at the church altar rather than
	# by killing. See docs/prayer_skill.md.
	&"prayer": preload("res://source/common/gameplay/jobs/prayer.tres"),
}


## True if [param job_slug] is a registered job. Cheap dict lookup, callable
## from anywhere.
static func has_job(job_slug: StringName) -> bool:
	return JOBS.has(job_slug)


## The [JobPerks] for [param job_slug], or null if unknown. Callers get a
## typed reference so static dispatch on perks methods is clean:
##   var perks: JobPerks = JobRegistry.perks_for(&"mining")
##   if perks != null:
##       var mult: float = perks.xp_multiplier(skill["perks"])
static func perks_for(job_slug: StringName) -> JobPerks:
	return JOBS.get(job_slug, null)


## Human-readable label for [param job_slug]. Falls back to a capitalised
## slug if the job is unknown — UI never crashes on a typo.
static func display_name(job_slug: StringName) -> String:
	var p: JobPerks = perks_for(job_slug)
	if p != null and not p.display_name.is_empty():
		return p.display_name
	return String(job_slug).capitalize()


## Category slug (`&"gathering"` / `&"crafting"`) for [param job_slug], or
## empty if unknown. Used by the Jobs UI to bucket the list.
static func category(job_slug: StringName) -> StringName:
	var p: JobPerks = perks_for(job_slug)
	if p == null:
		return &""
	return p.category


## Icon for [param job_slug], or null if the job is unknown and nothing stands
## in for it.
##
## Three-step fallback, because not every job resource carries its own icon yet:
## the authored `icon` first, then the first source item (what you gather), then
## the first recipe item (what you make). A Fletching entry with no icon still
## shows an arrow rather than an empty square.
##
## Lives here rather than in a panel so the skills grid, the HUD tracker and its
## hover card can't end up showing three different pictures for one skill.
static func icon_for(job_slug: StringName) -> Texture2D:
	var p: JobPerks = perks_for(job_slug)
	if p == null:
		return null
	if p.icon != null:
		return p.icon
	if not p.source_items.is_empty():
		var source_item: Item = p.source_items[0]
		if source_item != null:
			return source_item.item_icon
	if not p.recipe_items.is_empty():
		var recipe_item: Item = p.recipe_items[0]
		if recipe_item != null:
			return recipe_item.item_icon
	return null
