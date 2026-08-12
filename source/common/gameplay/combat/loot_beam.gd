class_name LootBeam
extends AnimatedSprite2D
## A pillar of light standing on a valuable ground drop, so a rare item reads
## across the map instead of being a 32px icon in the grass. Modelled on
## RuneScape's loot beams: a beam rises from the drop and stands until the item
## is picked up or despawns.
##
## Pure client visual and entirely self-resolving: it is parented to the
## GroundItem, which already knows its item_id, so nothing extra is replicated
## and the server does no work. It dies with its parent, which means it can never
## outlive the drop or stick around on an item someone else looted.
##
## The tier is DROP RATE, not price. Vendor value is a poor proxy for rarity —
## the rarest drops in the game, the 1/1000 boss relics, are worth 0 at a vendor,
## so a price rule put a beam on a spare chestplate and nothing on the rarest item
## in the game. Rating on how hard something is to GET means any future weapon,
## relic or chest tiers itself the moment its drop chance is authored; nobody has
## to remember to price it.
##
## Rates come from DropRarityIndex, a generated lookup of the best chance any
## source drops each item at. Rebuild it after touching a loot table:
##   godot --headless --path . -s tools/build_drop_rarity_index.gd

enum Tier { NONE, VALUABLE, PRIZE, RELIC }

## Drop chance at or below which each beam lights. Cut against the live spread:
## the relics sit at exactly 0.1%, Ossuran's weapons at 0.25%, and his material
## chest at 2% — so each tier lands on a real band of content rather than an
## arbitrary round number. Anything easier than RATE_VALUABLE is a routine drop.
const RATE_RELIC: float = 0.002      # 1 in 500 or rarer
const RATE_PRIZE: float = 0.01       # 1 in 100
const RATE_VALUABLE: float = 0.05    # 1 in 20

## Escape hatches for content that the numbers get wrong, using the tags array
## every Item already has — no schema change, no migration.
const TAG_FORCE: StringName = &"loot_beam"
const TAG_SUPPRESS: StringName = &"no_loot_beam"

const FRAMES_PATH: String = "res://source/common/gameplay/combat/vfx/loot_beam.tres"
## Clip name per tier — the pack ships the shape in eight colours, so tier is a
## different animation rather than a modulate (tinting an already-saturated cyan
## sprite toward gold goes muddy).
const TIER_CLIP: Dictionary = {
	Tier.VALUABLE: &"cyan",
	Tier.PRIZE: &"gold",
	Tier.RELIC: &"purple",
}
## Beam foot relative to the drop. The 64x96 art is drawn standing on its bottom
## edge, so the sprite is pushed up by half its height to plant it on the ground.
const FOOT_OFFSET: Vector2 = Vector2(0, -44)
## Under the item icon and its amount label, over the ground.
const BEAM_Z: int = -1


## Which beam, if any, [param item] deserves. Static so the drop can ask before
## paying to build a node, and so tests can assert the rule directly.
static func tier_for(item: Item) -> Tier:
	if item == null:
		return Tier.NONE
	if item.tags.has(TAG_SUPPRESS):
		return Tier.NONE
	if item.tags.has(TAG_FORCE):
		return Tier.PRIZE
	var id: int = int(item.get_meta("id", 0))
	if id <= 0:
		return Tier.NONE
	# A CHEST always beams, whatever its drop rate. Chests are the delivery
	# vehicle for every high-tier crafting material in the game, and the ranked
	# ornate grants land at 40% — a rate rule would never light the one drop the
	# whole late-game economy runs through. Rarer chests still escalate below.
	var chest_floor: Tier = Tier.VALUABLE if item is LootChestItem else Tier.NONE
	# No drop source = nothing to rate. Crafted and vendor items raise no beam
	# even when they are expensive; a beam marks a lucky find, not a rich one.
	var chance: float = DropRarityIndex.chance_for(id)
	if chance <= 0.0:
		return chest_floor
	if chance <= RATE_RELIC:
		return Tier.RELIC
	if chance <= RATE_PRIZE:
		return Tier.PRIZE
	if chance <= RATE_VALUABLE:
		return Tier.VALUABLE
	return chest_floor


## Build a beam for [param item] under [param parent], or return null when the
## item does not earn one. Caller does not need to pre-check the tier.
static func spawn(parent: Node, item: Item) -> LootBeam:
	var tier: Tier = tier_for(item)
	if tier == Tier.NONE or parent == null:
		return null
	var frames: SpriteFrames = load(FRAMES_PATH) as SpriteFrames
	var clip: StringName = TIER_CLIP.get(tier, &"")
	if frames == null or not frames.has_animation(clip):
		return null
	var beam: LootBeam = LootBeam.new()
	beam.sprite_frames = frames
	beam.animation = clip
	beam.position = FOOT_OFFSET
	beam.z_index = BEAM_Z
	# A pillar of light adds to what is behind it rather than hiding it, and it
	# must not eat the item icon it is standing under.
	beam.material = CanvasItemMaterial.new()
	(beam.material as CanvasItemMaterial).blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	parent.add_child(beam)
	beam.play(clip)
	return beam


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	centered = true
