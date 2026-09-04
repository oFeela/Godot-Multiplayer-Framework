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

## OVERRIDEN METHODS
func _init(p_store_name: String, p_key: String, initial_data: Dictionary, template: Dictionary) -> void:
	store_name = p_store_name
	key = p_key
	_template = template.duplicate(true)
	data = initial_data.duplicate(true)
	reconcile()
	
	
	
## PUBLICS

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
