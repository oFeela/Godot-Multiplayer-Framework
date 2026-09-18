## Persistent local player identity resolver and editor multi-instance coordinator.
##
## [PlayerIdentity] resolves a unique, persistent [member player_id] for the local runtime instance.
## - For production builds and primary editor instances, it resolves to the local user's Steam ID.
## - For extra debug editor instances (Instances 2+), it assigns dedicated port-bound slots
##   and generates persistent device UUID v4 keys to prevent identity and save data collision.
extends Node

## VARIABLES

## When set to [code]true[/code], each secondary debug editor instance slot (1, 2, 3...) maintains
## its generated UUID identity and save file permanently across editor restarts.
@export var use_static_instance_slots: bool = true

## Resolved unique persistent identity string for the current player/instance (e.g., [code]"steam_12345678"[/code] or [code]"device_uuid..."[/code]).
var player_id: String = ""

## Internal active slot index evaluated for debug editor instances. Defaults to primary slot [code]1[/code].
var _instance_slot: int = 1

## OVERRIDDEN METHODS

func _ready() -> void:
	player_id = _resolve_player_id()
	LoggerService.info("[PlayerIdentity] Registered Player ID: " + player_id)

## PRIVATES

## Detects whether the current process is a secondary/extra editor instance by attempting to bind to sequential local TCP ports.
## [return]: [code]true[/code] if running as secondary editor instance (Slot > 1); otherwise [code]false[/code].
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

## Resolves the final player identity string based on execution environment and Steam availability.
## [return]: Identity string formatted with either Steam prefix or Device UUID fallback.
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

## Resolves or generates a persistent device UUID stored on disk.
## [return]: A persistent RFC 4122 compliant UUID v4 string.
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

## Calculates the file path used to persist local device IDs based on build type and editor slot settings.
## [return]: Target file path string in [code]user://[/code].
func _get_save_path() -> String:
	# In release builds, use a clean static path
	if not OS.has_feature("editor"):
		return "user://player_id.txt"

	# Static Slot mode: Instance 1 -> player_id_slot_1.txt, Instance 2 -> player_id_slot_2.txt
	if use_static_instance_slots:
		return "user://player_id_slot_%d.txt" % _instance_slot

	# Dynamic Process ID mode: player_id_10412.txt
	return "user://player_id_%d.txt" % OS.get_process_id()

## Saves a generated device ID string to the given file path.
func _save_device_id(path: String, id: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(id)

## Generates a cryptographically random RFC 4122 compliant UUID v4 string.
## [return]: Formatted UUID string prefixed with [code]"device_"[/code].
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
