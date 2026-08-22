# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardDataStore
extends RefCounted

var store_id: StringName = StringName()


func _init(new_store_id: StringName = StringName()) -> void:
	store_id = new_store_id


func contains(_entity_id: int) -> bool:
	return false


func capture_record(_entity_id: int) -> Dictionary:
	return {}


func restore_record(_record: Dictionary) -> bool:
	return false


func remap_record(record: Dictionary, id_map: Dictionary) -> Dictionary:
	var remapped: Dictionary = record.duplicate(true)
	var old_entity_id: int = int(str(record.get("entity_id", "0")))
	if old_entity_id > 0 and id_map.has(old_entity_id):
		remapped["entity_id"] = str(int(id_map[old_entity_id]))
	return remapped


func remove(_entity_id: int) -> bool:
	return false


func clear() -> void:
	pass


func serialize() -> Array[Dictionary]:
	return []


func deserialize(_records: Array) -> void:
	clear()
