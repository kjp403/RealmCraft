class_name CosmeticPresetLibrary
## Slug -> scripted preset. The one place that decides whether a cosmetic renders
## as a layered node tree or as the original pre-rendered strip.
##
## Anything NOT listed here keeps working exactly as it did: [CosmeticVfx] falls
## back to the SpriteFrames from the cosmetics registry. That fallback is the
## reason this overhaul needed no registry change, no index rebuild and no art
## pass - Rainbow, Chromatic, the halos, the flourishes, the departures and the
## Ascended weapon glow are all untouched, and a preset can be added or removed
## for a single slug without disturbing any of them.
##
## NOTE: the four set auras granted by [SkillingOutfitManager] reuse these slugs
## (aura_verdant, aura_gold, aura_emberfrost, aura_toxic), so completing a
## Skilling Outfit now grants the upgraded effect too. That is intended - it is
## the same cosmetic - but it does mean these presets show up on players who never
## bought anything, which is worth remembering when judging how loud they are.

const _AURA_TOXIC: GDScript = preload("res://source/common/gameplay/cosmetics/presets/aura_toxic_preset.gd")
const _AURA_VERDANT: GDScript = preload("res://source/common/gameplay/cosmetics/presets/aura_verdant_preset.gd")
const _AURA_BLOOD: GDScript = preload("res://source/common/gameplay/cosmetics/presets/aura_blood_preset.gd")
const _AURA_EMBERFROST: GDScript = preload("res://source/common/gameplay/cosmetics/presets/aura_emberfrost_preset.gd")
const _AURA_GALAXY: GDScript = preload("res://source/common/gameplay/cosmetics/presets/aura_galaxy_preset.gd")
const _AURA_GOLD: GDScript = preload("res://source/common/gameplay/cosmetics/presets/aura_gold_preset.gd")
const _TRAIL_TOXIC: GDScript = preload("res://source/common/gameplay/cosmetics/presets/trail_toxic_preset.gd")
const _TRAIL_BLOOD: GDScript = preload("res://source/common/gameplay/cosmetics/presets/trail_blood_preset.gd")
const _TRAIL_GALAXY: GDScript = preload("res://source/common/gameplay/cosmetics/presets/trail_galaxy_preset.gd")
const _TRAIL_GOLD: GDScript = preload("res://source/common/gameplay/cosmetics/presets/trail_gold_preset.gd")
const _TRAIL_STORM: GDScript = preload("res://source/common/gameplay/cosmetics/presets/trail_storm_preset.gd")

## Adding a line here upgrades one cosmetic from its strip to a node tree.
const PRESETS: Dictionary = {
	&"aura_toxic": _AURA_TOXIC,
	&"aura_verdant": _AURA_VERDANT,
	&"aura_blood": _AURA_BLOOD,
	&"aura_emberfrost": _AURA_EMBERFROST,
	&"aura_galaxy": _AURA_GALAXY,
	&"aura_gold": _AURA_GOLD,
	&"trail_toxic": _TRAIL_TOXIC,
	&"trail_blood": _TRAIL_BLOOD,
	&"trail_galaxy": _TRAIL_GALAXY,
	&"trail_gold": _TRAIL_GOLD,
	&"trail_storm": _TRAIL_STORM,
}


## The preset script for a cosmetic id, or null when it should use its strip.
static func script_for(cosmetic_id: int) -> GDScript:
	if cosmetic_id == 0:
		return null
	return PRESETS.get(Cosmetics.slug(cosmetic_id), null)


## A ready-to-mount preset node, or null when this cosmetic has no preset.
static func build(cosmetic_id: int, wearer: Character) -> CosmeticPreset:
	var script: GDScript = script_for(cosmetic_id)
	if script == null:
		return null
	var preset: CosmeticPreset = script.new()
	# Assigned BEFORE the node enters the tree: _build() runs from _ready and the
	# Blood aura's owner-only vignette check needs the wearer already set.
	preset.wearer = wearer
	preset.name = "Preset"
	return preset
