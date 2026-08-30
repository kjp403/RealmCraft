class_name SkillMasterTitles
## The eleven level-99 mastery titles, one per profession skill.
##
## Unlike [SupporterTitles] (bought) and the [TitleCatalog] premium set (staff
## test stock), these are EARNED and granted automatically — see
## [SkillMasterTitleService] for the grant paths.
##
## KEYED BY JOB SLUG, NOT BY DISPLAY NAME, and that distinction is the single
## easiest thing to get wrong here. Three of the eleven skills have a slug that
## does not match what players call them:
##
##     Crafting  -> &"outfitting"
##     Farming   -> &"harvesting"
##     Herblore  -> &"herblore"   (matches, but sits next to the two that do not)
##
## [PlayerResource.skills] is keyed by the SLUG, so a table written against the
## display names would silently never fire for those skills — the level check
## would look up a key that does not exist, find nothing, and grant nothing, with
## no error anywhere. Every key below is checked against [JobRegistry] by
## tools/verify_skill_master_titles.gd for exactly that reason.

## The level that earns a mastery title. Matches [constant SkillXp.LEVEL_CAP] —
## these are cap titles, so if the cap ever moves this must move with it, which is
## why it is derived rather than typed as a literal 99.
const UNLOCK_LEVEL: int = SkillXp.LEVEL_CAP

## job slug -> title. `fx` indexes the style in skill_master_title.gdshader AND
## the emitter in [TitleParticles]; the two must stay in step, which
## tools/verify_skill_master_titles.gd asserts.
##
## `color` is the label tint the shader gradients away from, and it is also what
## the chat bracket and the vault row use, so it has to read on its own against a
## dark chat backdrop — not merely as a seed for the gradient.
const BY_JOB: Dictionary = {
	&"mining": {
		"name": "Master Miner",
		"color": "#c2a86e",
		"fx": 0,
		"blurb": "Stone and gold. Ninety-nine levels of swinging at rock.",
	},
	&"smithing": {
		"name": "Forge Master",
		"color": "#ff7a34",
		"fx": 1,
		"blurb": "White-hot iron cooling to red. Sparks off the anvil.",
	},
	&"fishing": {
		"name": "Deep Sea Legend",
		"color": "#3fc9ea",
		"fx": 2,
		"blurb": "Caustics and bubbles. Everything below the surface.",
	},
	&"cooking": {
		"name": "Culinary King",
		"color": "#e2a24a",
		"fx": 3,
		"blurb": "Golden-brown, steaming, and slightly on fire.",
	},
	&"outfitting": {
		"name": "Grand Artisan",
		"color": "#dfe4ec",
		"fx": 4,
		"blurb": "Marble and silver, set with every gem you ever cut.",
	},
	&"woodcutting": {
		"name": "Timber Lord",
		"color": "#b8813f",
		"fx": 5,
		"blurb": "Oak grain and falling leaves.",
	},
	&"harvesting": {
		"name": "Arch-Botanist",
		"color": "#46d982",
		"fx": 6,
		"blurb": "Green things growing, pollen in the light.",
	},
	&"fletching": {
		"name": "Master Fletcher",
		"color": "#f2dcdc",
		"fx": 7,
		"blurb": "Feather and crimson, cut by the wind of a loosed shot.",
	},
	&"herblore": {
		"name": "Grand Alchemist",
		"color": "#b876ec",
		"fx": 8,
		"blurb": "Something purple is boiling and it should not be.",
	},
	&"slayer": {
		"name": "Slayer Master",
		"color": "#e9e2d2",
		"fx": 9,
		"blurb": "Bone-white, dripping, trailing smoke.",
	},
	&"prayer": {
		"name": "High Priest",
		"color": "#ffe9a8",
		"fx": 10,
		"blurb": "Gold light with something behind it.",
	},
}

## Display order for the vault and the profile — the order the Jobs UI lists
## skills in, so a player reads the same sequence in both places.
const ORDER: Array[StringName] = [
	&"mining", &"woodcutting", &"fishing", &"harvesting", &"smithing",
	&"outfitting", &"cooking", &"herblore", &"fletching", &"slayer", &"prayer",
]


## Title earned by mastering [param job_slug], or "" when that job has none.
static func title_for(job_slug: StringName) -> String:
	var entry: Dictionary = BY_JOB.get(job_slug, {})
	return str(entry.get("name", ""))


## The job a mastery title belongs to, or &"" when the name is not one of ours.
## Case-insensitive, because titles arrive from chat commands and the DB as well
## as from the grant path.
static func job_for_title(title: String) -> StringName:
	var needle: String = title.strip_edges().to_lower()
	if needle.is_empty():
		return &""
	for job: StringName in BY_JOB:
		if str((BY_JOB[job] as Dictionary).get("name", "")).to_lower() == needle:
			return job
	return &""


## Spec for a mastery title, in the shape [TitleCatalog.spec] returns — so the
## whole title VFX pipeline treats these exactly like a supporter or premium
## title and needs no branch of its own.
##
## `style` is fixed at 0 and `vip` at false: the mastery looks are driven by `fx`
## through a different shader, and leaving the legacy keys present means anything
## still reading them (the chat bbcode tag, the vault row) keeps working.
static func spec(title: String) -> Dictionary:
	var job: StringName = job_for_title(title)
	if job == &"":
		return {}
	var entry: Dictionary = (BY_JOB[job] as Dictionary).duplicate()
	entry["style"] = 0
	entry["vip"] = false
	entry["job"] = job
	return entry


## True when this title is one of the eleven.
static func is_mastery_title(title: String) -> bool:
	return job_for_title(title) != &""


## Every mastery title, in [constant ORDER]. Rows carry `slug` so the vault list
## can key on it like the other two rosters.
static func roster() -> Array:
	var out: Array = []
	for job: StringName in ORDER:
		var row: Dictionary = (BY_JOB[job] as Dictionary).duplicate()
		row["slug"] = String(job)
		row["job"] = job
		out.append(row)
	return out


## True when [param level] earns the title. A single predicate rather than
## `>= 99` scattered at each call site, so the retroactive sweep and the live
## hook can never disagree about what qualifies.
static func qualifies(level: int) -> bool:
	return level >= UNLOCK_LEVEL
