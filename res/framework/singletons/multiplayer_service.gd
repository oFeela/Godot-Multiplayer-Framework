## Session creation and network peer setup service.
##
## [MultiplayerService] manages starting ENet or Steam hosted sessions, handling peer connections,
## processing failure hooks, and automatically transitioning players into the game world scene.
extends Node

## CONSTANTS

## Emitted when hosting or joining succeeds and the network peer becomes active.
signal session_started()

## Emitted when hosting or joining fails.
## [param reason]: Human-readable description explaining why the session failed.
signal session_failed(reason: String)

## OVERRIDEN METHODS

func _ready() -> void:
	# Steam lobby creation hook
	if Engine.has_singleton("SteamLobbyService") or get_node_or_null("/root/SteamLobbyService"):
		SteamLobbyService.host_created.connect(_on_network_ready)
		SteamLobbyService.client_joined.connect(_on_network_ready)
	
	# ENet client connection hook
	multiplayer.connected_to_server.connect(_on_network_ready)
	multiplayer.connection_failed.connect(_on_network_failed)

## PUBLICS

## Hosts a game session using Steam lobbies or ENet direct sockets depending on configuration.
## [param use_steam]: Toggles whether to attempt Steamworks lobby creation.
## [param port]: The network port to bind when hosting via ENet.
## [param max_players]: Maximum allowed peer connections on the server.
func host_game(use_steam: bool = FrameworkConfig.DEFAULT_USE_STEAM, port: int = FrameworkConfig.DEFAULT_PORT, max_players: int = FrameworkConfig.DEFAULT_MAX_PLAYERS) -> void:
	if use_steam and Steam.isSteamRunning():
		LoggerService.info("[MultiplayerService] Requesting Steam Lobby Creation...")
		SteamLobbyService.create_lobby()
	else:
		if not Steam.isSteamRunning():
			LoggerService.warn("[MultiplayerService] Steam is not running. Falling back to ENet.")
			
		LoggerService.info("[MultiplayerService] Starting ENet Host on port %d..." % port)
		var peer = ENetMultiplayerPeer.new()
		var error = peer.create_server(port, max_players)
		if error != OK:
			LoggerService.warn("[MultiplayerService] Failed to create ENet Host: %s" % str(error))
			session_failed.emit("Failed to create ENet server socket.")
			return
			
		multiplayer.multiplayer_peer = peer
		PlayersService.setup_host_player()
		_on_network_ready()

## Joins an existing game session via IP address or Steam invite overlay.
## [param use_steam]: Toggles whether joins should be delegated to Steam overlay invites.
## [param address]: The IP address or domain name of the remote host (ENet mode).
## [param port]: The remote host port to connect to (ENet mode).
func join_game(use_steam: bool = FrameworkConfig.DEFAULT_USE_STEAM, address: String = "127.0.0.1", port: int = FrameworkConfig.DEFAULT_PORT) -> void:
	if use_steam and Steam.isSteamRunning():
		LoggerService.warn("[MultiplayerService] Steam joins are handled via Steam invite overlays.")
		return
		
	if not Steam.isSteamRunning():
		LoggerService.warn("[MultiplayerService] Steam is not running. Falling back to ENet.")
		
	LoggerService.info("[MultiplayerService] Connecting via ENet to %s:%d..." % [address, port])
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	if error != OK:
		LoggerService.warn("[MultiplayerService] Failed to create ENet client: %s" % str(error))
		session_failed.emit("Failed to connect to host.")
		return
		
	multiplayer.multiplayer_peer = peer

## PRIVATES

## Callback triggered when hosting or connection succeeds; transitions to the game world.
func _on_network_ready() -> void:
	LoggerService.info("[MultiplayerService] Network ready! Transitioning to world scene...")
	session_started.emit()
	get_tree().change_scene_to_file(FrameworkConfig.MAIN_GAME_WORLD_PATH)

## Callback triggered when an ENet connection attempt fails.
func _on_network_failed() -> void:
	LoggerService.warn("[MultiplayerService] Connection attempt failed.")
	session_failed.emit("Connection failed.")
