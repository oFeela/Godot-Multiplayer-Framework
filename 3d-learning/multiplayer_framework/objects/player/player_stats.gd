class_name PlayerStats
extends RefCounted

## CONSTANTS
signal stat_changed(stat_name: String, new_value: Variant)

## VARIABLES
var _data: Dictionary = {} # {"Level": 10, "Kills": 3} as an example

## PUBLICS

## Sets a value locally and emits the 'stat_changed' signal
func set_value(stat_name: String, value: Variant) -> void:
	_data[stat_name] = value
	stat_changed.emit(stat_name, value)
	
	
## Safely fetches a value, returning a fallback default if it hasn't been set ye
func get_value(stat_name: String, default: Variant = 0) -> Variant:
	return _data.get(stat_name, default)
	
	
## Checks if a specific stat key exists
func has_stat(stat_name: String) -> bool:
	return _data.has(stat_name)
