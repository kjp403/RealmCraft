extends PeddlerAction
## Hearth Stew: a slow heal and a small travel speed boost for
## [constant DURATION_S].
##
## THE SPEED IS A TRAVEL BUFF. It lapses the moment the eater is fighting and
## comes back when they disengage, without the timer stopping — see
## [method BuffService.apply]'s suppress_in_combat. A stew that made you faster
## mid-fight would be a kiting tool sold for 10,000 gold; a stew that ENDED on
## the first hit would be worthless in the field, where the whole fifteen minutes
## is spent walking between fights and occasionally being ambushed.
##
## THE HEAL IS REGEN, not a burst. [constant Stat.HEALTH_REGEN] is HP per second
## and the instance StatusTick already pays it out (carrying fractions between
## ticks, so a sub-1/s rate still heals). That tick is out-of-combat only, which
## is the right behaviour for food and means the heal needs no suppression flag
## of its own — it is already off in a fight.
##
## Neither half stacks: both go through the same exact-amount refresh, so a
## second bowl resets fifteen minutes rather than doubling anything.

const DURATION_S: float = 15.0 * 60.0
## Fraction of base move speed added while out of combat.
const SPEED_PCT: float = 0.05
## Extra HP per second on top of whatever the eater already regenerates.
const REGEN_PER_S: float = 1.5


static func speed_amount() -> float:
	return float(PlayerResource.BASE_STATS[Stat.MOVE_SPEED]) * SPEED_PCT


func apply(player: Player, _instance: ServerInstance) -> Dictionary:
	if player.player_resource == null or player.stats_component == null:
		return {"ok": false, "reason": "no_player"}
	BuffService.apply(player, Stat.HEALTH_REGEN, REGEN_PER_S, DURATION_S)
	BuffService.apply(
		player, Stat.MOVE_SPEED, speed_amount(), DURATION_S, false, true
	)
	return {
		"ok": true,
		"message": "Hearth Stew — %d minutes of slow healing, and +%d%% speed out of combat." % [
			int(DURATION_S / 60.0), int(SPEED_PCT * 100.0)
		],
	}
