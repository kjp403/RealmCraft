class_name DungeonReward
extends Resource
## The completion payout for a dungeon run: a gold amount (rolled in a range) plus
## a roll on a loot table. EVERY clearing player gets their OWN roll (the same
## participation-reward model as mob kills — co-op, no split). Attach it to the
## dungeon's DungeonResource; RoomNode hands it to DungeonService on clear.
##
## Daily charges (character-wide, see DungeonService): successful clears spend one
## charge. After charges are spent you can still run for XP / help / Hard records /
## dailies, but gold and loot are withheld. lockout_hours is unused legacy (kept so
## old .tres files load); charges gate rewards instead.

## Gold paid on completion, rolled uniformly in [gold_min, gold_max]. 0 = no gold.
@export var gold_min: int = 0
@export var gold_max: int = 0
## Loot table — each entry rolls independently (its own chance + amount range),
## exactly like a mob's loot. Curate it richer than trash drops.
@export var loot: Array[LootDrop] = []
## Optional capped pool (e.g. enchanted gem/cloth/ore). Each entry rolls
## independently, but at most [member exclusive_max] of the hits are kept.
@export var exclusive_loot: Array[LootDrop] = []
## Cap on how many exclusive_loot hits can grant in one clear. 2 = can get two
## of the three enchanted mats, never all three.
@export var exclusive_max: int = 2
## Unused legacy field (soft rolling lockout). Kept for .tres compatibility.
@export var lockout_hours: float = 0.0
## Guaranteed T3 Ornate Gold Chest (item 249 / gold_pink_large) count on a charged
## clear. Hard Mode tables should double Normal (e.g. 1 → 2). 0 = none. Not
## affected by solo chance/amount multipliers — the count is exact.
@export var ornate_chest_count: int = 0
