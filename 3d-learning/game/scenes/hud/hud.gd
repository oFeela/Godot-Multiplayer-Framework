extends CanvasLayer

@onready var coins_label: Label = $VBoxContainer/Coins

func _ready() -> void:
	var replica := await DataReplicaManager.get_replica(
		PlayerDataManager.DATA_REPLICA_NAME_PREFIX + str(PlayerIdentity.player_id)
	)
	replica.listen_to_change(["coins"], func(val, _old):
		coins_label.text = "Coins: %d" % val
	)
	coins_label.text = "Coins: %d" % replica.data.get("coins", 0)
	
