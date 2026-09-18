## Runtime environment helper service.
##
## [RunService] provides utility methods to inspect execution state, network authority roles,
## and editor context across single-player and multiplayer sessions.
extends Node

## Checks whether the current process execution context has server authority.
## Returns [code]true[/code] if running as a dedicated/listen server, or if running in offline single-player mode.
func is_server() -> bool:
	return multiplayer.is_server() if multiplayer.has_multiplayer_peer() else true

## Checks whether the current process execution context is acting as a remote client.
## [return]: [code]true[/code] if connected to a host server as a client peer; otherwise [code]false[/code].
func is_client() -> bool:
	return not is_server()

## Checks whether the code is currently executing inside the Godot Editor context.
## [return]: [code]true[/code] if running as an editor plugin or tool script within the editor; otherwise [code]false[/code].
func is_editor() -> bool:
	return Engine.is_editor_hint()
