extends Node

## CONSTANTS
signal data_replica_ready(replica: DataReplica)

## VARIABLES
var _replicas: Dictionary[String, DataReplica] = {}

func _ready() -> void:
	DataReplicaService.replica_created.connect(_on_replica_created)
	
func _on_replica_created(replica: DataReplica) -> void:
	_replicas[replica.name] = replica
	replica.destroyed.connect(func():
		_replicas.erase(replica.name)
	)
	
	data_replica_ready.emit(replica)
	
	
	
## PUBLICS

## Asynchronously get the replica with the given name within 'timeout' seconds.
## Set 'timeout' to 0.0 for indefinite waiting.
func get_replica(replica_name: String, timeout: float = 5.0) -> DataReplica:
	# Immediate return
	if _replicas.has(replica_name):
		return _replicas[replica_name]
		
	# Create timer if definite timeout
	var timer: SceneTreeTimer = null
	if timeout > 0.0:
		timer = get_tree().create_timer(timeout)
		
	# Repeat until data_replica_ready is emitted + found the target replica
	while not _replicas.has(replica_name):
		if timer and timer.time_left <= 0.0:
			LoggerService.warn("[ReplicaManager] Timed out waiting for replica '%s'" % replica_name)
			return null
		
		var replica: DataReplica = await data_replica_ready
		if replica.name == replica_name:
			return replica
			
	# Return NULL
	return _replicas.get(replica_name, null)
	
