class_name DataProfileStore
extends Node

## CONSTANTS
signal profile_loaded(profile: DataProfile)
signal profile_unloaded(profile: DataProfile)
signal client_payload_received(key: String)

enum StoreMode {
	P2P,
	CENTRALIZED
}

# HMAC secret key used for signing local P2P save payloads
const HMAC_SECRET_KEY: String = "67Miguel67_Change_In_Production_Ok"

## VARIABLES
@export var store_mode: StoreMode = StoreMode.P2P
@export var store_name: String = "PlayerData"

var template: Dictionary = {}

var _loaded_profiles: Dictionary[String, DataProfile] = {}
var _key_to_peer_id: Dictionary[String, int] = {}
var _auto_save_timer: Timer

## OVERRIDEN METHODS
func _init(p_store_name: String = "PlayerData", p_template: Dictionary = {}, p_mode: StoreMode = StoreMode.P2P) -> void:
	store_name = p_store_name
	template = p_template
	store_mode = p_mode
	
	
func _ready() -> void:
	_auto_save_timer = Timer.new()
	_auto_save_timer.wait_time = 60.0
	_auto_save_timer.autostart = true
	_auto_save_timer.timeout.connect(save_all)
	add_child(_auto_save_timer)
	
	
	
## PUBLICS

## Loads a profile with the corresponding key and peer_id as the owner of the profile.
## The peer_id is used for rpc calls for synchronization in case of P2P.
func load_profile(peer_id: int, key: String) -> DataProfile:
	if not RunService.is_server():
		push_warning("[DataProfileStore] Only server/host can call load_profile()")
		return null
		
	if _loaded_profiles.has(key):
		return _loaded_profiles[key]
		
	_key_to_peer_id[key] = peer_id
	
	if store_mode == StoreMode.CENTRALIZED:
		var db_data = _read_from_central_db(key)
		return _register_profile_session(key, db_data)
	else:
		if peer_id == 1 or peer_id == multiplayer.get_unique_id():
			# If host, just read directly from local disk since it has authority
			var host_data = _read_local_disk(key)
			return _register_profile_session(key, host_data)
		else:
			# If client, then request client for their data
			_rpc_request_client_payload.rpc_id(peer_id, key)
			return null
			
# 'call_remote' because server won't need to call this. Already loaded automatically.
@rpc("authority", "call_remote", "reliable")
func _rpc_request_client_payload(key: String) -> void:
	var client_package = _read_local_disk_package(key)
	_rpc_client_submit_payload.rpc_id(1, key, client_package)
	
@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_submit_payload(key: String, client_package: Dictionary) -> void:
	if not RunService.is_server():
		return
		
	var sender_peer_id = multiplayer.get_remote_sender_id()
	
	# Disallow if the sender peer does not own the corresponding key's profile
	if _key_to_peer_id.get(key, -1) != sender_peer_id:
		push_warning("[DataProfileStore] Security violation: Peer %d submitted payload for key '%s'" % [sender_peer_id, key])
		return
		
	var verified_data: Dictionary = {}
	
	# Check for HMAC signature requirements
	if client_package.has("data") and client_package.has("signature"):
		# Hash verification
		var payload_data = client_package["data"]
		var signature = client_package["signature"]
		
		if _verify_hmac_signature(payload_data, signature):
			verified_data = payload_data
			print("[DataProfileStore] HMAC Check Passed for peer %d (Key: '%s')" % [sender_peer_id, key])
		else:
			push_warning("[DataProfileStore] HMAC CHECK FAILED! Peer %d sent tampered save payload! Resetting to template." % sender_peer_id)
			verified_data = template.duplicate(true)
	else:
		verified_data = client_package.get("data", template.duplicate(true))
		
	_register_profile_session(key, verified_data)
	client_payload_received.emit(key)
	
	
## Sets a data profile key to the given value
func set_profile_value(profile: DataProfile, data_key: String, value: Variant) -> void:
	if not RunService.is_server():
		push_warning("[DataProfileStore] Non-authoritative attempt to mutate profile values!")
		return
		
	if _loaded_profiles.get(profile.key, null) != profile:
		return
		
	profile.set_value(data_key, value)
	
	
## Saves the given profile if it's dirty
func save_profile(profile: DataProfile) -> void:
	if not RunService.is_server():
		return
		
	if _loaded_profiles.get(profile.key, null) != profile:
		return
		
	if not profile.is_dirty():
		return
		
	if store_mode == StoreMode.CENTRALIZED:
		_write_to_central_db(profile.key, profile.data)
		profile.mark_clean()
	else:
		var target_peer_id = _key_to_peer_id.get(profile.key, 1)
		if target_peer_id == 1 or target_peer_id == multiplayer.get_unique_id():
			print("SERVER")
			_write_local_disk(profile.key, profile.data)
			profile.mark_clean()
		else:
			print("CLIENT")
			_rpc_save_client_profile_to_disk.rpc_id(target_peer_id, profile.key, profile.data)
			profile.mark_clean()
			
@rpc("authority", "call_remote", "reliable")
func _rpc_save_client_profile_to_disk(key: String, validated_data: Dictionary) -> void:
	print("[DataProfileStore] Writing Host-validated profile state to client disk.")
	_write_local_disk(key, validated_data)
	
	
## Unloads the given profile. Will unlock it from session lock.
## Saves it accordingly.
func unload_profile(profile: DataProfile) -> void:
	if not RunService.is_server():
		return
		
	if _loaded_profiles.get(profile.key, null) != profile:
		return
		
	save_profile(profile)
	profile.unlock()
	
	_loaded_profiles.erase(profile.key)
	_key_to_peer_id.erase(profile.key)
	
	print("[DataProfileStore:%s] Session released for profile with key: '%s'" % [store_name, profile.key])
	profile_unloaded.emit(profile)
	
	
## Saves all loaded profiles
func save_all() -> void:
	for profile in _loaded_profiles.values():
		save_profile(profile)
		
		
## Get the profile with the given key
func get_profile(key: String) -> DataProfile:
	return _loaded_profiles.get(key, null)
	
	
	
## PRIVATES

## Registers a profile to be in session. Triggers session lock for the profile.
func _register_profile_session(key: String, raw_data: Dictionary) -> DataProfile:
	var profile = DataProfile.new(store_name, key, raw_data, template)
	_loaded_profiles[key] = profile
	
	print("[DataProfileStore:%s] Session locked/activated for key: '%s'" % [store_name, key])
	
	profile_loaded.emit(profile)
	return profile
	
	
func _generate_hmac(content: String) -> String:
	var crypto = Crypto.new()
	var payload_with_context = store_name + ":" + content # Context-binds signature to store
	var key_bytes = HMAC_SECRET_KEY.to_utf8_buffer()
	var content_bytes = payload_with_context.to_utf8_buffer()
	var hmac = crypto.hmac_digest(HashingContext.HASH_SHA256, key_bytes, content_bytes)
	return hmac.hex_encode()
	
	
func _verify_hmac_signature(data_dict: Dictionary, signature: String) -> bool:	
	var data_json_string = JSON.stringify(data_dict, "\t")
	var expected_hash = _generate_hmac(data_json_string)
	
	return expected_hash == signature
	
	
func _get_local_file_path(key: String) -> String:
	return "user://stores/" + store_name + "/" + key.validate_filename() + ".json"
	
	
func _read_local_disk_package(key: String) -> Dictionary:
	var path = _get_local_file_path(key)

	if not FileAccess.file_exists(path):
		return {"data": template.duplicate(true), "signature": _generate_hmac(JSON.stringify(template, "\t"))}
		
	var file = FileAccess.open(path, FileAccess.READ)
	
	# Failed to load just pass an incorrect signature,
	# so that server will check that it is invalid.
	if not file:
		return {"data": template.duplicate(true), "signature": ""}
	
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {"data": template.duplicate(true), "signature": ""} # Same as above if failed
		
	var clean_data = json.data["data"].duplicate(true)
	_cast_dict_types(clean_data, template)
	json.data["data"] = clean_data
	
	return json.data
	
	
func _read_local_disk(key: String) -> Dictionary:
	var package = _read_local_disk_package(key)

	if package.has("data") and package.has("signature"):
		if _verify_hmac_signature(package["data"], package["signature"]):
			return package["data"]
		else:
			push_warning("[DataProfileStore] Local save signature invalid. Tampered data detected. Falling back to template.")
			return template.duplicate(true)
			
	return package.get("data", template.duplicate(true))
	
	
func _cast_dict_types(data: Dictionary, template_ref: Dictionary) -> void:
	for k in template_ref.keys():
		if not data.has(k):
			continue
		var expected_type = typeof(template_ref[k])
		if expected_type == TYPE_INT and typeof(data[k]) == TYPE_FLOAT:
			data[k] = int(data[k])
		elif expected_type == TYPE_DICTIONARY and typeof(data[k]) == TYPE_DICTIONARY:
			_cast_dict_types(data[k], template_ref[k])
	
	
func _write_local_disk(key: String, data: Dictionary) -> bool:
	var path = _get_local_file_path(key)
	var dir_path = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
		
	var clean_data = data.duplicate(true)
	_cast_dict_types(clean_data, template)
		
	var data_json_string = JSON.stringify(clean_data, "\t")
	var signature = _generate_hmac(data_json_string)
	
	var package = {
		"data": clean_data,
		"signature": signature
	}
	
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return false
		
	file.store_string(JSON.stringify(package, "\t"))
	file.close()
	return true
	
func _read_from_central_db(key: String) -> Dictionary:
	# TODO: HOOK TO CENTRAL DB IF NEEDED FOR CENTRAL DB GAME
	return template.duplicate(true)
	
	
func _write_to_central_db(key: String, data: Dictionary) -> void:
	# TODO: HOOK TO CENTRAL DB IF NEEDED FOR CENTRAL DB GAME
	pass
