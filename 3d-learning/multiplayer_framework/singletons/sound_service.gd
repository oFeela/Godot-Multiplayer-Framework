extends Node

## VARIABLES
@export var registered_sounds: Dictionary[String, AudioStream] = FrameworkConfig.INITIAL_REGISTERED_SOUNDS.duplicate()

## PUBLICS

## Plays a 2D sound globally on the local client
func play_sound_2d(stream_or_key: Variant, volume_db: float = 0.0) -> void:
	var stream := _resolve_stream(stream_or_key)
	if not stream: return
	
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	
	add_child(player)
	
	player.play()
	player.finished.connect(player.queue_free)
	
	
## Plays a 3D sound at a world position
func play_sound_3d(stream_or_key: Variant, global_pos: Vector3, volume_db: float = 0.0) -> void:
	var stream := _resolve_stream(stream_or_key)
	if not stream: return
	
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.global_position = global_pos
	player.volume_db = volume_db
	
	add_child(player)
	
	player.play()
	player.finished.connect(player.queue_free)
	
	
# Server -> All Clients: Replicates a 3D sound at a world location
func play_sound_3d_replicated(sound_key: String, global_pos: Vector3, volume_db: float = 0.0) -> void:
	if not RunService.is_server():
		LoggerService.warn("[SoundService] play_sound_3d_replicated called on client.")
		return
	s2c_play_sound_3d.rpc(sound_key, global_pos, volume_db)
	
@rpc("authority", "call_local", "reliable")
func s2c_play_sound_3d(sound_key: String, global_pos: Vector3, volume_db: float) -> void:
	play_sound_3d(sound_key, global_pos, volume_db)
	
	
## Server -> All Clients: Replicates a 2D non-spatial sound globally to everyone (round end, emergency alarm)
func play_sound_2d_replicated(sound_key: String, volume_db: float = 0.0) -> void:
	if not RunService.is_server():
		LoggerService.warn("[SoundService] play_sound_2d_replicated called on client.")
		return
	s2c_play_sound_2d.rpc(sound_key, volume_db)
	
@rpc("authority", "call_local", "reliable")
func s2c_play_sound_2d(sound_key: String, volume_db: float) -> void:
	play_sound_2d(sound_key, volume_db)
	
	
## Server -> Target Client: Replicates a 2D sound to a specific player (purchase success, quest complete)
func play_sound_2d_client(target: Variant, sound_key: String, volume_db: float = 0.0) -> void:
	if not RunService.is_server():
		LoggerService.warn("[SoundService] play_sound_2d_client called on client.")
		return
		
	var peer_id: int = -1
	
	if target is Player:
		peer_id = target.peer_id
	elif target is int:
		peer_id = target
	else:
		LoggerService.error("[SoundService] Invalid target for fire_client. Expected Player or int.")
		return
		
	if peer_id <= 0:
		LoggerService.warn("[SoundService] Attempted to fire_client to invalid peer_id: %d" % peer_id)
		return
		
	s2c_play_sound_2d.rpc_id(peer_id, sound_key, volume_db)
	
	
	
## PRIVATES

func _resolve_stream(stream_or_key: Variant) -> AudioStream:
	if stream_or_key is AudioStream:
		return stream_or_key
	elif stream_or_key is String:
		if registered_sounds.has(stream_or_key):
			return registered_sounds[stream_or_key] as AudioStream
		LoggerService.warn("[SoundService] Sound key '%s' not found in registry." % stream_or_key)
	return null
