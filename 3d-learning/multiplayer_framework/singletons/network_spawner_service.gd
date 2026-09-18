extends Node

## VARIABLES
## Map scene keys (e.g., "coin", "fireball") to scene files
@export var registered_scenes: Dictionary[String, PackedScene] = FrameworkConfig.INITIAL_REGISTERED_SCENES.duplicate()

var _multiplayer_spawner: MultiplayerSpawner
var _spawn_container: Node

## OVERRIDEN METHODS
func _ready() -> void:
	# Internal MultiplayerSpawner instance to handle replication of ANYTHING 
	# that is spawned via this service
	_multiplayer_spawner = MultiplayerSpawner.new()
	_multiplayer_spawner.name = "GlobalMultiplayerSpawner"
	add_child(_multiplayer_spawner)
	
	# In case spawn_container has been set before it was ran
	if _spawn_container and is_instance_valid(_spawn_container):
		_multiplayer_spawner.spawn_path = _spawn_container.get_path()
	
	for scene in registered_scenes.values():
		_register_scene_to_spawner(scene)
	
	
## PUBLICS

## Sets the spawn container where replicated entities will be parented to
## Call this from MultiplayerWorld._ready()
func set_spawn_container(container: Node) -> void:
	_spawn_container = container
	if _multiplayer_spawner and is_instance_valid(_spawn_container):
		_multiplayer_spawner.spawn_path = _spawn_container.get_path()
		
		
## Registers a new scene at runtime
func register_scene(scene_key: String, scene: PackedScene) -> void:
	registered_scenes[scene_key] = scene
	_register_scene_to_spawner(scene)
	
	
## Creates an entity in memory on the server. DOES NOT replicate to clients yet.
func instantiate_entity(scene_key: String, transform_data: Variant = null) -> Node:
	if not RunService.is_server():
		LoggerService.warn("[NetworkSpawnerService] Clients cannot instantiate networked entities.")
		return null
		
	if not registered_scenes.has(scene_key):
		LoggerService.warn("[NetworkSpawnerService] Unregistered scene key: '%s'" % scene_key)
		return null
		
	var scene := registered_scenes[scene_key]
	var instance := scene.instantiate()
	
	if transform_data != null:
		_apply_transform(instance, transform_data)
		
	return instance
	
	
## Parents an instantiated entity into the parent node, triggering replication across all clients.
## custom_parent NEEDS to be a node that is the _spawn_container OR any descendants of it
func replicate_entity(instance: Node, custom_parent: Node = null) -> void:
	if not RunService.is_server() or not instance:
		return
		
	var target_parent := custom_parent if custom_parent else _spawn_container
	
	if not target_parent or not is_instance_valid(target_parent):
		LoggerService.warn("[NetworkSpawnerService] Cannot replicate entity. Target parent container is invalid.")
		return
		
	# Safety check: Ensure custom_parent is inside or is the spawn_container
	if target_parent != _spawn_container and not _spawn_container.is_ancestor_of(target_parent):
		LoggerService.warn("[NetworkSpawnerService] Custom parent must be a descendant of the global spawn container!")
		return
		
	target_parent.add_child(instance, true)
	
	
## ONE-LINE SHORTCUT: Instantiates, applies transform, and replicates immediately.
func spawn(scene_key: String, transform_data: Variant = null, custom_parent: Node = null) -> Node:
	var instance := instantiate_entity(scene_key, transform_data)
	if instance:
		replicate_entity(instance, custom_parent)
	return instance
	
	
	
## PRIVATES

## Register a scene to the MultiplayerSpawner
func _register_scene_to_spawner(scene: PackedScene) -> void:
	if scene and _multiplayer_spawner:
		var path = scene.resource_path
		
		if not _has_spawnable_scene(scene):
			_multiplayer_spawner.add_spawnable_scene(path)
		
		
## Checks if the MultiplayerSpawner has the given scene
func _has_spawnable_scene(scene: PackedScene) -> bool:
	if not scene or not _multiplayer_spawner:
		return false
		
	var path = scene.resource_path
	
	for i in range(_multiplayer_spawner.get_spawnable_scene_count()):
		if _multiplayer_spawner.get_spawnable_scene(i) == path:
			return true
			
	return false
	
	
func _apply_transform(instance: Node, transform_data: Variant) -> void:
	if instance is Node3D and transform_data is Transform3D:
		instance.global_transform = transform_data
	elif instance is Node2D and transform_data is Transform2D:
		instance.global_transform = transform_data
	elif "global_position" in instance:
		instance.global_position = transform_data
