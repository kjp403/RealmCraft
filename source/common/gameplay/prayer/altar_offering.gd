class_name AltarOffering
extends Resource
## One thing the altar accepts: an item, and the Prayer xp burning it pays.
## Authored inside the [AltarOfferingTable].

@export var item: Item
## Prayer xp per unit offered, before perks.
@export_range(0, 100000, 1) var xp: int = 1
## Prayer level needed before the altar will take it (0 = anyone).
@export_range(0, 99, 1) var required_level: int = 0
