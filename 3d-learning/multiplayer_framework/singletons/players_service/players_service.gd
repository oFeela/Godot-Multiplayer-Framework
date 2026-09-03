extends Node2D

## CONSTANTS
signal player_added(player: Player)
signal player_removing(player: Player)
signal server_shutting_down
signal player_stat_changed(player: Player, stat_name: String, value: Variant)

## VARIABLES
var _players: Dictionary[int, Player] = {}
var _peer_to_player_id: Dictionary[int, String] = {}
var local_player: Player = null

## BUILT-IN METHODS
func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	# Stop Godot from instantly killing the process on window close
	get_tree().set_auto_accept_quit(false)
	
	
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		await leave_server()
		get_tree().quit()
	
	
	
## PUBLICS

## Setup Host Player (Server / Singleplayer Host)
func setup_host_player() -> void:
	if not RunService.is_server():
		return
		
	var host_player = Player.new()
	host_player.peer_id = 1
	host_player.name = _get_player_name_from_steam(1)
	
	# Register host identity locally
	_peer_to_player_id[1] = PlayerIdentity.player_id
	_players[1] = host_player
	local_player = host_player
	
	player_added.emit(host_player)
	
	
## Sends player_id and signals readiness in ONE atomic RPC
func notify_server_scene_ready() -> void:
	if RunService.is_server(): 
		return
	_rpc_client_ready_to_spawn.rpc_id(1, PlayerIdentity.player_id)
	
	
@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_ready_to_spawn(player_id: String) -> void:
	if not RunService.is_server(): 
		return
		
	var incoming_peer_id = multiplayer.get_remote_sender_id()
	
	if has_player(incoming_peer_id):
		print_debug("Warning: Security Exception. Peer ", incoming_peer_id, " attempted duplicate registration!")
		return
		
	# Store server-only mapping
	_peer_to_player_id[incoming_peer_id] = player_id
	print("[PlayersService] Mapped Peer %d -> Account '%s'" % [incoming_peer_id, player_id])
	
	_register_and_sync_new_player(incoming_peer_id)
	
	
## Helper to fetch player_id from peer_id
func get_player_id_from_peer_id(peer_id: int) -> String:
	return _peer_to_player_id.get(peer_id, "") # Defaults to empty string for client who attempted
	
	
## Helper to fetch player_id
func get_player_id_from_player(player: Player) -> String:
	if not player:
		return ""
		
	return _peer_to_player_id.get(player.peer_id, "")
	
	
## Gets all connected players
func get_players() -> Array[Player]:
	return _players.values()
	
	
## Gets the correspoding Player from their character.
## Returns null if invalid.
func get_player_from_character(char_node: Node) -> Player:
	for p: Player in _players.values():
		if p.character == char_node:
			return p
	return null
	
	
## Helper to get the local Player's character node directly
func get_local_character() -> Node:
	return local_player.character if local_player and is_instance_valid(local_player.character) else null
	
	
## Server Only: Sets the Player character and then syncs across to clients
func set_player_character(player: Player, char_node: Node) -> void:
	if not RunService.is_server():
		return
		
	if not player:
		return
	
	_rpc_set_player_character.rpc(player.peer_id, char_node.get_path())	
	
@rpc("authority", "call_local", "reliable")
func _rpc_set_player_character(peer_id: int, char_node_path: NodePath) -> void:
	if not has_player(peer_id):
		return
		
	if has_node(char_node_path):
		_players[peer_id].character = get_node(char_node_path)
		return
		
	# Wait for arrival by using node_added signal
	var root = get_tree()
	var listener: Callable
	listener = func(node: Node):
		if node.get_path() == char_node_path:
			_players[peer_id].character = node
			root.node_added.disconnect(listener)
	root.node_added.connect(listener)
	
	
## Safely fetches a Player object by their peer_id. Returns null if not found.
func get_player_from_peer_id(peer_id: int) -> Player:
	return _players.get(peer_id, null)
	
	
## Helper to check if a peer ID is currently connected
func has_player(peer_id: int) -> bool:
	return _players.has(peer_id)
	
	
## Server-only: Updates a Player's stat and replicates it out to all clients.
func set_stat(player: Player, stat_name: String, value: Variant) -> void:
	if not RunService.is_server():
		print_debug("Warning: Authoritative Server rule violation. Only the server can change stats!")
		return
		
	if not player:
		return
		
	_rpc_set_stat.rpc(player.peer_id, stat_name, value)
	
@rpc("authority", "call_local", "reliable")
func _rpc_set_stat(peer_id: int, stat_name: String, value: Variant) -> void:
	if has_player(peer_id):
		print("On peer ", multiplayer.get_unique_id(), " set peer ", peer_id, " stat of ", stat_name, " to ", value)
		_players[peer_id].stats.set_value(stat_name, value)
		player_stat_changed.emit(_players[peer_id], stat_name, value)
		
		
## Safely fetches a stat from a specific Player's stats.
func get_stat(player: Player, stat_name: String, default: Variant = 0) -> Variant:
	if not player:
		return default
	
	var peer_id = player.peer_id
	
	if has_player(peer_id):
		return _players[peer_id].stats.get_value(stat_name, default)
	return default
	
	
## Server-only: Forcefully disconnects a player from the game session.
func kick_player(player: Player, reason: String = "Kicked from server!") -> void:
	if not RunService.is_server():
		print_debug("Warning: Only the server can kick!")
		return
		
	if not player:
		return
		
	var peer_id = player.peer_id
	print("Kicking Peer ID: ", peer_id, " Reason: ", reason)
	
	# For server kick
	if peer_id == 1 or peer_id == multiplayer.get_unique_id():
		await leave_server()
		return
		
	if multiplayer.has_multiplayer_peer():
		_remove_player_internal(peer_id)
		await get_tree().create_timer(0.5).timeout
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		
		
## Call this function when a client/server voluntarily wants to leave the server.
func leave_server() -> void:
	if multiplayer.has_multiplayer_peer():
		if RunService.is_server():
			_rpc_notify_server_shutting_down.rpc()
			
			# Yield to give network buffer time to flush save RPCs to clients
			await get_tree().create_timer(1.0).timeout
		else:
			server_shutting_down.emit()
			
			# Ask server to process player_removing over open socket
			_rpc_request_graceful_leave.rpc_id(1)
			
			# Fallback timeout in case server drops unexpectedly
			await get_tree().create_timer(1.0).timeout
			_clear_service_data()
			
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
		
@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_graceful_leave() -> void:
	if not RunService.is_server():
		return
		
	var sender_id = multiplayer.get_remote_sender_id()
	if has_player(sender_id):
		_remove_player_internal(sender_id)
		await get_tree().create_timer(0.5).timeout
		
	_rpc_acknowledge_leave.rpc_id(sender_id)
	
@rpc("authority", "call_remote", "reliable")
func _rpc_acknowledge_leave() -> void:
	_clear_service_data()
	
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
		
@rpc("authority", "call_local", "reliable")
func _rpc_notify_server_shutting_down() -> void:
	if _players.is_empty() and _peer_to_player_id.is_empty() and not local_player:
		return
		
	server_shutting_down.emit()
	_clear_service_data()
		
		
## PRIVATES

## Fetches the player username from Steam.
func _get_player_name_from_steam(peer_id: int) -> String:
	# If Steam isn't active or loaded, fallback immediately
	if not ClassDB.class_exists("Steam") or not Steam.isSteamRunning():
		return "Player_" + str(peer_id)
		
	# If it's the current user who requested it,
	# fetch their local Steam profile name
	if peer_id == 1 or peer_id == multiplayer.get_unique_id():
		return Steam.getPersonaName()
		
	# Otherwise, extract their Steam ID from requester's SteamMultiplayerPeer
	if multiplayer.has_multiplayer_peer():
		var peer = multiplayer.multiplayer_peer as SteamMultiplayerPeer
		if peer:
			var steam_id: int = peer.get_steam_id_for_peer_id(peer_id)
			if steam_id > 0:
				return Steam.getFriendPersonaName(steam_id)
		
	return "Player_" + str(peer_id)
	
## Server-side handling upon peer connection.
func _on_peer_connected(peer_id: int) -> void:
	if not RunService.is_server():
		return
	print("[PlayersService] Raw peer socket opened for: ", peer_id, ". Waiting for scene handshake...")
	
	
## Server-side handling of Player creation upon peer connection.
func _register_and_sync_new_player(peer_id: int) -> void:
	if not RunService.is_server():
		return
		
	# Create the new peer's Player on the server
	var new_player = Player.new()
	new_player.peer_id = peer_id
	new_player.name = _get_player_name_from_steam(peer_id)
	
	# Sync existing Players to the newly connected peer
	for existing_peer_id in _players.keys():
		var existing_player = _players[existing_peer_id]
		_rpc_on_peer_connected.rpc_id(
			peer_id, 
			existing_peer_id, 
			existing_player.name
		)
		
		# Sync the stats of the existing player
		for stat_name in existing_player.stats._data.keys():
			var stat_val = existing_player.stats.get_value(stat_name)
			_rpc_set_stat.rpc_id(
				peer_id, 
				existing_peer_id, 
				stat_name, 
				stat_val
			)
			
		# Sync the character of the existing player
		if existing_player.character and is_instance_valid(existing_player.character):
			_rpc_set_player_character.rpc_id(
				peer_id,
				existing_peer_id,
				existing_player.character.get_path()
			)
	
	_players[peer_id] = new_player
	
	# Broadcast to EVERYONE (other than server since 'call_remote') about the addition
	_rpc_on_peer_connected.rpc(peer_id, new_player.name)
	
	# Broadcast the newcomer's stats out to everyone else
	for stat_name in new_player.stats._data.keys():
		var stat_val = new_player.stats.get_value(stat_name)
		_rpc_set_stat.rpc(peer_id, stat_name, stat_val)
		
	player_added.emit(new_player)
	
	
## Client sync of a new Player upon peer connection.
@rpc("authority", "call_remote", "reliable")
func _rpc_on_peer_connected(peer_id: int, incoming_name: String) -> void:		
	var new_player = Player.new()
	new_player.peer_id = peer_id
	new_player.name = incoming_name
	
	_players[peer_id] = new_player
	
	# Check if the newly added player belongs to the local player
	if peer_id == multiplayer.get_unique_id():
		local_player = new_player
	
	player_added.emit(new_player)
	
	
## Server-side handling of Player destruction upon peer disconnection.
func _on_peer_disconnected(peer_id: int) -> void:
	if not RunService.is_server():
		return
		
	_remove_player_internal(peer_id)
	
	
## Client sync of a Player removal upon peer disconnection.
@rpc("authority", "call_remote", "reliable")
func _rpc_on_peer_disconnected(peer_id: int) -> void:
	if has_player(peer_id):
		var dropping_player = _players[peer_id]
		player_removing.emit(dropping_player)
		_players.erase(peer_id)
		_peer_to_player_id.erase(peer_id)
		
		if dropping_player.character and is_instance_valid(dropping_player.character):
			dropping_player.character.queue_free()
			
			
## Server-only: Handles local removal, signal emission, and replication.
func _remove_player_internal(peer_id: int) -> void:
	if not has_player(peer_id):
		return
		
	var dropping_player = _players[peer_id]
	player_removing.emit(dropping_player)

	if dropping_player.character and is_instance_valid(dropping_player.character):
		dropping_player.character.queue_free()
		
	_players.erase(peer_id)
	_peer_to_player_id.erase(peer_id)
	
	# If server, replicate to others
	if RunService.is_server():
		_rpc_on_peer_disconnected.rpc(peer_id)
		
		
## Will automically be called once the server disconnects
## All clients will call this themselves. Server doesn't broadcast.
## This is used for unexpected disconnect.
## Since for graceful leave, it won't rely after 'multiplayer.multiplayer_peer' has been disconnected.
func _on_server_disconnected() -> void:
	# If service data is already cleared, ignore (host cleanup or double disconnect)
	if _players.is_empty() and _peer_to_player_id.is_empty() and not local_player:
		return
		
	server_shutting_down.emit()
	_clear_service_data()
	
	
## Resets the service state/data.
func _clear_service_data() -> void:
	for peer_id in _players.keys():
		# Cannot simply call _rpc_on_peer_disconnected 
		# because this will be called locally
		var dropping_player = _players.get(peer_id, null)
		if not dropping_player: continue
		
		player_removing.emit(dropping_player)
		
		if dropping_player.character and is_instance_valid(dropping_player.character):
			dropping_player.character.queue_free()
		
	_players.clear()
	_peer_to_player_id.clear()
	local_player = null
