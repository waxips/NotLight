# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardEntitySnapshot
extends RefCounted

var entity_id: int = 0
var type_id: StringName = StringName()
var bounds: Rect2 = Rect2()
var rotation: float = 0.0
var z_order: int = 0
var flags: int = BoardTransformStore.FLAG_VISIBLE
var data_payload: Dictionary = {}


static func capture(runtime: BoardRuntime, source_entity_id: int) -> BoardEntitySnapshot:
	var snapshot: BoardEntitySnapshot = BoardEntitySnapshot.new()
	if runtime == null or not runtime.model.contains(source_entity_id):
		return snapshot
	snapshot.entity_id = source_entity_id
	snapshot.type_id = runtime.model.get_entity_type(source_entity_id)
	snapshot.bounds = runtime.model.get_entity_bounds(source_entity_id)
	snapshot.rotation = runtime.model.transforms.get_rotation(source_entity_id)
	snapshot.z_order = runtime.model.get_entity_z_order(source_entity_id)
	snapshot.flags = runtime.model.transforms.get_flags(source_entity_id)
	snapshot.data_payload = runtime.model.stores.capture_entity_payload(source_entity_id)
	return snapshot


func duplicate_snapshot() -> BoardEntitySnapshot:
	var result: BoardEntitySnapshot = BoardEntitySnapshot.new()
	result.entity_id = entity_id
	result.type_id = type_id
	result.bounds = bounds
	result.rotation = rotation
	result.z_order = z_order
	result.flags = flags
	result.data_payload = data_payload.duplicate(true)
	return result


func is_valid() -> bool:
	return entity_id > 0 and type_id != StringName()


func restore(runtime: BoardRuntime) -> bool:
	if runtime == null or not is_valid():
		return false
	if not runtime.restore_entity(entity_id, type_id, bounds, rotation, z_order, flags):
		return false
	if runtime.model.stores.restore_entity_payload(data_payload):
		return true
	runtime.remove_entity(entity_id)
	return false
