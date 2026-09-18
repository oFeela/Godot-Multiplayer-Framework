## Network-replicated dictionary data structure supporting path mutations, subscription filtering, and real-time state synchronization.
##
## [DataReplica] acts as a high-level state container managed by [DataReplicaService].
## It supports global or targeted peer subscriptions ([method replicate], [method subscribe]),
## path-based change listeners ([method listen_to_change]), and array manipulation with automatic RPC propagation.
class_name DataReplica
extends RefCounted

## CONSTANTS

## Emitted whenever a property value changes at a specific key path via [method set_data] or [method set_dict].
signal data_set(path: Array, new_value: Variant, old_value: Variant)

## Emitted when an element is inserted into an array at a given key path via [method array_insert].
signal array_inserted(path: Array, value: Variant, index: int)

## Emitted when an element is removed from an array at a given key path via [method array_remove].
signal array_removed(path: Array, removed_value: Variant, index: int)

## Emitted when this replica is destroyed locally or via server command.
signal destroyed()

## VARIABLES

## Unique name identifier for this replica instance across the network.
var name: String

## Raw data dictionary holding replicated state properties.
var data: Dictionary

## Metadata dictionary associated with this replica for filtering or identification.
var tags: Dictionary

## Flags whether this replica is automatically replicated to all connected and future clients.
var is_replicated_globally := false

## List of specific peer IDs subscribed to receive network updates for this replica.
var subscribed_peer_ids: Array[int] = []

var _path_listeners: Array[Dictionary] = []

## OVERRIDEN METHODS

## Initializes a new replica instance with a target name, initial data dictionary, and optional tags.
## [param r_name]: Unique name identifier.
## [param r_data]: Initial dictionary payload.
## [param r_tags]: Key-value metadata tags.
func _init(r_name: String, r_data: Dictionary, r_tags: Dictionary = {}) -> void:
	name = r_name
	data = r_data.duplicate(true)
	tags = r_tags.duplicate(true)

## PUBLICS

## Registers a callback function to execute when a value at or beneath [param path] changes.
## [codeblock]
## replica.listen_to_change(["Coins"], _on_coins_changed)
## [/codeblock]
func listen_to_change(path: Array, callback: Callable) -> void:
	_path_listeners.append({
		"path": path,
		"callable": callback
	})

## Unregisters a previously attached path listener callback.
func unlisten_change(path: Array, callback: Callable) -> void:
	for i in range(_path_listeners.size() - 1, -1, -1):
		var binding = _path_listeners[i]
		if binding["path"] == path and binding["callable"] == callback:
			_path_listeners.remove_at(i)

## Server-Only: Enables global replication, sending state to all currently connected and future joining peers.
func replicate() -> void:
	if not RunService.is_server(): return
	is_replicated_globally = true
	
	LoggerService.info("[DataReplica] Global replication enabled for '%s'" % name)
	DataReplicaService._server_replicate_all(self)

## Server-Only: Subscribes a specific peer ID to receive updates and initial state for this replica.
## [param peer_id]: The target network peer ID.
func subscribe(peer_id: int) -> void:
	if not RunService.is_server(): return
	if peer_id not in subscribed_peer_ids:
		subscribed_peer_ids.append(peer_id)
	
	LoggerService.info("[DataReplica] Peer %d subscribed to replica '%s'" % [peer_id, name])
	DataReplicaService._server_replicate_peer(self, peer_id)

## Server-Only: Unsubscribes a specific peer ID, stopping network updates and destroying client-side replica.
## [param peer_id]: The target network peer ID.
func unsubscribe(peer_id: int) -> void:
	if not RunService.is_server(): return
	if peer_id in subscribed_peer_ids:
		subscribed_peer_ids.erase(peer_id)
		
	LoggerService.info("[DataReplica] Peer %d unsubscribed from replica '%s'" % [peer_id, name])
	DataReplicaService._server_unsubscribe_peer(self, peer_id)

## Destroys this replica instance across the server and all subscribed remote clients.
func destroy() -> void:
	LoggerService.info("[DataReplica] Destroy requested for replica '%s'" % name)
	
	if RunService.is_server():
		DataReplicaService._server_destroy_replica(self)
	else:
		_destroy_local()

## Mutates a nested value using an explicit key path array and broadcasts change if server.
## [codeblock]
## replica.set_data(["Stats", "Health"], 100)
## [/codeblock]
func set_data(path: Array, value: Variant) -> void:
	var old_val = _get_nested(data, path)
	_set_nested(data, path, value)
	
	LoggerService.info("[DataReplica] ['%s'] set_data: %s = %s (was: %s)" % [name, str(path), str(value), str(old_val)])
	
	data_set.emit(path, value, old_val)
	_dispatch_listeners(path, value, old_val)
	
	if RunService.is_server():
		DataReplicaService._send_mutation(self, "set_data", [path, value])

## Sets multiple nested values relative to a base key path using a dictionary map.
## [codeblock]
## replica.set_dict(["Stats"], {"Health": 100, "Mana": 50})
## [/codeblock]
func set_dict(path: Array, values_dict: Dictionary) -> void:
	LoggerService.info("[DataReplica] ['%s'] set_dict at %s with %d entries" % [name, str(path), values_dict.size()])
	
	for key in values_dict:
		var key_path = path.duplicate()
		key_path.append(key)
		set_data(key_path, values_dict[key])

## Inserts an item into an Array target at the specified [param path] and replicates mutation.
## [param path]: Key path array leading to an Array instance.
## [param value]: Element to insert.
## [param index]: Target insertion index. Defaults to [code]-1[/code] (append).
func array_insert(path: Array, value: Variant, index: int = -1) -> void:
	var arr: Array = _get_nested(data, path)
	if arr == null or not arr is Array: return
	
	# Bounds check
	if index < -(arr.size() + 1): index = 0
	if index < 0: index += (arr.size() + 1)
	if index > arr.size(): index = arr.size()
		
	arr.insert(index, value)
	
	LoggerService.info("[DataReplica] ['%s'] array_insert: inserted %s into %s at index %d" % [name, str(value), str(path), index])
	
	array_inserted.emit(path, value, index)
	_dispatch_listeners(path, arr, index)
	
	if RunService.is_server():
		DataReplicaService._send_mutation(self, "array_insert", [path, value, index])

## Removes an item by index from an Array target at the specified [param path] and replicates mutation.
## Returns the removed value, or [code]null[/code] if invalid.
func array_remove(path: Array, index: int) -> Variant:
	var arr: Array = _get_nested(data, path)
	if arr == null or not arr is Array:
		LoggerService.warn("[DataReplica] ['%s'] array_remove failed: path %s is not an Array" % [name, str(path)])
		return null
	if index < 0 or index >= arr.size():
		LoggerService.warn("[DataReplica] ['%s'] array_remove failed: index %d out of bounds for path %s" % [name, index, str(path)])
		return null
	
	var removed_val = arr[index]
	arr.remove_at(index)
	
	LoggerService.info("[DataReplica] ['%s'] array_remove: removed %s from %s at index %d" % [name, str(removed_val), str(path), index])
	
	array_removed.emit(path, removed_val, index)
	_dispatch_listeners(path, arr, index)
	
	if RunService.is_server():
		DataReplicaService._send_mutation(self, "array_remove", [path, index])
		
	return removed_val

## PRIVATES

func _destroy_local() -> void:
	LoggerService.info("[DataReplica] Destroyed local replica '%s'" % name)
	destroyed.emit()

# Get a value from the specified path IF IT IS A VALID PATH.
func _get_nested(dict: Dictionary, path: Array) -> Variant:
	var curr = dict
	
	for k in path:
		if curr is Dictionary and curr.has(k):
			curr = curr[k]
		else:
			return null
			
	return curr

# Sets a value to the specified path. Will create new dictionary keys if needed.
func _set_nested(dict: Dictionary, path: Array, value: Variant) -> void:
	var curr = dict
	
	for i in range(path.size() - 1):
		var k = path[i]
		if not curr.has(k) or not (curr[k] is Dictionary):
			curr[k] = {}
		curr = curr[k]
		
	curr[path[-1]] = value

func _dispatch_listeners(changed_path: Array, new_value: Variant, secondary_arg: Variant) -> void:
	for binding in _path_listeners:
		var listener_path: Array = binding["path"]
		
		# Match exact path or parent container path
		if listener_path == changed_path or _is_subpath(changed_path, listener_path):
			var cb: Callable = binding["callable"]
			if cb.is_valid():
				# If watching a parent path, evaluate the value at the listener's exact path
				var target_value = new_value if listener_path == changed_path else _get_nested(data, listener_path)
				cb.call(target_value, secondary_arg)

func _is_subpath(full_path: Array, parent_path: Array) -> bool:
	if parent_path.size() > full_path.size(): return false
	for i in range(parent_path.size()):
		if parent_path[i] != full_path[i]:
			return false
	return true
