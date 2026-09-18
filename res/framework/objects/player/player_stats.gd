## Dictionary-backed statistics container with signal emissions on value mutation.
##
## [PlayerStats] provides key-value storage for arbitrary player attributes (e.g., level, experience, kills)
## and emits the [signal stat_changed] signal whenever a stat value is updated.
class_name PlayerStats
extends RefCounted

## CONSTANTS

## Emitted whenever a statistic entry is created or updated via [method set_value].
signal stat_changed(stat_name: String, new_value: Variant)

## VARIABLES

var _data: Dictionary = {} # {"Level": 10, "Kills": 3} as an example

## PUBLICS

## Sets a value locally and emits the [signal stat_changed] signal.
## [param stat_name]: Key name of the statistic to update or create.
## [param value]: New value to assign to the statistic.
func set_value(stat_name: String, value: Variant) -> void:
	_data[stat_name] = value
	stat_changed.emit(stat_name, value)

## Safely fetches a statistic value, returning a fallback default if it hasn't been set yet.
## [param stat_name]: Key name of the statistic to retrieve.
## [param default]: Value to return if the statistic key does not exist. Defaults to [code]0[/code].
func get_value(stat_name: String, default: Variant = 0) -> Variant:
	return _data.get(stat_name, default)

## Checks if a specific stat key exists in internal storage.
## [param stat_name]: Key name of the statistic to check.
func has_stat(stat_name: String) -> bool:
	return _data.has(stat_name)
