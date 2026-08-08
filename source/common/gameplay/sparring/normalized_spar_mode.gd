class_name NormalizedSparMode
extends SparGameMode
## Fair-fight spar bracket: every fighter enters level-synced to [sync_level]
## (LevelSync — same HP baseline, attribute spread rescaled to the bracket's
## budget, equipment preserved but bracket-gated at queue join). Raw spar
## stations stay untouched — this mode is opt-in per station (owner-locked
## design 2026-07-19; brackets are DATA: author a .tres per bracket, assign it
## on a DuelMaster, done).
##
## What it does NOT normalize (on purpose, alpha scope): mastery kits — a
## higher-level fighter keeps more unlocked abilities. Equal stats, your kit.

## Fighters are synced to this level; equipped gear must have
## required_level / required_mastery_level <= this to queue (SparringService).
@export var sync_level: int = 10


func apply_to_fighter(player: Player) -> void:
	LevelSync.apply(player, sync_level)


func remove_from_fighter(player: Player) -> void:
	LevelSync.restore(player)


## True when [param player] wears any gear above the bracket. Checked at queue
## join so the lobby message explains the fix (unequip / downgrade).
func gear_over_bracket(player_resource: PlayerResource) -> bool:
	for slot_key: StringName in player_resource.equipment:
		var item: Item = ContentRegistryHub.load_by_id(&"items", int(player_resource.equipment[slot_key])) as Item
		if item == null:
			continue
		# Character-level and mastery-tier gates both count as bracket tiers.
		var req_level: Variant = item.get("required_level")
		var req_mastery: Variant = item.get("required_mastery_level")
		var tier: int = maxi(
			int(req_level) if req_level != null else 0,
			int(req_mastery) if req_mastery != null else 0
		)
		if tier > sync_level:
			return true
	return false
