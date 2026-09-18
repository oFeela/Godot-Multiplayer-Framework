extends Node3D

func _ready():
	# Additional logic as needed (e.g. data store, etc.)
	if RunService.is_server():
		NetworkSignalService.server_event_received.connect(func(event_name: String, player: Player, _args: Array):
			if event_name == "give_coins":
				var profile := PlayerDataManager.get_profile(player)
				profile.set_value("coins", profile.	get_value("coins", 0) + 1000)
		)
		
		NetworkSignalService.bind_server_invoke_callable("request_buy", func(player: Player, _args: Array):
			var profile := PlayerDataManager.get_profile(player)
			if profile.get_value("coins", 0) >= 400000:
				profile.set_value("coins", profile.get_value("coins", 0) - 400000)
				return true
			return false
		)
		
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
