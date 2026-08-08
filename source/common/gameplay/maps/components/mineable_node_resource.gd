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

## Optional world label (e.g. "Oak Tree"). Empty → falls back to the ore item name.
@export var display_name: String = ""
## The item granted per yield (a MaterialItem; its outlet is a vendor trade or a recipe).
@export var ore: Item
@export var yield_amount: int = 1
## How many job-XP grants happen on each yield. Examples:
##   { &"mining": 10 }                          # ore vein
##   { &"harvesting": 5, &"medicine": 5 }       # herb that teaches both
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

@export_group("Extraction")
## HP the per-player progress drains before one charge is consumed and the
## player gets the yield. Each pickaxe swing chips this down by the swing's
## extraction_damage.
@export var extraction_hp: int = 3
## Yields each player can take before THEIR pool depletes. Independent per player.
@export var max_charges: int = 3
## Continuous regen while at least 1 charge remains for that player: +1 every X sec.
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
