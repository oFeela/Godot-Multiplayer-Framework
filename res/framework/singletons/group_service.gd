## Reactive node grouping and lifecycle tracking service.
##
## [GroupService] wraps Godot's built-in scene tree group mechanism to provide
## reactive signals ([signal node_added], [signal node_removed]) and automatic cleanup
## when nodes exit the scene tree.
extends Node

## CONSTANTS

## Emitted when a [Node] is successfully registered to a group tag.
## [param group_name]: The string name of the group.
## [param node]: The [Node] instance added to the group.
signal node_added(group_name: String, node: Node)

## Emitted when a [Node] is removed from a group tag or exits the scene tree.
## [param group_name]: The string name of the group.
## [param node]: The [Node] instance removed from the group.
signal node_removed(group_name: String, node: Node)

## VARIABLES

## Internal tracking registry storing group lists per active node instance.
var _node_groups: Dictionary = {} # Dictionary[Node, Array[String]]

## PUBLICS

## Adds a node to a group tag and hooks up automatic lifecycle cleanup on tree exit.
## [param node]: The target [Node] instance to tag.
## [param group_name]: The string identifier of the group tag.
func add_group(node: Node, group_name: String) -> void:
	if not is_instance_valid(node):
		LoggerService.warn("[GroupService] Cannot add an invalid node to group '%s'." % group_name)
		return
		
	if not node.is_in_group(group_name):
		node.add_to_group(group_name)
		
	if not _node_groups.has(node):
		_node_groups[node] = []
		# Auto cleanup
		node.tree_exited.connect(func(): _on_node_tree_exited(node), CONNECT_ONE_SHOT)
		
	var groups: Array[String] = _node_groups[node] as Array[String]
	if not groups.has(group_name):
		groups.append(group_name)
		node_added.emit(group_name, node)

## Removes a group tag from a node and cleans up internal tracking if no tags remain.
## [param node]: The target [Node] instance.
## [param group_name]: The string identifier of the group tag to strip.
func remove_group(node: Node, group_name: String) -> void:
	if not is_instance_valid(node):
		LoggerService.warn("[GroupService] Cannot remove an invalid node from group '%s'." % group_name)
		return
		
	if node.is_in_group(group_name):
		node.remove_from_group(group_name)
		
	if not _node_groups.has(node):
		return
		
	var groups: Array[String] = _node_groups[node] as Array[String]
	if groups.has(group_name):
		groups.erase(group_name)
		node_removed.emit(group_name, node)
		
	# Clean up tracker if no tags remain
	if groups.is_empty():
		_node_groups.erase(node)

## Checks if a valid node instance belongs to a specific group tag.
## [param node]: The target [Node] instance.
## [param group_name]: The group tag to verify.
## [return]: [code]true[/code] if valid and in the group, otherwise [code]false[/code].
func in_group(node: Node, group_name: String) -> bool:
	if not is_instance_valid(node): return false
	return node.is_in_group(group_name)

## Retrieves an array of all active scene tree nodes assigned to a specific group.
## [param group_name]: The group tag to query.
## [return]: Array of active [Node] instances currently in the group.
func get_group_nodes(group_name: String) -> Array[Node]:
	return get_tree().get_nodes_in_group(group_name)

## PRIVATES

## Internal callback triggered when a tracked node exits the scene tree to clean up references and emit signals.
func _on_node_tree_exited(node: Node):
	if not _node_groups.has(node):
		return
		
	var groups: Array[String] = (_node_groups[node] as Array[String]).duplicate()
	_node_groups.erase(node)
	
	# Emit removal signals for all registered groups
	for group in groups:
		node_removed.emit(group, node)
