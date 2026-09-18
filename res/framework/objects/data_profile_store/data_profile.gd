## Managed data store wrapper providing nested path mutation, change listeners, and session lock states.
##
## [DataProfile] acts as a state container for persistent save data or network replicas.
## It handles template reconciliation, path-based callbacks ([method listen_to_change]), array manipulation,
## and dirty flag tracking for disk write optimization.
class_name DataProfile
extends RefCounted

## CONSTANTS

## Emitted whenever a property value changes at a specific key path via [method set_data] or [method set_dict].
signal data_set(path: Array, new_value: Variant, old_value: Variant)

## Emitted when an element is inserted into an array at a given key path via [method array_insert].
signal array_inserted(path: Array, value: Variant, index: int)

## Emitted when an element is removed from an array at a given key path via [method array_remove].
signal array_removed(path: Array, removed_value: Variant, index: int)

## Emitted when the profile session lock is released via [method unlock].
signal unlocked()

## VARIABLES

## The name of the storage container or table associated with this profile.
var store_name: String = ""

## Unique identifier key for this profile within its store.
var key: String = ""

## Raw data dictionary holding all key-value state.
var data: Dictionary = {}

## Flags whether the profile is active (session locked). Inactive profiles reject mutation requests.
var is_active := true # active <==> session locked

var _is_dirty := false
var _template := {}
var _path_listeners: Array[Dictionary] = []

## OVERRIDEN METHODS

## Initializes a new profile instance with target store identifiers, base data, and template schema.
## [param p_store_name]: The associated store identifier.
## [param p_key]: Unique save key for this profile.
## [param initial_data]: Initial dictionary loaded from disk or network.
## [param template]: Fallback schema structure used during reconciliation.
func _init(p_store_name: String, p_key: String, initial_data: Dictionary, template: Dictionary) -> void:
	store_name = p_store_name
	key = p_key
	_template = template.duplicate(true)
	data = initial_data.duplicate(true)
	reconcile()

## PUBLICS

## Registers a callback function to execute when a value at or beneath [param path] changes.
## [codeblock]
## profile.listen_to_change(["Stats", "Coins"], _on_coins_changed)
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

## Reconciles existing profile [member data] against the template schema to populate missing keys.
func reconcile() -> void:
	_reconcile_dict(data, _template)

## Sets a root-level property on the profile dictionary.
## [param k]: Root dictionary key name.
## [param value]: New value to assign.
func set_value(k: String, value: Variant) -> void:
	set_data([k], value)

## Mutates a nested value using an explicit key path array.
## [codeblock]
## profile.set_data(["Stats", "Health"], 100)
## [/codeblock]
func set_data(path: Array, value: Variant) -> void:
	if not is_active:
		push_error("[DataProfile] Cannot set data on inactive profile for key: '%s'" % key)
		return
		
	var old_val = _get_nested(data, path)
	_set_nested(data, path, value)
	_is_dirty = true
	
	data_set.emit(path, value, old_val)
	_dispatch_listeners(path, value, old_val)

## Sets multiple nested values relative to a base key path using a dictionary map.
## [codeblock]
## profile.set_dict(["Stats"], {"Health": 100, "Mana": 50})
## [/codeblock]
func set_dict(path: Array, values_dict: Dictionary) -> void:
	for k in values_dict:
		var key_path = path.duplicate()
		key_path.append(k)
		set_data(key_path, values_dict[k])

## Inserts an item into an Array target at the specified [param path].
## [param path]: Key path array leading to an Array instance.
## [param value]: Element to insert.
## [param index]: Target insertion index. Defaults to [code]-1[/code] (append).
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

## Removes an item by index from an Array target at the specified [param path].
## Returns the removed value, or [code]null[/code] if invalid.
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

## Retrieves a top-level key value from the profile data dictionary.
func get_value(k: String, default: Variant = null) -> Variant:
	return data.get(k, default)

## Resets profile state back to an exact duplicate of the schema template.
func reset_to_template() -> void:
	if not is_active:
		return
		
	data = _template.duplicate(true)
	_is_dirty = true

## Clears the internal dirty state flag following a successful save write.
func mark_clean() -> void:
	_is_dirty = false

## Returns [code]true[/code] if data has changed since the last clean mark.
func is_dirty() -> bool:
	return _is_dirty

## Releases the profile session lock and marks it inactive to block further mutations.
func unlock() -> void:
	if not is_active:
		return
		
	is_active = false
	unlocked.emit()

## PRIVATES

## Recursively fills missing dictionary keys from the target template.
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
