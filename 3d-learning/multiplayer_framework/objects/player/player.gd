class_name Player
extends RefCounted

## CONSTANTS
signal character_added(char_node: Node)
signal character_removing(char_node: Node)

## VARIABLES
var peer_id: int
var name: String
var stats := PlayerStats.new()

var character: Node = null :
	set(new_char):
		if character == new_char: return
		
		# Old character removing
		if character and is_instance_valid(character):
			character_removing.emit(character)
			
		# New character addition
		character = new_char
		if character: # Ensure non-null assignment
			character_added.emit(character)

## OVERRIDEN METHODS
func _init(p_peer_id: int, p_name: String) -> void:
	peer_id = p_peer_id
	name = p_name
