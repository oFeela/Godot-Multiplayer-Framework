extends Node2D

## Handles both Steam production lobbies and offline ENet loopback testing.
## Set 'use_steam' to true for Valve networks, false for rapid local PC testing.

## This is a template of how lobby creation/join
## should be. Use this as a guide to setup.

## This is not necessarily the starting scene of the game.
## It is the scene that allows the player to create/join a lobby

## CONSTANTS
const DEFAULT_PORT: int = 4242
const MAX_PLAYERS: int = 4

## VARIABLES
# Toggle this in the inspector to switch network pipelines instantly!
@export var use_steam: bool = true

@onready var host_button: Button = $CanvasLayer/HostButton
@onready var join_button: Button = $CanvasLayer/JoinButton


func _ready() -> void:
	SteamNetwork.host_created.connect(_on_network_ready)
	
	# The exact millisecond the client establishes a raw socket connection,
	# switch their active screen to the packed map file so the scene tree matches the server.
	multiplayer.connected_to_server.connect(_on_network_ready)
	
	host_button.pressed.connect(_on_host_button_pressed)
	join_button.pressed.connect(_on_join_button_pressed)


## Connected to HostButton pressed signal
func _on_host_button_pressed() -> void:
	if use_steam:
		LoggerService.info("[Main] Requesting Steam Lobby Creation...")
		SteamNetwork.create_lobby()
	else:
		LoggerService.info("[Main] Initializing Local ENet Test Host on port: " + str(DEFAULT_PORT))
		var peer = ENetMultiplayerPeer.new()
		var error = peer.create_server(DEFAULT_PORT, MAX_PLAYERS)
		if error != OK:
			LoggerService.warn("[Main] Failed to create ENet Host socket: " + str(error))
			return
			
		multiplayer.multiplayer_peer = peer
		
		# For local testing, we must manually invoke the host tracking initialization
		PlayersService.setup_host_player()
		_on_network_ready()


## Connected to your UI "Join" button pressed signal (Strictly needed for local ENet testing!)
func _on_join_button_pressed() -> void:
	if use_steam:
		LoggerService.warn("[Main] For Steam, please accept a friend invite via the overlay.")
		return
		
	LoggerService.info("[Main] Connecting to Local ENet Test Host at 127.0.0.1...")
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client("127.0.0.1", DEFAULT_PORT)
	if error != OK:
		LoggerService.warn("[Main] Failed to create ENet client socket: " + str(error))
		return
		
	multiplayer.multiplayer_peer = peer


func _on_network_ready() -> void:
	LoggerService.info("[Main] Connection handshake finalized! Changing scene to active workspace...")
	get_tree().change_scene_to_file(FrameworkConfig.MULTIPLAYER_WORLD_PATH)
