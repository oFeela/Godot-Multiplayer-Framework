extends Node3D # Or 2D
## Make sure to change MultiplayerWorld to Node3D/2D
## according to the game's needs (2D or 3D).

## VARIABLES
@export var auto_spawn: bool = FrameworkConfig.PLAYER_AUTO_SPAWN
@export var respawn_time: float = FrameworkConfig.PLAYER_RESPAWN_TIME

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
	
	# Change back to main menu
	multiplayer.server_disconnected.connect(func():
		get_tree().change_scene_to_file.call_deferred(FrameworkConfig.MAIN_MENU_PATH)
	)
		
	# Additional logic as needed (e.g. data store, etc.)
	if RunService.is_server():
		while true:
			await get_tree().create_timer(1).timeout
			LoggerService.debug(PlayerDataManager._profiles)
			for p: Player in PlayersService.get_players():
				var profile = PlayerDataManager._profiles.get(p, null)
				if not profile: continue
				
				profile.set_value("coins", profile.get_value("coins", 0) + 100)
				LoggerService.debug(p.name)
				LoggerService.debug(profile.data)
		pass
	
	
func _process(delta: float) -> void:
	pass
	
	
	
## PUBLICS

## Spawns the character of the given Player.
## Will instead respawn if already exists.
func spawn_player_character(player: Player) -> void:
	if not RunService.is_server() or not auto_spawn:
		return
		
	if player.character and is_instance_valid(player.character):
		var old_char = player.character
		player.character = null
		old_char.queue_free()
		
	# Find a spawn point
	var spawn_position = Vector3.ZERO if self is Node3D else Vector2.ZERO
	var spawn_points := _find_spawn_points(self)
	
	if spawn_points.size() > 0:
		var random_spawn = spawn_points.pick_random()
		spawn_position = random_spawn.global_position
		
	var new_character := NetworkSpawnerService.instantiate_entity(
		"player", 
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
	
	
func force_reposition(player: Player, target_position: Variant) -> void:
	if not RunService.is_server():
		return
	
	_rpc_force_reposition.rpc_id(player.peer_id, target_position)
	
@rpc("authority", "call_local", "reliable")
func _rpc_force_reposition(target_position: Variant) -> void:
	if PlayersService.local_player:
		PlayersService.local_player.character.global_position = target_position
	else:
		# Another attempt in case it's missing for whatever reason (delayed set)
		var character = get_node_or_null(str(multiplayer.get_unique_id()))
		if character and is_instance_valid(character):
			character.global_position = target_position
	
	
	
## PRIVATES

## Called when a Player's character is freed.
## Example is for respawn purposes.
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
	if not RunService.is_server() or not auto_spawn:
		return
		
	spawn_player_character(player)
		
		
## Server-Authoritative clean up
func _on_player_left_server(player: Player) -> void:
	LoggerService.info(player.name + " left the server!")
