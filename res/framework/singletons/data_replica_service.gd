## Server-authoritative reactive state management and replication service.
##
## [DataReplicaService] handles the creation, state mutation, selective peer subscription,
## and destruction of [DataReplica] instances across network connections.
extends Node

## CONSTANTS

## Emitted on both server and client whenever a new [DataReplica] is created locally or replicated over the network.
## [param replica]: The newly created [DataReplica] instance.
signal replica_created(replica: DataReplica)

## VARIABLES

## Registry storing active [DataReplica] instances indexed by their unique name.
var _active_replicas: Dictionary[String, DataReplica] = {}

## OVERRIDEN METHODS

func _ready() -> void:
	if RunService.is_client():
		# Request a replica from server INSTANTLY for client
		multiplayer.connected_to_server.connect(_request_replicas)

## PUBLICS

## Creates a [DataReplica] on the host/server.
## [param r_name]: Unique identifier name for the replica.
## [param initial_data]: Dictionary containing the base state tree.
## [param tags]: Metadata tags attached to the replica.
## [return]: The created [DataReplica] instance, or [code]null[/code] if called on a non-server instance.
func create_replica(r_name: String, initial_data: Dictionary, tags: Dictionary = {}) -> DataReplica:
	if not RunService.is_server():
		LoggerService.warn("[DataReplicaService] Replicas can only be created on the server!")
		return null
	
	var replica = DataReplica.new(r_name, initial_data, tags)
	_active_replicas[r_name] = replica
	
	LoggerService.info("[DataReplicaService] Created replica '%s' on host/server" % r_name)
	replica_created.emit(replica)
	
	return replica

## RPC receiver for initializing a replicated [DataReplica] on remote clients.
@rpc("authority", "call_remote", "reliable")
func _rpc_create_replica(r_name: String, data: Dictionary, tags: Dictionary) -> void:
	LoggerService.info("[DataReplicaService] Received RPC: Creating replica '%s' on client" % r_name)
	
	var replica = DataReplica.new(r_name, data, tags)
	_active_replicas[r_name] = replica
	replica_created.emit(replica)

## Fetches an active [DataReplica] by its unique string name.
## [param r_name]: The unique name of the replica to retrieve.
## [return]: The [DataReplica] instance if found, otherwise [code]null[/code].
func get_replica(r_name: String) -> DataReplica:
	return _active_replicas.get(r_name, null)

## PRIVATES

## Issues an RPC to the server to request all globally replicated or subscribed replicas upon connection.
func _request_replicas() -> void:
	_rpc_request_replicas.rpc_id(1)

## Server RPC handler processing client sync requests.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_replicas() -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	
	# Skip host
	if sender_id == 1 or sender_id == multiplayer.get_unique_id():
		return
		
	LoggerService.info("[DataReplicaService] Peer %d requested full replica sync" % sender_id)
		
	# Send back GLOBAL or SUBSCRIBED replicas
	for replica: DataReplica in _active_replicas.values():
		if replica.is_replicated_globally or sender_id in replica.subscribed_peer_ids:
			_rpc_create_replica.rpc_id(sender_id, replica.name, replica.data, replica.tags)

## Replicates a given [DataReplica] to all currently connected peer clients.
func _server_replicate_all(replica: DataReplica) -> void:
	if not RunService.is_server(): return
	for peer_id in multiplayer.get_peers():
		_server_replicate_peer(replica, peer_id)

## Replicates a given [DataReplica] directly to a specific target peer.
func _server_replicate_peer(replica: DataReplica, peer_id: int) -> void:
	if not RunService.is_server(): return
	if peer_id == 1 or peer_id == multiplayer.get_unique_id():
		return
		
	LoggerService.info("[DataReplicaService] Replicating '%s' directly to peer %d" % [replica.name, peer_id])
	_rpc_create_replica.rpc_id(peer_id, replica.name, replica.data, replica.tags)

## Unsubscribes a specific peer from a [DataReplica], destroying the instance on their local client.
func _server_unsubscribe_peer(replica: DataReplica, peer_id: int) -> void:
	if not RunService.is_server(): return
	if peer_id == 1 or peer_id == multiplayer.get_unique_id():
		return
		
	LoggerService.info("[DataReplicaService] Unsubscribing peer %d from replica '%s'" % [peer_id, replica.name])
	_rpc_destroy_replica.rpc_id(peer_id, replica.name)

## Server-authoritative removal and network destruction of a [DataReplica].
func _server_destroy_replica(replica: DataReplica) -> void:
	if not RunService.is_server(): return
	
	LoggerService.info("[DataReplicaService] Destroying replica '%s' across network" % replica.name)
	
	if replica.is_replicated_globally:
		for peer_id in multiplayer.get_peers():
			_rpc_destroy_replica.rpc_id(peer_id, replica.name)
	else:
		for peer_id in replica.subscribed_peer_ids:
			if peer_id != 1 and peer_id != multiplayer.get_unique_id():
				_rpc_destroy_replica.rpc_id(peer_id, replica.name)
				
	# Destroy on server
	replica._destroy_local()
	_active_replicas.erase(replica.name)

## Client RPC handler for destroying a local [DataReplica] copy upon server instruction.
@rpc("authority", "call_remote", "reliable")
func _rpc_destroy_replica(r_name: String) -> void:
	LoggerService.info("[DataReplicaService] Received RPC: Destroying replica '%s'" % r_name)
	
	var replica: DataReplica = _active_replicas.get(r_name, null)
	if replica:
		replica._destroy_local()
		_active_replicas.erase(r_name)

## Routes state mutation events executed on the server down to target clients.
func _send_mutation(replica: DataReplica, mutator_type: String, args: Array) -> void:
	if not RunService.is_server(): return
	
	# Mutations take effect in-memory on Host automatically.
	# Send to STRICTLY relevant connected remote peers.
	if replica.is_replicated_globally:
		LoggerService.info("[DataReplicaService] Broadasting mutation '%s' for '%s' globally" % [mutator_type, replica.name])
		
		for peer in multiplayer.get_peers():
			_rpc_mutate_replica.rpc_id(peer, replica.name, mutator_type, args)
	else:
		LoggerService.info("[DataReplicaService] Sending mutation '%s' for '%s' to subscribed peers: %s" % [mutator_type, replica.name, str(replica.subscribed_peer_ids)])
		
		for peer in replica.subscribed_peer_ids:
			if peer != 1 and peer != multiplayer.get_unique_id():
				_rpc_mutate_replica.rpc_id(peer, replica.name, mutator_type, args)

## Client RPC handler for executing received state mutations on a local [DataReplica].
@rpc("authority", "call_remote", "reliable")
func _rpc_mutate_replica(r_name: String, mutator_type: String, args: Array) -> void:
	var replica: DataReplica = _active_replicas.get(r_name, null)
	if not replica: return
	
	LoggerService.info("[DataReplicaService] Executing remote mutation '%s' on replica '%s'" % [mutator_type, r_name])
	
	match mutator_type:
		"set_data":
			replica.set_data(args[0], args[1])
		"array_insert":
			replica.array_insert(args[0], args[1], args[2])
		"array_remove":
			replica.array_remove(args[0], args[1])
