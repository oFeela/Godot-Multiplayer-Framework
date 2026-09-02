extends Node

## CONSTANTS

## Path where local saves are stored. 
## In production, swap file saving for an HTTP REST API or database connection.
const SAVE_DIR := "res://save_data/"

## VARIABLES
var _data_cache: Dictionary[int, Dictionary] = {} # { peer_id: Dictionary }

## OVERRIDEN METHODS
func _ready() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)
		
		
