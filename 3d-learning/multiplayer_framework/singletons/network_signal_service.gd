extends Node

## CONSTANTS

## Emitted when a client fires an event to the server/host
signal server_event_received(event_name: String, player: Player, args: Array)

## Emitted when the server fires an event to a specific client
signal client_event_received(event_name: String, args: Array)

## VARIABLES
# Internal storage for invoke_server callbacks on the server
var _server_invoke_callables: Dictionary[String, Callable] = {}

# For client
var _pending_invokes: Dictionary = {} # Structure: { invoke_id: { "completed": bool, "result": Variant } }
var _next_invoke_id: int = 1

## PUBLICS

## Client -> Server: Sends an event to the host/server.
func fire_server(event_name: String, args: Array = []) -> void:
	# If a client is the host, it immediately fires to itself
	_c2s_event.rpc_id(1, event_name, args)
	
@rpc("any_peer", "call_local", "reliable")
func _c2s_event(event_name: String, args: Array) -> void:
	if not RunService.is_server(): return
	
	var sender_id := multiplayer.get_remote_sender_id()
	var player := PlayersService.get_player_from_peer_id(sender_id)
	if not player:
		LoggerService.warn("[NetworkSignalService] Event received from unknown peer_id: %d" % sender_id)
		return
		
	server_event_received.emit(event_name, player, args)
	
	
## Server -> Client: Sends an event to a target player (accepts Player object OR int peer_id).
func fire_client(target: Variant, event_name: String, args: Array = []) -> void:
	if not RunService.is_server():
		LoggerService.error("[NetworkSignalService] fire_client can only be called by the server.")
		return
		
	var peer_id: int = -1
	
	if target is Player:
		peer_id = target.peer_id
	elif target is int:
		peer_id = target
	else:
		LoggerService.error("[NetworkSignalService] Invalid target for fire_client. Expected Player or int.")
		return
		
	if peer_id <= 0:
		LoggerService.warn("[NetworkSignalService] Attempted to fire_client to invalid peer_id: %d" % peer_id)
		return
		
	_s2c_event.rpc_id(peer_id, event_name, args)
	
	
## Server -> All Clients: Broadcasts an event to all connected peers.
func fire_all_clients(event_name: String, args: Array = []) -> void:
	if not RunService.is_server():
		LoggerService.error("[NetworkSignalService] fire_all_clients can only be called by the server.")
		return
		
	_s2c_event.rpc(event_name, args)
	
@rpc("authority", "call_local", "reliable")
func _s2c_event(event_name: String, args: Array) -> void:
	client_event_received.emit(event_name, args)
	
	
## Registers a callback on the server to handle invoke_server requests.
## Signature of callback: func(player: Player, args: Array) -> Variant
func bind_server_invoke_callable(function_name: String, callable: Callable) -> void:
	if not RunService.is_server():
		LoggerService.warning("[NetworkSignalService] Invoke callables should be bound on the server/host.")
	_server_invoke_callables[function_name] = callable
	
## Client -> Server: Invokes a function on the server and awaits its return value.
## Times out automatically if the host fails to respond.
func invoke_server(function_name: String, args: Array = [], timeout: float = 5.0) -> Variant:
	var invoke_id = _next_invoke_id
	_next_invoke_id += 1
	
	_pending_invokes[invoke_id] = {
		"completed": false,
		"result": null
	}
	
	# Send invocation to server
	_c2s_invoke_request.rpc_id(1, invoke_id, function_name, args)
	
	# Timeout
	var start_time = Time.get_ticks_msec()
	timeout = int(timeout * 1000)
		
	while not _pending_invokes[invoke_id]["completed"]:
		if timeout > 0 and (Time.get_ticks_msec() - start_time) >= timeout:
			LoggerService.warn("[NetworkSignalService] invoke_server('%s') timed out!" % function_name)
			_pending_invokes.erase(invoke_id)
			return null
		
		await get_tree().process_frame
		
	var res = _pending_invokes[invoke_id]["result"]
	_pending_invokes.erase(invoke_id)
	
	return res
	
@rpc("any_peer", "call_local", "reliable")
func _c2s_invoke_request(invoke_id: int, function_name: String, args: Array) -> void:
	if not RunService.is_server(): return
	
	var sender_id := multiplayer.get_remote_sender_id()
	var player: Player = PlayersService.get_player_from_peer_id(sender_id)
	var return_val: Variant = null
	
	if player and _server_invoke_callables.has(function_name):
		var callable: Callable = _server_invoke_callables[function_name]
		if callable.is_valid():
			return_val = callable.call(player, args)
	else:
		LoggerService.warn("[NetworkSignalService] No invoke callable registered for '%s'" % function_name + ". Please register one or it will do nothing!")
		
	# Update client _pending_invokes
	_s2c_invoke_response.rpc_id(sender_id, invoke_id, return_val)
	
@rpc("authority", "call_local", "reliable")
func _s2c_invoke_response(invoke_id: int, result: Variant) -> void:
	if _pending_invokes.has(invoke_id):
		_pending_invokes[invoke_id]["result"] = result
		_pending_invokes[invoke_id]["completed"] = true
