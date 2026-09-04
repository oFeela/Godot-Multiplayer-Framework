extends Node

## Checks whether the current running peer is the server.
func is_server():
	return multiplayer.is_server() if multiplayer.has_multiplayer_peer() else true
	
	
## Checks whether the current running peer is the client.
func is_client():
	return not is_server()
	
	
## Checks whether running inside the Godot Editor.
func is_editor() -> bool:
	return Engine.is_editor_hint()
	
	
