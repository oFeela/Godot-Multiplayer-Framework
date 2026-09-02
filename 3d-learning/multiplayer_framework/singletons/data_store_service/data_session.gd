class_name DataSession
extends RefCounted

## CONSTANTS
signal unlocked

## VARIABLES
var owner_peer_id: int
var data: Dictionary = {}
var is_active := false
var _store: DataStore

## OVERRIDEN METHODS
func _init(s_peer_id: int, s_data: Dictionary, s_store: DataStore) -> void:
	owner_peer_id = s_peer_id
	data = s_data
	_store = s_store
	is_active = true
	
	
	
## PUBLICS

## Fills in any missing default key/values if game data structure updates
func reconcile(template: Dictionary):
	_reconcile_dict(data, template)
	
	
## Ends session lock and triggers save
func end_session() -> void:
	if not is_active:
		return
		
	is_active = false
	_store._end_data_session(self)
	unlocked.emit()
	
	
	
## PRIVATES

## Reconciles the target dictionary to the template
func _reconcile_dict(target: Dictionary, template: Dictionary) -> void:
	for k in template.keys():
		if not target.has(k):
			target[k] = template[k].duplicate(true) if template[k] is Dictionary or template[k] is Array else template[k]
		elif target[k] is Dictionary and template[k] is Dictionary:
			_reconcile_dict(target[k], template[k])
