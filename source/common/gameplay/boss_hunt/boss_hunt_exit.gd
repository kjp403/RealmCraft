class_name BossHuntExit
extends Interactable
## A "leave the hunt early" station, placed on the arena's spawn pad (where
## players also respawn on death). Click → the leave confirm → recall to the
## Guild Hall, dropping out of the contract.
##
## Deliberately a CLICK target rather than a walk-in door: the contract is paid
## for by the half hour, and an invisible warper anywhere in a one-room arena is
## something you'd eventually get kited across. Recall works as the universal
## escape too; this is the obvious one. Same shape as DungeonExit.


func _ready() -> void:
	menu_name = &"boss_hunt_exit"
	super._ready()
