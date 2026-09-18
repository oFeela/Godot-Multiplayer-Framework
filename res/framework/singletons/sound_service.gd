## Audio playback and network sound replication manager.
##
## [SoundService] manages spatial (3D) and non-spatial (2D) audio playback.
## It supports playing local audio streams directly or looking up sound streams by string keys,
## as well as replicating audio triggers across connected peers from the server.
extends Node

## VARIABLES

## Dictionary mapping string audio keys (e.g., [code]"explosion"[/code], [code]"coin_pickup"[/code]) to [AudioStream] resources.
@export var registered_sounds: Dictionary[String, AudioStream] = FrameworkConfig.INITIAL_REGISTERED_SOUNDS.duplicate()

## PUBLICS

## Plays a 2D global (non-spatial) sound locally on the client.
## [param stream_or_key]: An [AudioStream] resource or a registered [String] lookup key.
## [param volume_db]: Volume adjustment in decibels (default: [code]0.0[/code]).
func play_sound_2d(stream_or_key: Variant, volume_db: float = 0.0) -> void:
	var stream := _resolve_stream(stream_or_key)
	if not stream: return
	
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	
	add_child(player)
	
	player.play()
	player.finished.connect(player.queue_free)

## Plays a 3D spatial sound at a specific world position locally.
## [param stream_or_key]: An [AudioStream] resource or a registered [String] lookup key.
## [param global_pos]: Spatial world coordinates ([Vector3]) where the sound originates.
## [param volume_db]: Volume adjustment in decibels (default: [code]0.0[/code]).
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

## Server -> All Clients: Replicates a 3D spatial sound at a world position across all connected peers.
## [param sound_key]: Registered [String] identifier of the sound stream.
## [param global_pos]: Spatial world coordinates ([Vector3]) where the sound originates.
## [param volume_db]: Volume adjustment in decibels (default: [code]0.0[/code]).
func play_sound_3d_replicated(sound_key: String, global_pos: Vector3, volume_db: float = 0.0) -> void:
	if not RunService.is_server():
		LoggerService.warn("[SoundService] play_sound_3d_replicated called on client.")
		return
	s2c_play_sound_3d.rpc(sound_key, global_pos, volume_db)

## RPC handler executing a 3D spatial sound trigger on connected peers.
@rpc("authority", "call_local", "reliable")
func s2c_play_sound_3d(sound_key: String, global_pos: Vector3, volume_db: float) -> void:
	play_sound_3d(sound_key, global_pos, volume_db)

## Server -> All Clients: Replicates a 2D global sound to all connected peers (e.g., game alarms, UI triggers).
## [param sound_key]: Registered [String] identifier of the sound stream.
## [param volume_db]: Volume adjustment in decibels (default: [code]0.0[/code]).
func play_sound_2d_replicated(sound_key: String, volume_db: float = 0.0) -> void:
	if not RunService.is_server():
		LoggerService.warn("[SoundService] play_sound_2d_replicated called on client.")
		return
	s2c_play_sound_2d.rpc(sound_key, volume_db)

## RPC handler executing a 2D non-spatial sound trigger on connected peers.
@rpc("authority", "call_local", "reliable")
func s2c_play_sound_2d(sound_key: String, volume_db: float) -> void:
	play_sound_2d(sound_key, volume_db)

## Server -> Target Client: Replicates a 2D sound exclusively to a specific player session.
## [param target]: Target recipient ([Player] instance or peer ID [int]).
## [param sound_key]: Registered [String] identifier of the sound stream.
## [param volume_db]: Volume adjustment in decibels (default: [code]0.0[/code]).
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

## Resolves an [AudioStream] from either a raw resource or a string lookup key in [member registered_sounds].
func _resolve_stream(stream_or_key: Variant) -> AudioStream:
	if stream_or_key is AudioStream:
		return stream_or_key
	elif stream_or_key is String:
		if registered_sounds.has(stream_or_key):
			return registered_sounds[stream_or_key] as AudioStream
		LoggerService.warn("[SoundService] Sound key '%s' not found in registry." % stream_or_key)
	return null
