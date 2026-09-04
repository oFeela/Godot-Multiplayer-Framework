extends Node

## CONSTANTS
signal host_created
signal client_joined

const LOBBY_TYPE := Steam.LobbyType.LOBBY_TYPE_FRIENDS_ONLY
const MAX_MEMBERS := 4

## VARIABLES
var peer: SteamMultiplayerPeer

## OVERRIDEN METHODS
func _ready() -> void:
	Steam.initRelayNetworkAccess()
	
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.join_requested.connect(_on_join_requested)
	
	
func _process(_delta: float) -> void:
	Steam.run_callbacks()
	
	
	
## PUBLICS

## Call to create a lobby
func create_lobby() -> void:
	# Emits the 'lobby_created' and 'lobby_joined' signals
	Steam.createLobby(LOBBY_TYPE, MAX_MEMBERS)
	
	
	
## PRIVATES

## Called after creating a lobby locally by the host
func _on_lobby_created(connect_: int, _lobby_id: int) -> void:
	if connect_ == Steam.RESULT_OK:
		peer = SteamMultiplayerPeer.new()
		peer.server_relay = true
		peer.create_host()
		multiplayer.multiplayer_peer = peer # To align with Godot's default MultiplayerAPI
		
		PlayersService.setup_host_player()
		
		host_created.emit()
		
		
## Called when joining a lobby (after creating the lobby or joining one)
func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response == Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		# For the lobby creator, already created their own peer.
		# Should not create a new peer.
		if Steam.getLobbyOwner(lobby_id) == Steam.getSteamID():
			return
		
		peer = SteamMultiplayerPeer.new()
		peer.server_relay = true
		peer.create_client(Steam.getLobbyOwner(lobby_id))
		multiplayer.multiplayer_peer = peer
		
		client_joined.emit()
		
		
## Called when attempting to join from Steam interface
func _on_join_requested(lobby_id: int, _steam_id: int) -> void:
	Steam.joinLobby(lobby_id)
