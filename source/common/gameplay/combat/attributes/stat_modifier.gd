class_name StatModifier
extends Resource


## The gather stats are GLOBAL across every skill — a piece carrying GATHER_YIELD
## speeds up mining, fishing and herb picking alike. That is the right shape for
## generic gatherer's clothing, and the wrong shape for a themed Skilling Outfit;
## those pay per-skill utility resolved in [SkillingOutfitManager] and carry no
## base_modifiers at all.
@export_enum(
	Stat.HEALTH_MAX,
	Stat.MANA_MAX,
	Stat.MANA_REGEN,
	Stat.ARMOR,
	Stat.MR,
	Stat.AD,
	Stat.AP,
	Stat.ABILITY_HASTE,
	Stat.MOVE_SPEED,
	Stat.GATHER_SPEED,
	Stat.GATHER_YIELD,
	Stat.GATHER_XP
)
var stat_name: String = Stat.HEALTH_MAX

@export var value: float = 0.0
