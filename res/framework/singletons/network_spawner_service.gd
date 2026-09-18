## Networked entity creation and replication manager.
##
## [NetworkSpawnerService] utilizes an internal [MultiplayerSpawner] to register,
## instantiate, and replicate scene nodes across connected peers on the network.
extends Node

## VARIABLES

## Dictionary mapping string scene keys (e.g., [code]"coin"[/code], [code]"fireball"[/code]) to [PackedScene] resources.
@export var registered_scenes: Dictionary[String, PackedScene] = FrameworkConfig.INITIAL_REGISTERED_SCENES.duplicate()

## Internal [MultiplayerSpawner] instance handling replication across peers.
var _multiplayer_spawner: MultiplayerSpawner

## Target parent node under which replicated entities will be added.
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

## Sets the spawn container where replicated entities will be parented.
## Intended to be called during scene setup (e.g., inside [method MultiplayerWorld._ready]).
## [param container]: The root [Node] where spawned entities will reside.
func set_spawn_container(container: Node) -> void:
	_spawn_container = container
	if _multiplayer_spawner and is_instance_valid(_spawn_container):
		_multiplayer_spawner.spawn_path = _spawn_container.get_path()

## Registers a new scene resource dynamically at runtime.
## [param scene_key]: Unique string lookup key for the scene.
## [param scene]: The [PackedScene] resource to register.
func register_scene(scene_key: String, scene: PackedScene) -> void:
	registered_scenes[scene_key] = scene
	_register_scene_to_spawner(scene)

## Instantiates an entity in memory on the server without replicating it immediately to clients.
## [param scene_key]: Registered string identifier of the target scene.
## [param transform_data]: Optional spatial transform ([Transform3D], [Transform2D], or [Vector2]/[Vector3]).
## [return]: The newly instantiated [Node], or [code]null[/code] if instantiation fails or call is made on a client.
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

## Parents an instantiated entity into the scene tree, triggering automatic network replication across all clients.
## [param instance]: The instantiated entity node to replicate.
## [param custom_parent]: Target parent node. Must be equal to or a descendant of the configured spawn container.
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

## Convenience function: Instantiates, applies initial spatial transform data, and replicates an entity in a single call.
## [param scene_key]: Registered string identifier of the target scene.
## [param transform_data]: Optional spatial transform ([Transform3D], [Transform2D], or [Vector2]/[Vector3]).
## [param custom_parent]: Target parent node. Must be equal to or a descendant of the configured spawn container.
## [return]: The spawned and replicated [Node] instance, or [code]null[/code] on failure.
func spawn(scene_key: String, transform_data: Variant = null, custom_parent: Node = null) -> Node:
	var instance := instantiate_entity(scene_key, transform_data)
	if instance:
		replicate_entity(instance, custom_parent)
	return instance

## PRIVATES

## Registers a [PackedScene] resource into the internal [MultiplayerSpawner].
func _register_scene_to_spawner(scene: PackedScene) -> void:
	if scene and _multiplayer_spawner:
		var path = scene.resource_path
		
		if not _has_spawnable_scene(scene):
			_multiplayer_spawner.add_spawnable_scene(path)

## Checks if the given [PackedScene] is already registered within the internal [MultiplayerSpawner].
func _has_spawnable_scene(scene: PackedScene) -> bool:
	if not scene or not _multiplayer_spawner:
		return false
		
	var path = scene.resource_path
	
	for i in range(_multiplayer_spawner.get_spawnable_scene_count()):
		if _multiplayer_spawner.get_spawnable_scene(i) == path:
			return true
			
	return false

## Applies transform or position data onto a freshly instantiated entity instance.
func _apply_transform(instance: Node, transform_data: Variant) -> void:
	if instance is Node3D and transform_data is Transform3D:
		instance.global_transform = transform_data
	elif instance is Node2D and transform_data is Transform2D:
		instance.global_transform = transform_data
	elif "global_position" in instance:
		instance.global_position = transform_data
