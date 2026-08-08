class_name StatsComponent
extends Node


## Fired whenever a stat changes locally.
#signal stat_changed(stat_name: StringName, value: float)


@export var synchronizer: StateSynchronizer

var stats: Stats = Stats.new()


func get_stat(stat_name: StringName) -> float:
	return stats.get(stat_name) as float


func set_stat(
	stat_name: StringName,
	value: float
) -> void:
	stats.set(stat_name, value)
	# NPCs replicate stats through their ReplicatedPropsContainer instead of a per-entity
	# synchronizer, so this can legitimately be unset.
	if synchronizer:
		synchronizer.mark_dirty_by_path(stat_path(stat_name), value, false)


## Additive modification.
## Positive or negative values are allowed
func modify_stat(
	stat_name: StringName,
	delta: float
) -> void:

	set_stat(
		stat_name,
		get_stat(stat_name) + delta
	)


static func stat_path(stat_name: StringName) -> String:
	return "StatsComponent:stats:%s" % stat_name


## Dynamic container
class Stats extends RefCounted:
	signal stat_changed(stat_name: StringName, value: float)


	var values: Dictionary[StringName, float]


	func _get(property: StringName) -> Variant:
		return values.get(property, 0.0)


	func _set(property: StringName, value: Variant) -> bool:
		# Coerce ints from VARIANT wire payloads so client sync can't reject
		# an unequip/attribute delta and leave a stale combat read-out.
		var as_float: float = 0.0
		match typeof(value):
			TYPE_FLOAT:
				as_float = value
			TYPE_INT:
				as_float = float(value)
			_:
				return false

		values[property] = as_float
		stat_changed.emit(property, as_float)
		return true
