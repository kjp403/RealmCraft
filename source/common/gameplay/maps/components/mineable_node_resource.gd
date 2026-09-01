class_name MineableNodeResource
extends Resource
## Data-only definition of a gathering node "type" (Copper Vein, Iron Vein,
## Healing Herb, ...). A [MineableNode] scene instanced in a map points at
## one of these resources via its `data` export, then reads the gathering
## config from it. Tuning copper vein values now updates every copper vein
## in every map at once — same pattern as [JobPerks] for jobs.
##
## Author one `.tres` per node type under
## `source/common/gameplay/maps/components/mineable_nodes/`. The
## upcoming jobs/source-slug bake tool will scan that folder, look at each
## resource's `job_xp` dict, and auto-populate the matching JobPerks
## `source_slugs` lists — killing the hand-maintained content drift.

const SHIMMER_SHADER: Shader = preload("res://source/common/gameplay/items/shimmer.gdshader")

var _shimmer_material: ShaderMaterial = null

## Optional world label (e.g. "Oak Tree"). Empty → falls back to the ore item name.
@export var display_name: String = ""
## The item granted per yield (a MaterialItem; its outlet is a vendor trade or a recipe).
@export var ore: Item
@export var yield_amount: int = 1
## How many job-XP grants happen on each yield. Examples:
##   { &"mining": 10 }                          # ore vein
##   { &"harvesting": 5, &"herblore": 5 }       # herb that teaches both
@export var job_xp: Dictionary[StringName, int] = {&"mining": 10}
## Minimum level in the node's primary job (first key in [member job_xp]).
## 0 / 1 = no meaningful gate for a fresh level-1 character.
@export var required_level: int = 0
## Tool the player must have equipped (matched against ToolItem.tool_type).
@export var required_tool: StringName = &"pickaxe"

@export_group("Secondary Catch")
## Optional rarer catch rolled instead of [member ore] (e.g. Cod at a Herring hole).
## When set and the roll succeeds, the player receives this item and
## [member secondary_job_xp] instead of the primary yield.
@export var secondary_ore: Item
## Chance (0–1) to catch [member secondary_ore] instead of [member ore] on a yield.
@export_range(0.0, 1.0, 0.01) var secondary_chance: float = 0.0
## Job XP granted when the secondary catch wins. Empty → reuse [member job_xp].
@export var secondary_job_xp: Dictionary[StringName, int] = {}

@export_group("Byproduct")
## Optional SECOND item granted alongside [member ore] on a successful yield
## (trees drop Headless Arrows for Fletching). Unlike [member secondary_ore]
## this does not replace the primary — the player gets both.
##
## Gated behind a perk, not free: the amount is scaled by the harvesting job's
## [code]&"shaft_yield"[/code] effect, which is 0.0 until the player spends a
## point. A node with a byproduct set therefore drops nothing extra for a
## player who hasn't invested in it.
@export var byproduct_item: Item
## Full byproduct count, i.e. what a player with the effect maxed receives.
@export var byproduct_amount: int = 0
## Job whose perks scale the byproduct. Defaults to Fletching since that is the
## only consumer today; a future byproduct just points at its own job.
@export var byproduct_job: StringName = &"fletching"

@export_group("Extraction")
## HP the per-player progress drains before one charge is consumed and the
## player gets the yield. Each pickaxe swing chips this down by the swing's
## extraction_damage.
@export var extraction_hp: int = 3
## Yields each player can take before THEIR pool depletes. Independent per player.
## With [member min_charges] set this is the TOP of the random roll.
## Defaults to the standard gathering pool (see [member min_charges]) so a newly
## authored ore / herb / tree node needs no charge tuning at all.
@export var max_charges: int = 25
## Bottom of the random pool roll. When > 0 (and below [member max_charges]) the
## node hands each player a fresh random pool size in
## [code][min_charges, max_charges][/code] every time it fills, and skips the
## per-charge trickle regen — the vein simply runs until it is mined out, then
## respawns after [member depleted_recharge_seconds] with a new roll.
## 0 = fixed pool of [member max_charges] with trickle regen. Nothing ships on
## that path today; it exists for a node that should refill while you stand at it.
##
## The default is the standard gathering pool: every tool-swing node — ore veins,
## herb patches, trees — rolls 3-25 yields per player and runs until it is worked
## out, then respawns after [member depleted_recharge_seconds] with a new roll.
## Fishing holes run the same system on their own 5-20 roll. New node types
## inherit the default automatically; only override to opt out.
@export var min_charges: int = 3
## Continuous regen while at least 1 charge remains for that player: +1 every X sec.
## Ignored by nodes with a random pool ([member min_charges] > 0).
@export var charge_regen_seconds: float = 12.0
## Recharge time after a player's pool hits 0. Longer than continuous regen,
## refills ALL of that player's charges at once.
@export var depleted_recharge_seconds: float = 60.0
## Per-player cooldown after a successful extraction.
@export var player_cooldown_seconds: float = 5.0

@export_group("Visual")
## Sprite shown at the node. Use an [AtlasTexture] (right-click in the
## inspector → "New AtlasTexture", then assign the spritesheet to its `atlas`
## and click "Edit Region" to pick the sub-rect visually). Prefer a clean
## 32×32 region for hub veins. A plain Texture2D also works for one-off art.
@export var texture: Texture2D
## Optional look when charges hit 0 (e.g. plain rubble without ore flecks).
## Leave empty to keep [member texture] and dim it with a gray modulate instead.
@export var depleted_texture: Texture2D
## Uniform sprite scale (1.0 = texture pixel size). Use >1 so higher-tier
## trees (Oak, etc.) read larger than the shared 64×96 woodcutting art.
@export var visual_scale: float = 1.0

## Extra idle frames, cycled client-side on top of [member texture] (which is
## always frame 0). Two frames is a bob or a twinkle; four is a pulse ramp.
## Empty = a still node, which is every ore vein and herb we ship.
## Frames must be the same size as [member texture] or the node will jump.
@export var idle_frames: Array[Texture2D] = []
## Seconds each idle frame is held. 0.5 reads as a slow breath at 2 frames;
## drop it toward 0.2 for a 4-frame pulse that should feel like energy.
@export var idle_frame_seconds: float = 0.5

## Animated shine over the node sprite (Celestial's starlight, Astralite's
## cosmic pulse). 0 = no shimmer. Mirrors [member Item.shimmer_strength].
@export_range(0.0, 2.0, 0.05) var shimmer_strength: float = 0.0
## Colour of the highlight sweep and twinkle.
@export var shimmer_tint: Color = Color(1.0, 0.95, 0.72)
## Sweep / twinkle rate.
@export_range(0.1, 4.0, 0.05) var shimmer_speed: float = 1.0
## Cycle the sprite's hues as well.
@export var shimmer_iridescent: bool = false

@export_group("Chop FX")
## Particle burst played on the gathering player's client each time a swing
## lands. Empty = no burst (the default; ore veins and herbs stay quiet).
## Supported: [code]drift_up[/code] (motes rising), [code]sparkle[/code]
## (cross-shaped twinkles), [code]spark_side[/code] (sparks thrown left and
## right off the hit point), [code]starburst[/code] (an outward explosion).
@export var chop_fx_style: StringName = &""
## Main particle colour.
@export var chop_fx_color: Color = Color.WHITE
## Second colour the burst fades toward, so a burst is never one flat hue.
@export var chop_fx_color_alt: Color = Color.WHITE
## Particles per swing. Keep it low — this fires on every axe hit.
@export var chop_fx_amount: int = 10

## How much BRIGHTER the node goes on the frame a swing lands, as a fraction
## above normal — 0.5 peaks at 1.5x. 0 = no flash, which is every node that
## shipped before the high ore tiers. This is the cue that says "that hit
## counted": the particle burst reads as decoration, but a flash on the struck
## body itself is what makes a swing feel connected.
##
## It is an overbright multiplier, not a blend toward a colour, because
## [code]modulate[/code] multiplies — a flash authored at or below white can
## only darken the sprite. 0.35-0.5 is the useful band; pale art (Celestial)
## saturates sooner, dark rock (Obsidian) can take more before it reads.
@export_range(0.0, 1.0, 0.05) var hit_flash_strength: float = 0.0
## Colour of the flash, scaled up by [member hit_flash_strength]. White for a
## plain physical impact; tint it toward the metal for a hit that should feel
## like it woke something up (Astralite flashes violet-white). Alpha is ignored.
@export var hit_flash_color: Color = Color.WHITE
## Flash duration. Longer than ~0.2 stops reading as an impact and starts
## reading as a glow, and swings land every ~0.3s at the top tiers.
@export_range(0.02, 0.5, 0.01) var hit_flash_seconds: float = 0.12
## Peak sprite kick, in texture pixels, on a landed swing. The node jolts along
## this and settles back with a damped bounce inside [member hit_flash_seconds]
## x2. 0 = a rock that does not move, which is the old behaviour.
## 2-4 is a chip; past ~6 the rock reads as wobbling rather than being struck.
@export_range(0.0, 8.0, 0.5) var hit_recoil_pixels: float = 0.0


## Shared material for [member shimmer_strength] > 0, else null. Client-only.
func shimmer_material() -> ShaderMaterial:
	if shimmer_strength <= 0.0:
		return null
	if _shimmer_material == null:
		_shimmer_material = ShaderMaterial.new()
		_shimmer_material.shader = SHIMMER_SHADER
		_shimmer_material.set_shader_parameter(&"shimmer_strength", shimmer_strength)
		_shimmer_material.set_shader_parameter(&"shimmer_tint", shimmer_tint)
		_shimmer_material.set_shader_parameter(&"shimmer_speed", shimmer_speed)
		_shimmer_material.set_shader_parameter(&"shimmer_iridescent", shimmer_iridescent)
	return _shimmer_material
