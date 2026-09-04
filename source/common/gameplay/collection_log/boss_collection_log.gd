class_name BossCollectionLog
extends Resource
## One boss's collection log: the definitive set of unique drops that boss owns,
## plus the title and nameplate VFX earned for filling it ("green-logging" it).
##
## DATA, NOT CODE. Adding a boss to the Collection Log is a .tres drop into
## collection_log/logs/ — the same shape as [BossHuntCatalog] scanning
## boss_hunt/targets/, and for the same reason: the roster is content, and
## content should not need a code change.
##
## [b]log_items holds registry SLUGS, not display names and not content ids.[/b]
## The slug is [Item] metadata/slug — what [ContentRegistry.id_from_slug] keys on.
## Two traps live in that one sentence:
##
##   * Weapon slugs carry a literal ".item" suffix, because they are authored as
##     `sword_fire.item.tres` and the index is generated from the file name:
##     the slug is &"sword_fire.item", NOT &"sword_fire". A log written from the
##     display name ("Fire Sword") or from a tidied-up slug matches nothing, and
##     fails silently — the item drops, the log never fills, and the only symptom
##     is a title nobody can earn.
##   * A hand-set metadata/id is not enough on its own; the item must also be in
##     the generated items_index.tres. Every slug below was checked against that
##     index, and tools/verify_collection_logs.gd re-checks them.
##
## Membership rule for log_items, applied when the three shipped logs were built:
## an item belongs to a boss's log only if that boss is its ONLY source. Gold,
## bones, ores, bars, chests, keys and food are excluded as generic; so are
## materials like Sewer Hide and Basilisk Ore, which read as boss-flavoured but
## also come off Sewers trash, gathering nodes and the Fire shop. See
## [CollectionLogManager.add_item_to_log] for why the weapon sets are still in —
## they are boss-gated by SOURCE rather than by item.

## Registry slug of the boss this log belongs to — [EnemyTypeResource.enemy_type],
## which is also the metadata/slug the enemy index keys on.
##
## Use the enemy slug, not the [BossHuntTarget] contract slug. They agree today
## for all three shipped bosses, but a boss reachable BOTH from a Boss Hunt
## contract and from its overworld spawn must credit one log, not two.
@export var boss_id: StringName = &""

## Display name for the log's header. Kept as its own field rather than read off
## the [EnemyTypeResource] because the log is shown in menus the enemy resource
## is not loaded for.
@export var boss_name: String = ""

## Every unique item this boss owns, by registry slug. Order is the display order
## in the log UI. Duplicates and empties are rejected by the verifier — a repeat
## would make the log unfillable, since progress is stored as a set.
@export var log_items: Array[StringName] = []

## The title awarded the first time this log reaches 100%.
@export var green_log_title_text: String = ""

## Nameplate particle layer instanced when the title is worn.
##
## The scene root is a [GreenLogTitleFx] (a [Node2D]), matching the mastery-title
## standard in [TitleParticles]: CPUParticles2D only (GPU particles are not safe
## on the web export), nearest-neighbour filtering, and amount/lifetime inside
## the nameplate budget so thirty of these over a boss lobby stay affordable.
@export var green_log_vfx: PackedScene = null

## The [VipTierProfile] key for this title's look — the .tres of the same name
## under titles/profiles/. This is what gives a green-log title the full metal
## ramp, specular sweep and bespoke emitter stack rather than the flat `style`
## branch below.
##
## Resolved through [CollectionLogTitles], which [TitleCatalog.spec] consults
## BEFORE its PREMIUM table — so these titles carry a profile without ever
## matching is_premium_name, and strip_unreleased_vfx leaves them alone.
@export var green_log_profile: StringName = &""

## Which branch of title_vfx.gdshader tints the TEXT: 0 gem, 1 gold, 2 ember,
## 3 void, 4 star, 5 moon, 6 ink — the same `style` int [TitleCatalog] uses.
##
## Not in the original spec, and deliberately added: green_log_vfx alone covers
## the particles around the label but nothing tints the glyphs, and the chat
## bracket and vault row have no particle layer at all. Without this the title
## renders as flat white text everywhere except directly over the player's head.
@export_range(0, 6) var green_log_title_style: int = 0

## Label tint the shader gradients away from, and what the chat bracket uses. It
## has to read on its own against a dark chat backdrop, not merely seed a gradient.
@export var green_log_title_color: Color = Color.WHITE


## How many items fill this log. The single source of truth for "100%".
func total_items() -> int:
	return log_items.size()


## True if [param item_id] is one of this boss's logged uniques.
func owns_item(item_id: StringName) -> bool:
	return log_items.has(item_id)
