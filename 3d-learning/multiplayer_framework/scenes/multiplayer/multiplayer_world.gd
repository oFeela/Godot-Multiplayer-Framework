extends Node3D # Or 2D
## Make sure to change MultiplayerWorld to Node3D/2D
## according to the game's needs (2D or 3D).

## VARIABLES
@export var player_character_scene := preload("uid://bg4uh6g3e6swi")
@export var auto_spawn: bool = true
@export var respawn_time: float = 3.0

@onready var player_characters_container = $PlayerCharactersContainer
@onready var multiplayer_spawner = $MultiplayerSpawner

## OVERRIDEN METHODS
func _ready() -> void:
	multiplayer_spawner.spawn_path = player_characters_container.get_path()
	
	# PlayersService connections
	PlayersService.player_added.connect(_on_player_joined_server)
	PlayersService.player_removing.connect(_on_player_left_server)
	
	# Spawn existing players (realistically only the server will be present)
	for player in PlayersService.get_players():
		_on_player_joined_server(player)
		
	# For clients, only tell the server to join as Player
	# if and only if the MultiplayerWorld scene has finished loading.
	if not PlayersService.is_server():
		PlayersService.notify_server_scene_ready()
		
	# For PlayersService testing
	# For testing client leaving
	PlayersService.server_shutting_down.connect(func():
		print("Disconnected from server!")
		get_tree().change_scene_to_file("res://multiplayer_framework/scenes/main/main.tscn")
	)
	if PlayersService.is_server():
		while true:
			if get_tree():
				await get_tree().create_timer(1).timeout
			else:
				continue
				
			PlayersService.set_stat(
				PlayersService.local_player, 
				"Level",
				PlayersService.get_stat(PlayersService.local_player, "Level")
				+ 1
			)
			
			for player in PlayersService.get_players():
				print(player.name)
				print(player.stats._data)
				print(player.character)
				await get_tree().create_timer(1).timeout
				PlayersService.kick_player(player)
	else:
		await get_tree().create_timer(10).timeout
		multiplayer.multiplayer_peer.close()
		
				
func _process(delta: float) -> void:
	pass
	
	
	
## PUBLICS

## Spawns the character of the given Player.
## Will instead respawn if already exists.
func spawn_player_character(player: Player) -> void:
	if not PlayersService.is_server() or not auto_spawn:
		return
		
	if player.character and is_instance_valid(player.character):
		player.character.queue_free()
		
	var new_character := player_character_scene.instantiate()
	new_character.name = str(player.peer_id)
	
	# Sync, authority will transfer to the client by now
	player_characters_container.add_child(new_character)
	
	# Find a spawn point
	var spawn_position = Vector3.ZERO if self is Node3D else Vector2.ZERO
	var spawn_points := _find_spawn_points(self)
	
	if spawn_points.size() > 0:
		var random_spawn = spawn_points.pick_random()
		spawn_position = random_spawn.global_position
		
	# Register to PlayersService, 
	# the character should have been replicated by now to other clients
	PlayersService.set_player_character(player, new_character)
		
	# Set the position of the character by calling the local client to do so
	force_reposition(player, spawn_position)
	
	# For respawning
	new_character.tree_exited.connect(_on_player_character_freed.bind(player))
	
	
func force_reposition(player: Player, target_position: Variant) -> void:
	if not PlayersService.is_server():
		return
	
	_rpc_force_reposition.rpc_id(player.peer_id, target_position)
	
@rpc("authority", "call_local", "reliable")
func _rpc_force_reposition(target_position: Variant) -> void:
	if PlayersService.local_player:
		PlayersService.local_player.character.global_position = target_position
	else:
		# Another attempt in case it's missing for whatever reason (delayed set)
		var character = player_characters_container.get_node_or_null(str(multiplayer.get_unique_id()))
		if character and is_instance_valid(character):
			character.global_position = target_position
	
	
	
## PRIVATES

## Called when a Player's character is freed.
## Example is for respawn purposes.
func _on_player_character_freed(player: Player):
	if not player in PlayersService.get_players():
		return
		
	print("[Workspace] ", player.name, " avatar was freed. Initiating ", "%.1f" % respawn_time, "-second respawn...")
	await get_tree().create_timer(respawn_time).timeout
	
	# Respawn them.
	# They won't respawn if 'auto_spawn' is false already handled inside.
	_on_player_joined_server(player)
	
	
## Finds any valid spawn points in the world.
## Done recursively.
func _find_spawn_points(curr_node: Node) -> Array[PlayerCharacterSpawnPoint]:
	var results: Array[PlayerCharacterSpawnPoint] = []
	
	if curr_node is PlayerCharacterSpawnPoint:
		results.append(curr_node)
	
	for child in curr_node.get_children():
		results.append_array(_find_spawn_points(child))
		
	return results
	
	
## Server-Authoritative instantiation loop
func _on_player_joined_server(player: Player) -> void:
	if not PlayersService.is_server() or not auto_spawn:
		return
		
	spawn_player_character(player)
		
		
## Server-Authoritative clean up
func _on_player_left_server(player: Player) -> void:
	print(player.name, " left the server!")
