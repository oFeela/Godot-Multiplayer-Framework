extends CanvasLayer

## UI REFERENCES
@onready var coins_label: Label = $VBoxContainer/Coins

## VARIABLES
var _player_replica: DataReplica

func _ready() -> void:
	DataReplicaService.replica_created.connect(_on_replica_created)
	
	var target_name := "PlayerData_" + str(PlayerIdentity.player_id)
	var existing_replica := DataReplicaService.get_replica(target_name)
	if existing_replica:
		_bind_replica(existing_replica)
		
		
func _on_replica_created(replica: DataReplica) -> void:
	if replica.name == "PlayerData_" + str(PlayerIdentity.player_id):
		_bind_replica(replica)
		
		
func _bind_replica(replica: DataReplica) -> void:
	_player_replica = replica
	
	# Listen directly to coins changes
	replica.listen_to_change(["coins"], _update_coins)
	
	# Clean up reference on destroy
	replica.destroyed.connect(func(): _player_replica = null)
	
	# Set initial UI state
	_update_coins(replica.data.get("coins", 0), null)
	
	
func _update_coins(new_coins: Variant, _old_coins: Variant) -> void:
	coins_label.text = "Coins: %d" % new_coins
