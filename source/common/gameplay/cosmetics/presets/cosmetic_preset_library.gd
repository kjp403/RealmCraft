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
const _AURA_SOLAR_ECLIPSE: GDScript = preload("res://source/common/gameplay/cosmetics/presets/aura_solar_eclipse_preset.gd")
const _AURA_RUNEBOUND_TITAN: GDScript = preload("res://source/common/gameplay/cosmetics/presets/aura_runebound_titan_preset.gd")
const _TRAIL_CHRONO_ECHO: GDScript = preload("res://source/common/gameplay/cosmetics/presets/trail_chrono_echo_preset.gd")
const _TRAIL_INFERNAL_CHASM: GDScript = preload("res://source/common/gameplay/cosmetics/presets/trail_infernal_chasm_preset.gd")
const _AURA_CRIMSON_EMBERS: GDScript = preload("res://source/common/gameplay/cosmetics/presets/aura_crimson_embers_preset.gd")
const _AURA_ARCANE_SIGILS: GDScript = preload("res://source/common/gameplay/cosmetics/presets/aura_arcane_sigils_preset.gd")
const _AURA_GLACIAL_VEIL: GDScript = preload("res://source/common/gameplay/cosmetics/presets/aura_glacial_veil_preset.gd")
const _AURA_VERDANT_BLOOM: GDScript = preload("res://source/common/gameplay/cosmetics/presets/aura_verdant_bloom_preset.gd")
const _AURA_AETHER_ARCS: GDScript = preload("res://source/common/gameplay/cosmetics/presets/aura_aether_arcs_preset.gd")
const _AURA_LOTUS_PETALS: GDScript = preload("res://source/common/gameplay/cosmetics/presets/aura_lotus_petals_preset.gd")
const _AURA_ALCHEMICAL_SUN: GDScript = preload("res://source/common/gameplay/cosmetics/presets/aura_alchemical_sun_preset.gd")
const _AURA_PRISMATIC_SHIMMER: GDScript = preload("res://source/common/gameplay/cosmetics/presets/aura_prismatic_shimmer_preset.gd")
const _TRAIL_STATIC_WAKE: GDScript = preload("res://source/common/gameplay/cosmetics/presets/trail_static_wake_preset.gd")
const _HALO_THUNDERHEAD_CROWN: GDScript = preload("res://source/common/gameplay/cosmetics/presets/halo_thunderhead_crown_preset.gd")
const _PET_AXOLOTL: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_axolotl_preset.gd")
const _PET_BABY_DRAGON: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_baby_dragon_preset.gd")
const _PET_BUMBLEBEE: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_bumblebee_preset.gd")
const _PET_CLOCKWORK_OWL: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_clockwork_owl_preset.gd")
const _PET_CLOUD_PUP: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_cloud_pup_preset.gd")
const _PET_CORGI: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_corgi_preset.gd")
const _PET_CRAB: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_crab_preset.gd")
const _PET_CRYSTAL_GOLEM: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_crystal_golem_preset.gd")
const _PET_DUCKLING: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_duckling_preset.gd")
const _PET_EMBER_IMP: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_ember_imp_preset.gd")
const _PET_FIREFLIES: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_fireflies_preset.gd")
const _PET_FROG: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_frog_preset.gd")
const _PET_GHOST: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_ghost_preset.gd")
const _PET_HAMSTER_BALL: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_hamster_ball_preset.gd")
const _PET_JELLYFISH: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_jellyfish_preset.gd")
const _PET_KITSUNE: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_kitsune_preset.gd")
const _PET_MIMIC: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_mimic_preset.gd")
const _PET_MOTH: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_moth_preset.gd")
const _PET_MUSHROOM_SPROUT: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_mushroom_sprout_preset.gd")
const _PET_OWL: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_owl_preset.gd")
const _PET_PENGUIN: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_penguin_preset.gd")
const _PET_PET_ROCK: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_pet_rock_preset.gd")
const _PET_PHOENIX_CHICK: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_phoenix_chick_preset.gd")
const _PET_POCKET_MOON: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_pocket_moon_preset.gd")
const _PET_PUMPKIN_LANTERN: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_pumpkin_lantern_preset.gd")
const _PET_RED_PANDA: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_red_panda_preset.gd")
const _PET_SLIME: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_slime_preset.gd")
const _PET_SNAIL: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_snail_preset.gd")
const _PET_SPELLBOOK: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_spellbook_preset.gd")
const _PET_STAR_SPRITE: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_star_sprite_preset.gd")
const _PET_BABY_GRIFFIN: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_baby_griffin_preset.gd")
const _PET_BUNNY: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_bunny_preset.gd")
const _PET_PIXIE: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_pixie_preset.gd")
const _PET_STARRY_CAT: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_starry_cat_preset.gd")
const _PET_TREASURE_GOBLIN: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_treasure_goblin_preset.gd")
const _PET_WISP: GDScript = preload("res://source/common/gameplay/cosmetics/presets/pet_wisp_preset.gd")

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
	# Mythic tier. These have no strip heritage at all - they were authored as
	# presets from the start, and their generated strips exist only to hold a
	# registry entry (see tools/gen_cosmetic_vfx.py).
	&"aura_solar_eclipse": _AURA_SOLAR_ECLIPSE,
	&"aura_runebound_titan": _AURA_RUNEBOUND_TITAN,
	&"trail_chrono_echo": _TRAIL_CHRONO_ECHO,
	&"trail_infernal_chasm": _TRAIL_INFERNAL_CHASM,
	# THE COLOUR-MATCHED SET. Authored as presets from the start, like the mythic
	# tier above - their generated strips exist only to hold a registry entry. Each
	# takes its colours from [CosmeticThemes], so the aura, the matching title and
	# the matching body dye are the same hex and cannot drift apart.
	&"aura_crimson_embers": _AURA_CRIMSON_EMBERS,
	&"aura_arcane_sigils": _AURA_ARCANE_SIGILS,
	&"aura_glacial_veil": _AURA_GLACIAL_VEIL,
	&"aura_verdant_bloom": _AURA_VERDANT_BLOOM,
	&"aura_aether_arcs": _AURA_AETHER_ARCS,
	&"aura_lotus_petals": _AURA_LOTUS_PETALS,
	&"aura_alchemical_sun": _AURA_ALCHEMICAL_SUN,
	&"aura_prismatic_shimmer": _AURA_PRISMATIC_SHIMMER,
	# The rest of each theme set: a trail and a halo in the same colours.
	&"trail_static_wake": _TRAIL_STATIC_WAKE,
	&"halo_thunderhead_crown": _HALO_THUNDERHEAD_CROWN,
	# PETS. Every pet is a scripted companion (CompanionPreset) - there is no
	# strip version of one, and its registry strip is only a placeholder.
	&"pet_axolotl": _PET_AXOLOTL,
	&"pet_baby_dragon": _PET_BABY_DRAGON,
	&"pet_bumblebee": _PET_BUMBLEBEE,
	&"pet_clockwork_owl": _PET_CLOCKWORK_OWL,
	&"pet_cloud_pup": _PET_CLOUD_PUP,
	&"pet_corgi": _PET_CORGI,
	&"pet_crab": _PET_CRAB,
	&"pet_crystal_golem": _PET_CRYSTAL_GOLEM,
	&"pet_duckling": _PET_DUCKLING,
	&"pet_ember_imp": _PET_EMBER_IMP,
	&"pet_fireflies": _PET_FIREFLIES,
	&"pet_frog": _PET_FROG,
	&"pet_ghost": _PET_GHOST,
	&"pet_hamster_ball": _PET_HAMSTER_BALL,
	&"pet_jellyfish": _PET_JELLYFISH,
	&"pet_kitsune": _PET_KITSUNE,
	&"pet_mimic": _PET_MIMIC,
	&"pet_moth": _PET_MOTH,
	&"pet_mushroom_sprout": _PET_MUSHROOM_SPROUT,
	&"pet_owl": _PET_OWL,
	&"pet_penguin": _PET_PENGUIN,
	&"pet_pet_rock": _PET_PET_ROCK,
	&"pet_phoenix_chick": _PET_PHOENIX_CHICK,
	&"pet_pocket_moon": _PET_POCKET_MOON,
	&"pet_pumpkin_lantern": _PET_PUMPKIN_LANTERN,
	&"pet_red_panda": _PET_RED_PANDA,
	&"pet_slime": _PET_SLIME,
	&"pet_snail": _PET_SNAIL,
	&"pet_spellbook": _PET_SPELLBOOK,
	&"pet_star_sprite": _PET_STAR_SPRITE,
	&"pet_wisp": _PET_WISP,
	&"pet_baby_griffin": _PET_BABY_GRIFFIN,
	&"pet_bunny": _PET_BUNNY,
	&"pet_pixie": _PET_PIXIE,
	&"pet_starry_cat": _PET_STARRY_CAT,
	&"pet_treasure_goblin": _PET_TREASURE_GOBLIN,
}


## The preset script for a cosmetic id, or null when it should use its strip.
static func script_for(cosmetic_id: int) -> GDScript:
	if cosmetic_id == 0:
		return null
	return PRESETS.get(Cosmetics.slug(cosmetic_id), null)


## A ready-to-mount preset node, or null when this cosmetic has no preset.
##
## [param preview] marks a wardrobe mount rather than a live one, which changes
## two things: screen-space layers are suppressed, and the viewer-distance cull is
## bypassed (a preview lives in UI space, where a world-space distance test is
## meaningless and would cull everything).
static func build(cosmetic_id: int, wearer: Character, preview: bool = false) -> CosmeticPreset:
	var script: GDScript = script_for(cosmetic_id)
	if script == null:
		return null
	var preset: CosmeticPreset = script.new()
	# Assigned BEFORE the node enters the tree: _build() runs from _ready, and the
	# Blood aura's owner-only vignette check reads both of these.
	preset.wearer = wearer
	preset.is_preview = preview
	preset.name = "Preset"
	return preset
