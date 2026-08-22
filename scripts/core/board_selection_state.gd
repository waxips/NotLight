# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardSelectionState
extends RefCounted

signal selection_changed(selected_ids: PackedInt64Array, primary_id: int)

var primary_id: int = 0
var _selected: Dictionary = {}
var _revision: int = 0


func set_single(entity_id: int) -> void:
	if entity_id <= 0:
		clear()
		return
	if _selected.size() == 1 and _selected.has(entity_id) and primary_id == entity_id:
		return
	_selected.clear()
	_selected[entity_id] = true
	primary_id = entity_id
	_emit_changed()


func set_many(entity_ids: PackedInt64Array, new_primary_id: int = 0) -> void:
	_selected.clear()
	for entity_id: int in entity_ids:
		if entity_id > 0:
			_selected[entity_id] = true
	primary_id = new_primary_id if _selected.has(new_primary_id) else _first_selected()
	_emit_changed()


func add(entity_id: int, make_primary: bool = true) -> void:
	if entity_id <= 0:
		return
	var changed: bool = not _selected.has(entity_id)
	_selected[entity_id] = true
	if make_primary and primary_id != entity_id:
		primary_id = entity_id
		changed = true
	if changed:
		_emit_changed()


func remove(entity_id: int) -> void:
	if not _selected.has(entity_id):
		return
	_selected.erase(entity_id)
	if primary_id == entity_id:
		primary_id = _first_selected()
	_emit_changed()


func toggle(entity_id: int) -> void:
	if _selected.has(entity_id):
		remove(entity_id)
	else:
		add(entity_id, true)


func contains(entity_id: int) -> bool:
	return _selected.has(entity_id)


func clear() -> void:
	if _selected.is_empty() and primary_id == 0:
		return
	_selected.clear()
	primary_id = 0
	_emit_changed()


func get_selected_ids() -> PackedInt64Array:
	var result: PackedInt64Array = PackedInt64Array()
	result.resize(_selected.size())
	var index: int = 0
	for key: Variant in _selected.keys():
		result[index] = int(key)
		index += 1
	return result


func size() -> int:
	return _selected.size()


func get_revision() -> int:
	return _revision


func _first_selected() -> int:
	for key: Variant in _selected.keys():
		return int(key)
	return 0


func _emit_changed() -> void:
	_revision += 1
	selection_changed.emit(get_selected_ids(), primary_id)
