extends CanvasLayer

@onready var coins_label: Label = $VBoxContainer/Coins
@onready var give_button: Button = $VBoxContainer/Give
@onready var buy_button: Button = $VBoxContainer/Buy

func _ready() -> void:
	var replica := await DataReplicaManager.get_replica(
		PlayerDataManager.DATA_REPLICA_NAME_PREFIX + str(PlayerIdentity.player_id)
	)
	replica.listen_to_change(["coins"], func(val, _old):
		coins_label.text = "Coins: %d" % val
	)
	coins_label.text = "Coins: %d" % replica.data.get("coins", 0)
	
	give_button.pressed.connect(func():
		NetworkSignalService.fire_server("give_coins")
	)
	buy_button.pressed.connect(func():
		var result = await NetworkSignalService.invoke_server("request_buy")
		if result:
			print("SUCCESSFUL BUY!")
		else:
			print("INSUFFICIENT FUND!")
	)
