extends Node

## This is the script to customize for what data needs to be saved.
## It uses the DataProfielStore and DataProfile abstraction.

## CONSTANTS
const player_data_store_name := "PlayerData_1"
const data_store_mode := DataProfileStore.StoreMode.P2P

## VARIABLES
var player_data_store: DataProfileStore
var _profiles: Dictionary[Player, DataProfile] = {}

## TEMPLATES
const PLAYER_TEMPLATE := {
	"coins": 100,
	"gems": 10,
	"level": 1,
	"xp": 0.0,
	"ascension": 0,
}

## OVERRIDEN METHODS
func _ready() -> void:
	player_data_store = DataProfileStore.new(
		player_data_store_name,
		PLAYER_TEMPLATE,
		data_store_mode
	)
	add_child(player_data_store)
	
	# Player signals
	PlayersService.player_added.connect(_on_player_added)
	PlayersService.player_removing.connect(_on_player_removing)
	
	# Shutdown signal
	PlayersService.server_shutting_down.connect(_on_server_shutting_down)
	
	
## PRIVATES
func _on_player_added(player: Player):
	if not RunService.is_server():
		return
		
	# Load the profile using the validated account player_id as the key
	var peer_id = player.peer_id
	var player_id = PlayersService.get_player_id_from_peer_id(peer_id)
	var profile = player_data_store.load_profile(peer_id, player_id)
	
	if profile:
		_on_profile_ready(player, profile)
	else:
		if player_data_store.store_mode == DataProfileStore.StoreMode.P2P:
			# Wait for arrival
			var wrapper: Array[Callable] = []

			wrapper.append(func(key: String):
				if key == player_id:
					var loaded_profile = player_data_store.get_profile(key)
					if loaded_profile:
						_on_profile_ready(player, loaded_profile)
						
					# Properly disconnects because wrapper[0] evaluates to the actual Callable
					if player_data_store.client_payload_received.is_connected(wrapper[0]):
						player_data_store.client_payload_received.disconnect(wrapper[0])
			)

			player_data_store.client_payload_received.connect(wrapper[0])
		else:
			PlayersService.kick_player(player, "Data failed to load. Please rejoin!")
		
		
func _on_profile_ready(player: Player, profile: DataProfile) -> void:
	profile.unlocked.connect(func():
		_profiles.erase(player)
		#PlayersService.kick_player(
			#player,
			#"Main data profile session ended. Should not still be in the server."
		#)
	)
	
	# Just in case they did not disconnect
	if player in PlayersService.get_players():
		_profiles[player] = profile
		print("[PlayerDataManager] Profile loaded for %s!" % player.name)
		
		# Usage exmaple
		profile.data["coins"] += 100 # Direct but won't trigger signal
		profile.set_value("coins", profile.get_value("coins", 0) + 100) # Will trigger signal 'value_changed'
	else:
		player_data_store.unload_profile(profile)
		
		
func _on_player_removing(player: Player) -> void:
	if not RunService.is_server():
		return
		
	var profile = _profiles.get(player, null)
	if profile:
		player_data_store.unload_profile(profile)
		
		
func _on_server_shutting_down() -> void:
	if not RunService.is_server():
		return
		
	print("[PlayerDataManager] Server shutting down, flushing all active profiles...")
	
	var active_players = _profiles.keys().duplicate()
	for player in active_players:
		var profile = _profiles.get(player, null)
		if profile:
			player_data_store.unload_profile(profile)
			
	_profiles.clear()
