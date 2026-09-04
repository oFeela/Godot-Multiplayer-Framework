class_name DataProfile
extends RefCounted

## CONSTANTS
signal data_set(path: Array, new_value: Variant, old_value: Variant)
signal array_inserted(path: Array, value: Variant, index: int)
signal array_removed(path: Array, removed_value: Variant, index: int)
signal unlocked()

## VARIABLES
var store_name: String = ""
var key: String = ""
var data: Dictionary = {}
var is_active := true # active <==> session locked
var _is_dirty := false
var _template := {}
var _path_listeners: Array[Dictionary] = []

## OVERRIDEN METHODS
func _init(p_store_name: String, p_key: String, initial_data: Dictionary, template: Dictionary) -> void:
	store_name = p_store_name
	key = p_key
	_template = template.duplicate(true)
	data = initial_data.duplicate(true)
	reconcile()
	
	
	
## PUBLICS

## Listen specifically to changes at a given path.
## Example: profile.listen_to_change(["coins"], _on_coins_changed)
func listen_to_change(path: Array, callback: Callable) -> void:
	_path_listeners.append({
		"path": path,
		"callable": callback
	})
	
	
## Stop listening to changes at a specific path for a callback.
func unlisten_change(path: Array, callback: Callable) -> void:
	for i in range(_path_listeners.size() - 1, -1, -1):
		var binding = _path_listeners[i]
		if binding["path"] == path and binding["callable"] == callback:
			_path_listeners.remove_at(i)
			
			
## Ensures new key additions in template default automatically populate existing save profiles
func reconcile() -> void:
	_reconcile_dict(data, _template)
	
	
## Set profile value on a given direct key
func set_value(k: String, value: Variant) -> void:
	set_data([k], value)
		
		
## Mutate a nested value (e.g., replica.set_data(["Stats", "Health"], 100)).
func set_data(path: Array, value: Variant) -> void:
	if not is_active:
		push_error("[DataProfile] Cannot set data on inactive profile for key: '%s'" % key)
		return
		
	var old_val = _get_nested(data, path)
	_set_nested(data, path, value)
	_is_dirty = true
	
	data_set.emit(path, value, old_val)
	_dispatch_listeners(path, value, old_val)
		
		
## Batch set multiple keys: replica.set_dict(["Stats"], {"Health": 100, "Mana": 50}).
func set_dict(path: Array, values_dict: Dictionary) -> void:
	for k in values_dict:
		var key_path = path.duplicate()
		key_path.append(k)
		set_data(key_path, values_dict[k])
		
		
## Append or insert into an array: replica.array_insert(["Inventory"], "GoldSword").
func array_insert(path: Array, value: Variant, index: int = -1) -> void:
	if not is_active:
		push_error("[DataProfile] Cannot insert to array on inactive profile for key: '%s'" % key)
		return
		
	var arr: Array = _get_nested(data, path)
	if arr == null or not arr is Array: return
	
	# Bounds check
	if index < -(arr.size() + 1): index = 0
	if index < 0: index += (arr.size() + 1)
	if index > arr.size(): index = arr.size()
		
	arr.insert(index, value)
	_is_dirty = true
	
	array_inserted.emit(path, value, index)
	_dispatch_listeners(path, arr, index)
	
	
## Remove an item from an array by index: replica.array_remove(["Inventory"], 0).
## Returns the removed value
func array_remove(path: Array, index: int) -> Variant:
	if not is_active:
		push_error("[DataProfile] Cannot remove from array on inactive profile for key: '%s'" % key)
		return
		
	var arr: Array = _get_nested(data, path)
	if arr == null or not arr is Array: return
	if index < 0 or index >= arr.size(): return
	
	var removed_val = arr[index]
	arr.remove_at(index)
	_is_dirty = true
	
	array_removed.emit(path, removed_val, index)
	_dispatch_listeners(path, arr, index)
	
	return removed_val
		
		
## Get profile value
func get_value(k: String, default: Variant = null) -> Variant:
	return data.get(k, default)
	
	
## Reset profile to default template state
func reset_to_template() -> void:
	if not is_active:
		return
		
	data = _template.duplicate(true)
	_is_dirty = true
	
	
func mark_clean() -> void:
	_is_dirty = false
	
	
func is_dirty() -> bool:
	return _is_dirty
	
	
func unlock() -> void:
	if not is_active:
		return
		
	is_active = false
	unlocked.emit()
	
	
	
## PRIVATES

## Reconciles the target dictionary to the template
func _reconcile_dict(target: Dictionary, tmpl: Dictionary) -> void:
	for k in tmpl.keys():
		if not target.has(k):
			if typeof(tmpl[k]) == TYPE_DICTIONARY or typeof(tmpl[k]) == TYPE_ARRAY:
				target[k] = tmpl[k].duplicate(true)
			else:
				target[k] = tmpl[k]
		elif typeof(target[k]) == TYPE_DICTIONARY and typeof(tmpl[k]) == TYPE_DICTIONARY:
			_reconcile_dict(target[k], tmpl[k])
			
			
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
