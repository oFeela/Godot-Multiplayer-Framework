extends Node

## This is the script to customize for what data needs to be saved.
## It uses the DataProfielStore and DataProfile abstraction.
## THIS IS SERVER ONLY. ONLY SERVER WILL CREATE PROFILES. 
## CLIENTS WILL HAVE TO REQUEST FOR THEM MANUALLY IN SOME WAY (DONE WITH DataReplica)

## CONSTANTS
const PLAYER_DATA_STORE_NAME := "PlayerData_1"
const DATA_REPLICA_NAME_PREFIX := "PlayerData_"
const DATA_STORE_MODE := DataProfileStore.StoreMode.P2P
const PLAYER_TEMPLATE := {
	"coins": 100,
	"gems": 10,
	"level": 1,
	"xp": 0.0,
	"ascension": 0,
}

## VARIABLES
var player_data_store: DataProfileStore
var _profiles: Dictionary[Player, DataProfile] = {}
var _replicas: Dictionary[Player, DataReplica] = {}

## OVERRIDEN METHODS
func _ready() -> void:
	player_data_store = DataProfileStore.new(
		PLAYER_DATA_STORE_NAME,
		PLAYER_TEMPLATE,
		DATA_STORE_MODE
	)
	add_child(player_data_store)
	
	# Player signals
	PlayersService.player_added.connect(_on_player_added)
	PlayersService.player_removing.connect(_on_player_removing)
	
	# Shutdown signal
	PlayersService.server_shutting_down.connect(_on_server_shutting_down)
	
	
	
## PUBLICS

## Returns the profile for a player instance.
func get_profile(player: Player) -> DataProfile:
	return _profiles.get(player, null)
	
	
## Returns the replica for a player instance.
func get_replica(player: Player) -> DataReplica:
	return _replicas.get(player, null)
	
	
	
## PRIVATES
func _on_player_added(player: Player):
	if not RunService.is_server():
		return
		
	# Load the profile using the validated account player_id as the key
	var peer_id = player.peer_id
	var player_id = PlayersService.get_player_id_from_peer_id(peer_id)
	var profile = await player_data_store.load_profile(peer_id, player_id)
	
	if profile:
		_on_profile_ready(player, profile)
	else:
		LoggerService.warn("[Server] Failed to load data profile for player_id: %s (peer: %d)" % [player_id, peer_id])
		PlayersService.kick_player(player, "Data failed to load. Please rejoin!")
		
		
func _on_profile_ready(player: Player, profile: DataProfile) -> void:
	profile.unlocked.connect(func():
		_cleanup_player_session(player),
		CONNECT_ONE_SHOT
	)
	
	# Just in case they did not disconnect
	if player in PlayersService.get_players():
		_profiles[player] = profile
		LoggerService.info("[PlayerDataManager] Profile loaded for %s!" % player.name)
		
		var peer_id = player.peer_id
		var player_id = PlayersService.get_player_id_from_peer_id(peer_id)
		
		var replica_name := DATA_REPLICA_NAME_PREFIX + str(player_id)
		var replica := DataReplicaService.create_replica(
			replica_name,
			profile.data
		)
		_replicas[player] = replica
		
		replica.subscribe(peer_id)
		
		# Direct 1:1 signal-to-method forwarding
		profile.data_set.connect(func(path: Array, new_val: Variant, _old_val: Variant):
			replica.set_data(path, new_val)
		)
		profile.array_inserted.connect(func(path: Array, value: Variant, index: int):
			replica.array_insert(path, value, index)
		)
		profile.array_removed.connect(func(path: Array, _removed_value: Variant, index: int):
			replica.array_remove(path, index)
		)
		
		# Usage exmaple
		profile.data["coins"] += 100 # Direct but won't trigger signal/flag, TLDR: NEVER USE THIS
		profile.set_value("coins", profile.get_value("coins", 0) + 100) # Will trigger signal 'value_changed'
	else:
		player_data_store.unload_profile(profile)
		
		
func _on_player_removing(player: Player) -> void:
	if not RunService.is_server():
		return
	_cleanup_player_session(player)
		
		
func _on_server_shutting_down() -> void:
	if not RunService.is_server():
		return
		
	LoggerService.info("[PlayerDataManager] Server shutting down, flushing all active profiles...")
	var active_players = _profiles.keys().duplicate()
	for player in active_players:
		_cleanup_player_session(player)
		
		
func _cleanup_player_session(player: Player) -> void:
	# Destroy Replica first to inform client before unloading saved profile
	var replica: DataReplica = _replicas.get(player, null)
	if replica:
		replica.destroy()
		_replicas.erase(player)
		
	var profile: DataProfile = _profiles.get(player, null)
	if profile:
		player_data_store.unload_profile(profile)
		_profiles.erase(player)
