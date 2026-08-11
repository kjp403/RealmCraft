class_name LootDrop
extends Resource
## One possible drop from an enemy: an item, a quantity range, and a roll chance.

@export var item: Item
@export var min_amount: int = 1
@export var max_amount: int = 1
## Step is 0.0001, not 0.01: the boss relics sit at 0.0005 (1/2000), and at the
## old step the Inspector could not represent them — opening a boss and touching
## this field snapped the drop to 0.00 and silently disabled it. Editor hint only,
## no runtime effect.
@export_range(0.0, 1.0, 0.0001) var chance: float = 1.0
