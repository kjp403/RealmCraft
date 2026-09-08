class_name PhysicsLayers
## Named 2D physics layer bits + the common combat masks, so collision setup reads as roles
## instead of magic numbers. Layer NUMBERS (1-based) match project.godot's 2D physics layer
## names; each BIT below is (1 << (n-1)) for use in collision_layer / collision_mask. CODE
## uses these consts; .tscn/.tres files use the raw int (scenes can't reference consts) — keep
## them in sync with docs/combat_layers.md. Change a role's layer in ONE place here.

const CHARACTER_BODY: int = 1 << 0  ## layer 1 — player/NPC navigation bodies
const WORLD: int = 1 << 1           ## layer 2 — solid environment (walls, barriers)
const HURTBOX: int = 1 << 2         ## layer 3 — character damage-receiving areas (attack target)
const PICKUP: int = 1 << 3          ## layer 4 — coins / collectibles / doors (already in use here)
const FLAG: int = 1 << 4            ## layer 5 — territory objectives (attack target)
const HARVESTABLE: int = 1 << 5     ## layer 6 — mineable nodes (pick / sickle target)
const INTERACTABLE: int = 1 << 6    ## layer 7 — warpers / masters / stations
## layer 8 — decorative-but-collidable tiles (trees, crates, fences): blocks
## movement/spawns/blink same as WORLD, but deliberately excluded from
## projectile wall-rays (see arrow.gd) so scenery a shot merely grazes doesn't
## eat it the way an actual wall should.
const SCENERY: int = 1 << 7

## A projectile / melee hitbox hits: hurtboxes (damage) + flags (capture) + world (block).
## Deliberately NOT character bodies — those are navigation only.
const COMBAT_TARGET_MASK: int = WORLD | HURTBOX | FLAG
## "Anything solid a body can't walk through" — movement, spawn placement, and
## blink destination checks want BOTH real walls and decoration; only
## projectile wall-detection stays WORLD-only.
const SOLID_GROUND_MASK: int = WORLD | SCENERY
## Deprecated for gather arcs — historically PickArc used this and pulled NPC
## aggro via HurtBoxes. Gather swings must use HARVESTABLE only.
const HARVEST_TARGET_MASK: int = COMBAT_TARGET_MASK | HARVESTABLE
