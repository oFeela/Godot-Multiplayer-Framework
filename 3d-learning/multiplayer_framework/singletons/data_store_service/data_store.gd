class_name DataStore
extends RefCounted

## CONSTANTS
enum DriverMode {
	P2P_CLIENT_TRANSFER,
	CENTRALIZED_SERVER,
}

const SAVE_PATH := "user://local_player_save.dat"
const HMAC_SECRET := "67Miguel67_MakeSureToChangeThisToSomethingElseInProduction"

## VARIABLES
var store_name: String
var template: Dictionary
var driver_mode := DriverMode.P2P_CLIENT_TRANSFER
var _active_sessions: Dictionary[int, DataSession] = {}
var _pending_p2p: Dictionary[int, Dictionary]

## OVERRIDEN METHODS
func _init(ds_name: String, ds_template: Dictionary, mode: DriverMode = DriverMode.P2P_CLIENT_TRANSFER) -> void:
	store_name = ds_name
	template = ds_template
	driver_mode = mode
	
	
	
## PUBLICS

## Starts a session lock on key
func start_data_session(owner_peer_id: int) -> DataSession:
	if not RunService.is_server():
		push_warning("[DataStore] Sessions can ONLY be loaded on the server!")
		return
		
	if has_data_session(owner_peer_id):
		push_warning("[DataStore] Session '%s' is already active!" % owner_peer_id)
		return _active_sessions[owner_peer_id]
		
	var loaded_data = {}
	
	match driver_mode:
		DriverMode.CENTRALIZED_SERVER:
			loaded_data = _load_centralized(owner_peer_id)
		DriverMode.P2P_CLIENT_TRANSFER:
			if _pending_p2p.has(owner_peer_id):
				loaded_data = _pending_p2p[owner_peer_id]
				_pending_p2p.erase(owner_peer_id)
				
	var session = DataSession.new(owner_peer_id, loaded_data, self)
	session.reconcile(template)
	_active_sessions[owner_peer_id] = session
	
	return session
		
		
func has_data_session(owner_peer_id: int) -> bool:
	return _active_sessions.has(owner_peer_id)
	
	
func get_data_session(owner_peer_id: int) -> bool:
	
