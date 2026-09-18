## Data structure representing a connected player session, their stats, and active character instance.
##
## [Player] tracks network identity ([member peer_id]), display name, gameplay stats ([PlayerStats]),
## and manages lifecycle signals when their spatial character avatar ([member character]) is attached or removed.
class_name Player
extends RefCounted

## CONSTANTS

## Emitted when a character node avatar is assigned to this player.
signal character_added(char_node: Node)

## Emitted immediately before the player's existing character node avatar is detached or freed.
signal character_removing(char_node: Node)

## VARIABLES

## The unique multiplayer peer ID assigned by [MultiplayerAPI].
var peer_id: int

## Display name of the player.
var name: String

## Container holding player stats, attributes, and progression data.
var stats := PlayerStats.new()

## Active in-world character avatar node assigned to this player.
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

## Initializes a new player instance with a network peer ID and display name.
## [param p_peer_id]: Network multiplayer unique ID.
## [param p_name]: Display screen name.
func _init(p_peer_id: int, p_name: String) -> void:
	peer_id = p_peer_id
	name = p_name
