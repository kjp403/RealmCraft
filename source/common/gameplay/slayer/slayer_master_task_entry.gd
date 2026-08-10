class_name SlayerMasterTaskEntry
extends Resource
## One row of a SlayerMasterResource's weighted task table: which SlayerTaskDef,
## how likely it is to be rolled relative to the other rows (OSRS "task weight"),
## and the quantity range assigned when it's rolled. Shape mirrors ShopEntry
## (a reference + the tuning numbers a designer edits inline in the master's .tres).

@export var task: SlayerTaskDef
## Relative weight in THIS master's table — same mechanic as every OSRS Slayer
## master's assignment list (Mazchna's Cave bugs at weight 8 vs Ice warriors at
## weight 7, etc.). Higher = more likely. 0 effectively disables the row without
## deleting it.
@export var weight: int = 5
@export var min_amount: int = 15
@export var max_amount: int = 30
