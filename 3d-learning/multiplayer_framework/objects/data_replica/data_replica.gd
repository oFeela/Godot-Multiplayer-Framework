class_name DataReplica
extends RefCounted

## CONSTANTS
signal data_set(path: Array, new_value: Variant, old_value: Variant)
signal array_inserted(path: Array, value: Variant, index: int)
signal array_removed(path: Array, removed_value: Variant, index: int)
signal destroyed()

## VARIABLES
var name: String
var data: Dictionary
var tags: Dictionary

var is_replicated_globally := false
var subscribed_peer_ids: Array[int] = []

## OVERRIDEN METHODS
func _init(r_name: String, r_data: Dictionary, r_tags: Dictionary = {}) -> void:
	name = r_name
	data = r_data.duplicate(true)
	tags = r_tags.duplicate(true)
	
	
	
## PUBLICS

## Replicate state to ALL connected players and any player joining in the future.
func replicate() -> void:
	if not RunService.is_server(): return
	is_replicated_globally = true
	
	LoggerService.info("[DataReplica] Global replication enabled for '%s'" % name)
	DataReplicaService._server_replicate_all(self)
	
	
## Replicate state privately to a specific player (e.g., inventory, personal stats).
func subscribe(peer_id: int) -> void:
	if not RunService.is_server(): return
	if peer_id not in subscribed_peer_ids:
		subscribed_peer_ids.append(peer_id)
	
	LoggerService.info("[DataReplica] Peer %d subscribed to replica '%s'" % [peer_id, name])
	DataReplicaService._server_replicate_peer(self, peer_id)
		
		
## Remove replication access from a specific player.
func unsubscribe(peer_id: int) -> void:
	if not RunService.is_server(): return
	if peer_id in subscribed_peer_ids:
		subscribed_peer_ids.erase(peer_id)
		
	LoggerService.info("[DataReplica] Peer %d unsubscribed from replica '%s'" % [peer_id, name])
	DataReplicaService._server_unsubscribe_peer(self, peer_id)
		
		
## Destroy this DataReplica across the server and all subscribed remote clients.
func destroy() -> void:
	LoggerService.info("[DataReplica] Destroy requested for replica '%s'" % name)
	
	if RunService.is_server():
		DataReplicaService._server_destroy_replica(self)
	else:
		_destroy_local()
		
		
## Mutate a nested value (e.g., replica.set_data(["Stats", "Health"], 100)).
func set_data(path: Array, value: Variant) -> void:
	var old_val = _get_nested(data, path)
	_set_nested(data, path, value)
	
	LoggerService.info("[DataReplica] ['%s'] set_data: %s = %s (was: %s)" % [name, str(path), str(value), str(old_val)])
	data_set.emit(path, value, old_val)
	
	if RunService.is_server():
		DataReplicaService._send_mutation(self, "set_data", [path, value])
		
		
## Batch set multiple keys: replica.set_dict(["Stats"], {"Health": 100, "Mana": 50}).
func set_dict(path: Array, values_dict: Dictionary) -> void:
	LoggerService.info("[DataReplica] ['%s'] set_dict at %s with %d entries" % [name, str(path), values_dict.size()])
	
	for key in values_dict:
		var key_path = path.duplicate()
		key_path.append(key)
		set_data(key_path, values_dict[key])
		
		
## Append or insert into an array: replica.array_insert(["Inventory"], "GoldSword").
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
	
	if RunService.is_server():
		DataReplicaService._send_mutation(self, "array_insert", [path, value, index])
		
		
## Remove an item from an array by index: replica.array_remove(["Inventory"], 0).
## Returns the removed value
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
