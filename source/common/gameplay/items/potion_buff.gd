class_name PotionBuff
extends Resource
## One timed stat grant inside a [PotionItem]'s [member PotionItem.extra_buffs].
##
## Exists because [ConsumableItem] holds exactly ONE buff_stat/amount/duration
## triple, and the combination draughts grant two or three at once with
## DIFFERENT durations — the Aegis Elixir's armor runs for minutes while its
## Attack Damage runs for thirty seconds. Widening the base class to three
## parallel arrays would have made every existing potion's Inspector unreadable
## for the sake of two new items.


## Stat key from [Stat] — &"armor", &"ad", &"ap", &"mr", ...
@export var stat: StringName = &""
## Flat amount added for the duration. Negative is a self-debuff (a drawback on
## an otherwise strong draught); [BuffService] and the status strip both already
## handle a negative amount as a debuff row.
@export var amount: float = 0.0
@export var duration_s: float = 30.0


## Authored completely enough to do something? A half-filled entry is an
## authoring slip, not a weak buff, so it reads as "not a buff" everywhere
## rather than silently applying a zero-length one — the same rule
## [method ConsumableItem.is_coating] follows.
func is_valid() -> bool:
	return not stat.is_empty() and not is_zero_approx(amount) and duration_s > 0.0
