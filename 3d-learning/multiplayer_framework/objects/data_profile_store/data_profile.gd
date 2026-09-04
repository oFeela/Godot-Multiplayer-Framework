class_name DataProfile
extends RefCounted

## CONSTANTS
signal value_changed(key: String, new_value: Variant)
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
	
	
## Set profile value authoritatively
func set_value(k: String, value: Variant) -> void:
	if not is_active:
		push_error("[Profile] Cannot set value on inactive profile for key: '%s'" % key)
		return
		
	if data.get(k) != value:
		data[k] = value
		_is_dirty = true
		value_changed.emit(k, value)
		
		
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
