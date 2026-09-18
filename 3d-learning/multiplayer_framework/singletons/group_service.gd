extends Node

## CONSTANTS
signal node_added(group_name: String, node: Node)
signal node_removed(group_name: String, node: Node)

## VARIABLES
var _node_groups: Dictionary = {} # Dictionary[Node, Array[String]]

## PUBLICS

## Adds a node to a group and tracks its scene lifecycle
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
		
		
## Removes a group from a node
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
		
		
## Returns true if the node currently is in the given group
func in_group(node: Node, group_name: String) -> bool:
	if not is_instance_valid(node): return false
	return node.is_in_group(group_name)
	
	
## Returns all active nodes currently in group_name
func get_group_nodes(group_name: String) -> Array[Node]:
	return get_tree().get_nodes_in_group(group_name)
	
	
	
## PRIVATES

func _on_node_tree_exited(node: Node):
	if not _node_groups.has(node):
		return
		
	var groups: Array[String] = (_node_groups[node] as Array[String]).duplicate()
	_node_groups.erase(node)
	
	# Emit removal signals for all registered groups
	for group in groups:
		node_removed.emit(group, node)
