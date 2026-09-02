extends Node

## Provides a static, unique player_id.
## - Uses Steam ID for exported builds & primary editor instance.
## - Falls back to isolated local UUIDs with STATIC slots for debug instances.

## VARIABLES
## Set to true if you want each editor instance slot (1, 2, 3...) 
## to keep its save data/ID permanently across editor restarts.
@export var use_static_instance_slots: bool = true

var player_id: String = ""
var _instance_slot: int = 1


## OVERRIDDEN METHODS
func _ready() -> void:
	player_id = _resolve_player_id()
	print("[PlayerIdentity] Active Player ID: ", player_id)


## PRIVATES
func _is_extra_editor_instance() -> bool:
	# Try binding to sequential TCP ports (29173, 29174, 29175...)
	# Instance 1 gets Slot 1 (Port 29173). Instance 2 gets Slot 2 (Port 29174), etc.
	for slot in range(1, 10):
		var server := TCPServer.new()
		var port := 29172 + slot
		var err := server.listen(port, "127.0.0.1")
		
		if err == OK:
			_instance_slot = slot
			# Keep reference open so the port stays locked while this instance runs
			set_meta("_primary_instance_server", server)
			break

	# Slot 1 is Primary; Slots 2+ are Extra Editor Instances
	return _instance_slot > 1


func _resolve_player_id() -> String:
	# Force local fallback on extra editor instances (Instance #2, #3, etc.)
	# so they don't collide with Instance #1's Steam ID on the same PC.
	if OS.has_feature("editor") and _is_extra_editor_instance():
		return _resolve_device_id()

	# Primary Instance or Exported Build: Use Steam ID if available
	if Steam.isSteamRunning():
		return "steam_" + str(Steam.getSteamID())

	# Offline / Non-Steam Fallback
	return _resolve_device_id()


func _resolve_device_id() -> String:
	var path := _get_save_path()

	# Load existing ID from plain text file
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file:
			var saved_id := file.get_as_text().strip_edges()
			if not saved_id.is_empty():
				return saved_id

	# Generate new UUID v4 if file doesn't exist
	var new_id := _generate_uuid_v4()
	_save_device_id(path, new_id)
	return new_id


func _get_save_path() -> String:
	# In release builds, use a clean static path
	if not OS.has_feature("editor"):
		return "user://player_id.txt"

	# Static Slot mode: Instance 1 -> player_id_slot_1.txt, Instance 2 -> player_id_slot_2.txt
	if use_static_instance_slots:
		return "user://player_id_slot_%d.txt" % _instance_slot

	# Dynamic Process ID mode: player_id_10412.txt
	return "user://player_id_%d.txt" % OS.get_process_id()


func _save_device_id(path: String, id: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(id)


func _generate_uuid_v4() -> String:
	var crypto := Crypto.new()
	var bytes := crypto.generate_random_bytes(16)

	# RFC 4122 compliance bits for UUID v4
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80

	var hex := bytes.hex_encode()
	return "device_%s-%s-%s-%s-%s" % [
		hex.substr(0, 8),
		hex.substr(8, 4),
		hex.substr(12, 4),
		hex.substr(16, 4),
		hex.substr(20, 12)
	]
