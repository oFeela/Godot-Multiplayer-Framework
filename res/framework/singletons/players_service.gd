## Session player session lifecycle, identity mapping, and player stat replication service.
##
## [PlayersService] acts as the authoritative authority for connected player sessions.
## It handles client-server join handshakes, character binding, synchronized player statistics,
## host initialization, graceful server departures, and peer disconnections.
##
## [b]Note:[/b] Account [code]player_id[/code] strings are stored exclusively on the server for security
## and are not accessible by remote clients.
extends Node2D

## CONSTANTS

## Emitted when a new player joins the session and completes network registration.
## [param player]: The newly added [Player] instance.
signal player_added(player: Player)

## Emitted immediately before a player is removed from the session due to leaving, kicking, or disconnecting.
## [param player]: The [Player] instance being removed.
signal player_removing(player: Player)

## Emitted when the server is shutting down or when a client is disconnected from the host session.
signal server_shutting_down

## Emitted when a player's statistic is updated on the server and replicated locally.
## [param player]: The target [Player] whose stat was changed.
## [param stat_name]: The name identifier of the modified statistic.
## [param value]: The new value assigned to the statistic.
signal player_stat_changed(player: Player, stat_name: String, value: Variant)

## VARIABLES

## Dictionary mapping active peer IDs ([int]) to their corresponding runtime [Player] instances.
var _players: Dictionary[int, Player] = {}

## Server-only dictionary mapping peer IDs ([int]) to unique persistent account identifier strings ([code]player_id[/code]).
var _peer_to_player_id: Dictionary[int, String] = {}

## Reference to the local peer's own [Player] instance, or [code]null[/code] if not yet assigned.
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

## Authoritatively initializes and registers the host/server player session (Peer ID 1).
func setup_host_player() -> void:
	if not RunService.is_server():
		return
		
	var host_player = Player.new(
		1,
		_get_player_name_from_steam(1)
	)
	
	# Register host identity locally
	_peer_to_player_id[1] = PlayerIdentity.player_id
	_players[1] = host_player
	local_player = host_player
	
	player_added.emit(host_player)

## Client -> Server: Sends the local player's unique identity string and signals scene readiness in an atomic RPC handshake.
func notify_server_scene_ready() -> void:
	if RunService.is_server(): 
		return
	_rpc_client_ready_to_spawn.rpc_id(1, PlayerIdentity.player_id)

## Server RPC handler validating incoming client readiness and initiating player registration/state synchronization.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_ready_to_spawn(player_id: String) -> void:
	if not RunService.is_server(): 
		return
		
	var incoming_peer_id := multiplayer.get_remote_sender_id()
	
	if has_player(incoming_peer_id):
		LoggerService.warn("[PlayersService] Security Exception. Peer " + str(incoming_peer_id) + " attempted duplicate registration!")
		return
		
	# Store server-only mapping
	_peer_to_player_id[incoming_peer_id] = player_id
	LoggerService.info("[PlayersService] Mapped Peer %d -> Account '%s'" % [incoming_peer_id, player_id])
	
	_register_and_sync_new_player(incoming_peer_id)

## Returns the persistent account string ([code]player_id[/code]) for a given peer ID.
## [param peer_id]: The network peer ID.
## [return]: Account identifier string on the server, or empty string on clients/unregistered peers.
func get_player_id_from_peer_id(peer_id: int) -> String:
	return _peer_to_player_id.get(peer_id, "") # Defaults to empty string for client who attempted

## Returns the persistent account string ([code]player_id[/code]) associated with a [Player] instance.
## [param player]: The target [Player] object.
## [return]: Account identifier string on the server, or empty string if invalid or on client.
func get_player_id_from_player(player: Player) -> String:
	if not player:
		return ""
		
	return _peer_to_player_id.get(player.peer_id, "")

## Returns an array containing all active [Player] instances connected to the session.
## [return]: An [Array] of [Player] objects.
func get_players() -> Array[Player]:
	return _players.values()

## Looks up and returns the [Player] object linked to a given character node in the world.
## [param char_node]: The character node reference in the scene tree.
## [return]: The matching [Player] instance, or [code]null[/code] if no match is found.
func get_player_from_character(char_node: Node) -> Player:
	for p: Player in _players.values():
		if p.character == char_node:
			return p
	return null

## Convenience method to directly retrieve the spatial character node belonging to the local player.
## [return]: The character [Node], or [code]null[/code] if unassigned or invalid.
func get_local_character() -> Node:
	return local_player.character if local_player and is_instance_valid(local_player.character) else null

## Server-Only: Binds a target character node to a player and synchronizes the scene node path to all clients.
## [param player]: The target [Player] object.
## [param char_node]: The character node reference to assign.
func set_player_character(player: Player, char_node: Node) -> void:
	if not RunService.is_server():
		return
		
	if not player:
		return
	
	_rpc_set_player_character.rpc(player.peer_id, char_node.get_path())	

## RPC handler replicating character node assignments across peers.
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

## Safely fetches a [Player] instance by their network peer ID.
## [param peer_id]: The target peer ID.
## [return]: The associated [Player] instance, or [code]null[/code] if not found.
func get_player_from_peer_id(peer_id: int) -> Player:
	return _players.get(peer_id, null)

## Checks whether a given peer ID currently exists in the registered player registry.
## [param peer_id]: The target network peer ID.
## [return]: [code]true[/code] if connected and registered; otherwise [code]false[/code].
func has_player(peer_id: int) -> bool:
	return _players.has(peer_id)

## Server-Only: Sets a stat value on a target player and replicates the update across all connected clients.
## [param player]: The target [Player] instance.
## [param stat_name]: The string key name of the statistic.
## [param value]: The new value to store and replicate.
func set_stat(player: Player, stat_name: String, value: Variant) -> void:
	if not RunService.is_server():
		LoggerService.warn("[PlayersService] Authoritative Server rule violation. Only the server can change stats!")
		return
		
	if not player:
		return
		
	_rpc_set_stat.rpc(player.peer_id, stat_name, value)

## RPC handler processing and emitting player stat changes locally.
@rpc("authority", "call_local", "reliable")
func _rpc_set_stat(peer_id: int, stat_name: String, value: Variant) -> void:
	if has_player(peer_id):
		_players[peer_id].stats.set_value(stat_name, value)
		player_stat_changed.emit(_players[peer_id], stat_name, value)

## Retrieves a statistic value from a specific player's stat store.
## [param player]: The target [Player] instance.
## [param stat_name]: The name of the statistic to retrieve.
## [param default]: Default value to return if player or stat key does not exist (default: [code]0[/code]).
## [return]: The stat value if found, or [param default].
func get_stat(player: Player, stat_name: String, default: Variant = 0) -> Variant:
	if not player:
		return default
	
	var peer_id = player.peer_id
	
	if has_player(peer_id):
		return _players[peer_id].stats.get_value(stat_name, default)
	return default

## Server-Only: Forcefully disconnects a target player from the game session and cleans up their network socket.
## [param player]: The [Player] to kick.
## [param reason]: Log message explaining the kick reason.
func kick_player(player: Player, reason: String = "Kicked from server!") -> void:
	if not RunService.is_server():
		LoggerService.warn("[PlayerService] Only the server can kick!")
		return
		
	if not player:
		return
		
	var peer_id = player.peer_id
	
	# For server kick
	if peer_id == 1 or peer_id == multiplayer.get_unique_id():
		await leave_server()
		return
		
	if multiplayer.has_multiplayer_peer():
		_remove_player_internal(peer_id)
		await get_tree().create_timer(0.5).timeout
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)

## Initiates a graceful departure from the server for either a client or host player.
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

## Server RPC handler receiving a client's graceful disconnect request.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_graceful_leave() -> void:
	if not RunService.is_server():
		return
		
	var sender_id = multiplayer.get_remote_sender_id()
	if has_player(sender_id):
		_remove_player_internal(sender_id)
		await get_tree().create_timer(0.5).timeout
		
	_rpc_acknowledge_leave.rpc_id(sender_id)

## Client RPC handler acknowledging that the server processed their departure request.
@rpc("authority", "call_remote", "reliable")
func _rpc_acknowledge_leave() -> void:
	_clear_service_data()
	
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()

## RPC broadcast notifying all peers that the server host is shutting down.
@rpc("authority", "call_local", "reliable")
func _rpc_notify_server_shutting_down() -> void:
	if _players.is_empty() and _peer_to_player_id.is_empty() and not local_player:
		return
		
	server_shutting_down.emit()
	_clear_service_data()

## PRIVATES

## Resolves a display name for a peer via Steam persona APIs or falls back to generic formatting.
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

## Internal callback triggered when a raw peer socket opens on the server.
func _on_peer_connected(peer_id: int) -> void:
	if not RunService.is_server():
		return
	LoggerService.info("[PlayersService] Raw peer socket opened for: " + str(peer_id) + ". Waiting for scene handshake...")

## Server-side registration sequence creating player instances and synchronizing existing room state to a newcomer.
func _register_and_sync_new_player(peer_id: int) -> void:
	if not RunService.is_server():
		return
		
	# Create the new peer's Player on the server
	var new_player = Player.new(
		peer_id,
		_get_player_name_from_steam(peer_id)
	)
	
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

## Client RPC handler registering a newly connected peer locally.
@rpc("authority", "call_remote", "reliable")
func _rpc_on_peer_connected(peer_id: int, incoming_name: String) -> void:		
	var new_player = Player.new(
		peer_id,
		incoming_name
	)
	
	_players[peer_id] = new_player
	
	# Check if the newly added player belongs to the local player
	if peer_id == multiplayer.get_unique_id():
		local_player = new_player
	
	player_added.emit(new_player)

## Internal server callback handling peer disconnection sockets.
func _on_peer_disconnected(peer_id: int) -> void:
	if not RunService.is_server():
		return
		
	_remove_player_internal(peer_id)

## Client RPC handler processing a peer disconnection and cleaning up their character node.
@rpc("authority", "call_remote", "reliable")
func _rpc_on_peer_disconnected(peer_id: int) -> void:
	if has_player(peer_id):
		var dropping_player = _players[peer_id]
		player_removing.emit(dropping_player)
		_players.erase(peer_id)
		_peer_to_player_id.erase(peer_id)
		
		if dropping_player.character and is_instance_valid(dropping_player.character):
			dropping_player.character.queue_free()

## Internal server helper performing player removal, node cleanup, and network broadcast.
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

## Callback executed on clients when the underlying multiplayer network connection breaks unexpectedly.
func _on_server_disconnected() -> void:
	# If service data is already cleared, ignore (host cleanup or double disconnect)
	if _players.is_empty() and _peer_to_player_id.is_empty() and not local_player:
		return
		
	server_shutting_down.emit()
	_clear_service_data()

## Resets internal state dictionaries and frees active player character instances.
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
