# SPDX-License-Identifier: GPL-3.0-or-later
class_name DeleteEntitiesCommand
extends BoardCommand

var entity_ids: PackedInt64Array = PackedInt64Array()
var snapshots: Array[BoardEntitySnapshot] = []
var _captured: bool = false


func _init(new_entity_ids: PackedInt64Array) -> void:
	label = NotLightL10n.text("runtime.core.delete_entities_command.6e1e0a8e5e")
	entity_ids = new_entity_ids.duplicate()


func execute(runtime: BoardRuntime) -> bool:
	if runtime == null or entity_ids.is_empty():
		return false
	if not _captured and not _capture(runtime):
		return false
	var removal_order: PackedInt64Array = _connector_first_ids(runtime, entity_ids)
	runtime.begin_change_batch()
	for entity_id: int in removal_order:
		if runtime.model.contains(entity_id) and not runtime.remove_entity(entity_id):
			runtime.end_change_batch()
			return false
	runtime.end_change_batch()
	return true


func undo(runtime: BoardRuntime) -> bool:
	if runtime == null or not _captured:
		return false
	var ordered: Array[BoardEntitySnapshot] = _regular_first_snapshots(snapshots)
	runtime.begin_change_batch()
	for snapshot: BoardEntitySnapshot in ordered:
		if not snapshot.restore(runtime):
			runtime.end_change_batch()
			return false
	runtime.refresh_all_connector_bounds()
	runtime.end_change_batch()
	return true


func _capture(runtime: BoardRuntime) -> bool:
	snapshots.clear()
	var expanded_lookup: Dictionary = {}
	for entity_id: int in entity_ids:
		if not runtime.model.contains(entity_id):
			continue
		expanded_lookup[entity_id] = true
		if runtime.model.get_entity_type(entity_id) != BoardEntityTypes.CONNECTOR:
			for connector_id: int in runtime.model.connectors.get_attached_connector_ids(entity_id):
				expanded_lookup[connector_id] = true
	entity_ids = PackedInt64Array()
	for key: Variant in expanded_lookup.keys():
		entity_ids.append(int(key))
	for entity_id: int in entity_ids:
		var snapshot: BoardEntitySnapshot = BoardEntitySnapshot.capture(runtime, entity_id)
		if not snapshot.is_valid():
			return false
		snapshots.append(snapshot)
	_captured = true
	return true


func _connector_first_ids(runtime: BoardRuntime, ids: PackedInt64Array) -> PackedInt64Array:
	var result: PackedInt64Array = PackedInt64Array()
	for entity_id: int in ids:
		if runtime.model.contains(entity_id) and runtime.model.get_entity_type(entity_id) == BoardEntityTypes.CONNECTOR:
			result.append(entity_id)
	for entity_id: int in ids:
		if runtime.model.contains(entity_id) and runtime.model.get_entity_type(entity_id) != BoardEntityTypes.CONNECTOR:
			result.append(entity_id)
	return result


func _regular_first_snapshots(source: Array[BoardEntitySnapshot]) -> Array[BoardEntitySnapshot]:
	var regular: Array[BoardEntitySnapshot] = []
	var connectors: Array[BoardEntitySnapshot] = []
	for snapshot: BoardEntitySnapshot in source:
		if snapshot.type_id == BoardEntityTypes.CONNECTOR:
			connectors.append(snapshot)
		else:
			regular.append(snapshot)
	regular.append_array(connectors)
	return regular
