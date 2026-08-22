# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardEntityRegistry
extends RefCounted

signal entity_registered(entity_id: int, type_id: StringName)
signal entity_unregistered(entity_id: int, type_id: StringName)
signal cleared

var _types_by_id: Dictionary = {}
var _revision: int = 0


func register_entity(entity_id: int, type_id: StringName) -> bool:
	if entity_id <= 0 or type_id == StringName() or _types_by_id.has(entity_id):
		return false
	_types_by_id[entity_id] = type_id
	_revision += 1
	entity_registered.emit(entity_id, type_id)
	return true


func unregister_entity(entity_id: int) -> bool:
	if not _types_by_id.has(entity_id):
		return false
	var type_value: Variant = _types_by_id[entity_id]
	var type_id: StringName = StringName(str(type_value))
	_types_by_id.erase(entity_id)
	_revision += 1
	entity_unregistered.emit(entity_id, type_id)
	return true


func contains(entity_id: int) -> bool:
	return _types_by_id.has(entity_id)


func get_type(entity_id: int) -> StringName:
	var value: Variant = _types_by_id.get(entity_id, StringName())
	return StringName(str(value))


func get_entity_ids() -> PackedInt64Array:
	var result: PackedInt64Array = PackedInt64Array()
	result.resize(_types_by_id.size())
	var write_index: int = 0
	for key: Variant in _types_by_id.keys():
		result[write_index] = int(key)
		write_index += 1
	return result


func get_revision() -> int:
	return _revision


func size() -> int:
	return _types_by_id.size()


func clear() -> void:
	if _types_by_id.is_empty():
		return
	_types_by_id.clear()
	_revision += 1
	cleared.emit()
