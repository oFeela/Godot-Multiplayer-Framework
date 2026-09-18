extends CharacterBody3D

func _enter_tree() -> void:
	set_multiplayer_authority(int(name))

# For testing purposes
func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority(): return
	#print(multiplayer.is_server())
	global_position = global_position + Vector3(0, 0.01, 0)
