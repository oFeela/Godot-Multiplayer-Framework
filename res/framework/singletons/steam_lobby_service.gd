## Steam Lobby management and connection signaling service.
##
## [SteamLobbyService] interfaces with Steamworks APIs via [SteamMultiplayerPeer] to manage lobby creation,
## remote peer joining via Steam overlay invites/requests, and network host setup.
extends Node

## CONSTANTS

## Emitted when a Steam lobby is successfully created by the host.
signal host_created

## Emitted when the local client successfully joins a remote Steam lobby.
signal client_joined

## Default lobby privacy type used when creating a match.
const LOBBY_TYPE := Steam.LobbyType.LOBBY_TYPE_FRIENDS_ONLY

## Maximum number of player slots allowed in the Steam lobby.
const MAX_MEMBERS := 4

## VARIABLES

## Active [SteamMultiplayerPeer] instance managing the network socket connection.
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

## Initiates asynchronous creation of a Steam lobby using the configured [constant LOBBY_TYPE] and [constant MAX_MEMBERS].
## Emits [signal host_created] upon success.
func create_lobby() -> void:
	# Emits the 'lobby_created' and 'lobby_joined' signals
	Steam.createLobby(LOBBY_TYPE, MAX_MEMBERS)

## PRIVATES

## Callback executed when Steam finishes creating a lobby requested by the host.
func _on_lobby_created(connect_: int, _lobby_id: int) -> void:
	if connect_ == Steam.RESULT_OK:
		peer = SteamMultiplayerPeer.new()
		peer.server_relay = true
		peer.create_host()
		multiplayer.multiplayer_peer = peer # To align with Godot's default MultiplayerAPI
		
		PlayersService.setup_host_player()
		
		host_created.emit()

## Callback executed when entering a Steam lobby (triggered for both host creation and client joining).
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

## Callback executed when a user accepts a Steam friend invite or joins via the Steam UI overlay.
func _on_join_requested(lobby_id: int, _steam_id: int) -> void:
	Steam.joinLobby(lobby_id)
