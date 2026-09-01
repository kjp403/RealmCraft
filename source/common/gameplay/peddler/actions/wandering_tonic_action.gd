extends PeddlerAction
## Wandering Tonic: +[constant SPEED_PCT] movement speed for
## [constant DURATION_S].
##
## DOES NOT STACK. [method BuffService.apply] already refreshes a buff with the
## same stat AND the same amount instead of adding a second one, so a second
## tonic resets the five minutes and never doubles the speed. That dedupe is
## exact-match on the amount, which is why the bonus is derived from the BASE
## move speed rather than from the drinker's current one: a percentage of a
## number that already includes the tonic would produce a slightly different
## amount every time and defeat the match.

## Fraction of base move speed added.
const SPEED_PCT: float = 0.15
const DURATION_S: float = 5.0 * 60.0


## The flat stat amount [constant SPEED_PCT] works out to. Static and derived
## from BASE_STATS so every drink computes the identical number.
static func bonus_amount() -> float:
	return float(PlayerResource.BASE_STATS[Stat.MOVE_SPEED]) * SPEED_PCT


func apply(player: Player, _instance: ServerInstance) -> Dictionary:
	if player.player_resource == null or player.stats_component == null:
		return {"ok": false, "reason": "no_player"}
	BuffService.apply(player, Stat.MOVE_SPEED, bonus_amount(), DURATION_S)
	return {
		"ok": true,
		"message": "Wandering Tonic — +%d%% speed for %d minutes." % [
			int(SPEED_PCT * 100.0), int(DURATION_S / 60.0)
		],
	}
