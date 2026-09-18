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
		
	# Repeat until data_replica_ready is emitted + found the target replica
	var start_time := Time.get_ticks_msec()
	timeout = int(timeout * 1000)
	
	while not _replicas.has(replica_name):
		if timeout > 0 and (Time.get_ticks_msec() - start_time) >= timeout:
			LoggerService.warn("[DataReplicaManager] Timed out waiting for replica '%s'" % replica_name)
			return null
		
		await get_tree().process_frame
			
	# Return NULL
	return _replicas.get(replica_name, null)
	
