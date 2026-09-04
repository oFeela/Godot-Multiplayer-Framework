extends CanvasLayer

## UI REFERENCES
@onready var coins_label: Label = $VBoxContainer/Coins

## VARIABLES
var _player_replica: DataReplica

func _ready() -> void:
	# 1. Listen for new replicas arriving from the server
	DataReplicaService.replica_created.connect(_on_replica_created)
	
	# 2. If the replica already arrived before this UI ready(), fetch it manually
	var my_player_id := PlayerIdentity.player_id
	var replica_name := "PlayerData_" + str(my_player_id)
	var existing_replica := DataReplicaService.get_replica(replica_name)
	
	if existing_replica:
		_bind_replica(existing_replica)


func _on_replica_created(replica: DataReplica) -> void:
	var my_player_id := PlayerIdentity.player_id
	var target_replica_name := "PlayerData_" + str(my_player_id)
	
	# Only bind if this replica belongs to the local player
	if replica.name == target_replica_name:
		_bind_replica(replica)


func _bind_replica(replica: DataReplica) -> void:
	_player_replica = replica
	
	# Connect replica mutation signals to UI handlers
	_player_replica.data_set.connect(_on_data_set)
	_player_replica.destroyed.connect(_on_replica_destroyed)
	
	# Initialize UI elements with starting values from the replica's initial data
	_update_full_ui()


func _update_full_ui() -> void:
	if not _player_replica: return
	
	coins_label.text = "Coins: %d" % _player_replica.data.get("coins", 0)


func _on_data_set(path: Array, new_value: Variant, _old_value: Variant) -> void:
	# Filter updates by path
	match path:
		["coins"]:
			coins_label.text = "Coins: %d" % new_value
			# Optional: Play coin animation or sound effect here


func _on_replica_destroyed() -> void:
	_player_replica = null
	# Reset UI or hide menu
