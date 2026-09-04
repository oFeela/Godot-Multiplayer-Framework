extends Node

## CONSTANTS
## Emitted when hosting or joining succeeds and network peer is active
signal session_started()
## Emitted when hosting or joining fails
signal session_failed(reason: String)

## OVERRIDEN METHODS
func _ready() -> void:
	# Steam lobby creation hook
	if Engine.has_singleton("SteamNetwork") or get_node_or_null("/root/SteamNetwork"):
		SteamNetwork.host_created.connect(_on_network_ready)
		SteamNetwork.client_joined.connect(_on_network_ready)
	
	# ENet client connection hook
	multiplayer.connected_to_server.connect(_on_network_ready)
	multiplayer.connection_failed.connect(_on_network_failed)
	
	
	
## PUBLICS

## Host a game session using Steam or ENet depending on configuration
func host_game(use_steam: bool = FrameworkConfig.DEFAULT_USE_STEAM, port: int = FrameworkConfig.DEFAULT_PORT, max_players: int = FrameworkConfig.DEFAULT_MAX_PLAYERS) -> void:
	if use_steam and Steam.isSteamRunning():
		LoggerService.info("[MultiplayerService] Requesting Steam Lobby Creation...")
		SteamNetwork.create_lobby()
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
		
		
## Join an existing game session
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
func _on_network_ready() -> void:
	LoggerService.info("[MultiplayerService] Network ready! Transitioning to world scene...")
	session_started.emit()
	get_tree().change_scene_to_file(FrameworkConfig.MULTIPLAYER_WORLD_PATH)
	
	
func _on_network_failed() -> void:
	LoggerService.warn("[MultiplayerService] Connection attempt failed.")
	session_failed.emit("Connection failed.")
