extends Node3D

func _ready():
	# Additional logic as needed (e.g. data store, etc.)
	if RunService.is_server():
		while true:
			await get_tree().create_timer(1).timeout
			LoggerService.debug(PlayerDataManager._profiles)
			for p: Player in PlayersService.get_players():
				var profile = PlayerDataManager.get_profile(p)
				if not profile: continue
				
				profile.set_value("coins", profile.get_value("coins", 0) + 100)
				LoggerService.debug(p.name)
				LoggerService.debug(profile.data)
		pass
