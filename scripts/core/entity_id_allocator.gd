# SPDX-License-Identifier: GPL-3.0-or-later
class_name EntityIdAllocator
extends RefCounted

const FIRST_ENTITY_ID: int = 1

var _next_id: int = FIRST_ENTITY_ID


func allocate() -> int:
	var result: int = _next_id
	_next_id += 1
	return result


func reserve(entity_id: int) -> void:
	if entity_id >= _next_id:
		_next_id = entity_id + 1


func reset(next_id: int = FIRST_ENTITY_ID) -> void:
	_next_id = maxi(next_id, FIRST_ENTITY_ID)


func get_next_id() -> int:
	return _next_id


func serialize_next_id() -> String:
	return str(_next_id)


func restore_serialized(value: Variant) -> void:
	var parsed: int = FIRST_ENTITY_ID
	if value is String:
		parsed = int(value as String)
	elif value is int or value is float:
		parsed = int(value)
	reset(parsed)
