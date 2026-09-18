## Base world controller managing player avatar spawning, spatial positioning, and scene lifecycle.
##
## [MultiplayerWorld] coordinates with [NetworkSpawnerService] and [PlayersService] to automatically
## spawn player characters at designated [Marker3D] locations, handle death/respawn timers,
## and manage scene navigation upon server disconnection.
class_name MultiplayerWorld3D
extends Node3D

## VARIABLES

## When [code]true[/code], automatically spawns and respawns characters upon joining or death.
@export var auto_spawn: bool = FrameworkConfig.PLAYER_AUTO_SPAWN

## Delay in seconds before a destroyed character is respawned.
@export var respawn_time: float = FrameworkConfig.PLAYER_RESPAWN_TIME

## Flags whether the host session is currently terminating to suppress pending respawn sequences.
var server_is_shutting_down: bool = false

## OVERRIDEN METHODS

func _ready() -> void:
	# So anything instantiated by the service will automatically be parented here
	NetworkSpawnerService.set_spawn_container(self)
	
	# PlayersService connections
	PlayersService.player_added.connect(_on_player_joined_server)
	PlayersService.player_removing.connect(_on_player_left_server)
	
	# Spawn existing players (realistically only the server will be present)
	for player in PlayersService.get_players():
		_on_player_joined_server(player)
		
	# For clients, only tell the server to join as Player
	# if and only if the MultiplayerWorld scene has finished loading.
	if not RunService.is_server():
		PlayersService.notify_server_scene_ready()
		
	# For the current client leaving, 'server_shutting_down' will be fired
	PlayersService.server_shutting_down.connect(func():
		LoggerService.info("Disconnected from server!")
		server_is_shutting_down = true
	)
	
	# Change back to main menu after disconnected
	multiplayer.server_disconnected.connect(func():
		get_tree().change_scene_to_file.call_deferred(FrameworkConfig.MAIN_MENU_PATH)
	)

## PUBLICS

## Server-Only: Spawns or replaces the character avatar node for a target [Player].
## [param player]: The target [Player] instance to spawn.
func spawn_player_character(player: Player) -> void:
	if not RunService.is_server() or not auto_spawn:
		return
		
	if player.character and is_instance_valid(player.character):
		var old_char = player.character
		player.character = null
		old_char.queue_free()
		
	# Find a spawn point
	var spawn_position = Vector3.ZERO
	var spawn_points := _find_spawn_points(self)
	
	if spawn_points.size() > 0:
		var random_spawn = spawn_points.pick_random()
		spawn_position = random_spawn.global_position
		
	var new_character := NetworkSpawnerService.instantiate_entity(
		"player_character", 
		spawn_position
	)
	new_character.name = str(player.peer_id)
	NetworkSpawnerService.replicate_entity(new_character, self)
		
	# Register to PlayersService, 
	# the character should have been replicated by now to other clients
	PlayersService.set_player_character(player, new_character)
		
	# Set the position of the character by calling the local client to do so
	force_reposition(player, spawn_position)
	
	# For respawning
	new_character.tree_exited.connect(_on_player_character_freed.bind(player), CONNECT_ONE_SHOT)

## Server-Only: Forces a client peer to override their character's global spatial position.
## [param player]: The target [Player] instance.
## [param target_position]: The target spatial position ([Vector3]).
func force_reposition(player: Player, target_position: Vector3) -> void:
	if not RunService.is_server():
		return
	
	_rpc_force_reposition.rpc_id(player.peer_id, target_position)

## RPC handler setting local character position on the authoritative target client.
@rpc("authority", "call_local", "reliable")
func _rpc_force_reposition(target_position: Vector3) -> void:
	if PlayersService.local_player:
		PlayersService.local_player.character.global_position = target_position
	else:
		# Another attempt in case it's missing for whatever reason (delayed set)
		var character = get_node_or_null(str(multiplayer.get_unique_id()))
		if character and is_instance_valid(character):
			character.global_position = target_position

## PRIVATES

## Handles player character node removal and schedules automatic respawn timers.
func _on_player_character_freed(player: Player):
	if server_is_shutting_down or not player in PlayersService.get_players():
		return
		
	LoggerService.info(player.name + " avatar was freed. Initiating " + "%.1f" % respawn_time + "-second respawn...")
	await get_tree().create_timer(respawn_time).timeout
	
	if server_is_shutting_down or not player in PlayersService.get_players():
		return
		
	# Respawn them.
	# They won't respawn if 'auto_spawn' is false already handled inside.
	_on_player_joined_server(player)

## Recursively scans the scene hierarchy to locate all active [Marker3D] nodes.
func _find_spawn_points(curr_node: Node) -> Array[Marker3D]:
	var results: Array[Marker3D] = []
	
	if curr_node is Marker3D:
		results.append(curr_node)
	
	for child in curr_node.get_children():
		results.append_array(_find_spawn_points(child))
		
	return results

## Callback executed when a new player joins the session to trigger initial character creation.
func _on_player_joined_server(player: Player) -> void:
	if not RunService.is_server() or not auto_spawn:
		return
		
	spawn_player_character(player)

## Callback executed when a player departs from the session.
func _on_player_left_server(player: Player) -> void:
	LoggerService.info(player.name + " left the server!")
