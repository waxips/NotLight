# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardStoreRegistry
extends RefCounted

var _stores: Dictionary = {}


func register_store(store: BoardDataStore) -> bool:
	if store == null or store.store_id == StringName() or _stores.has(store.store_id):
		return false
	_stores[store.store_id] = store
	return true


func unregister_store(store_id: StringName) -> bool:
	if not _stores.has(store_id):
		return false
	_stores.erase(store_id)
	return true


func get_store(store_id: StringName) -> BoardDataStore:
	var value: Variant = _stores.get(store_id)
	return value as BoardDataStore


func has_store(store_id: StringName) -> bool:
	return _stores.has(store_id)


func capture_entity_payload(entity_id: int) -> Dictionary:
	for key: Variant in _stores.keys():
		var store: BoardDataStore = _stores[key] as BoardDataStore
		if store == null or not store.contains(entity_id):
			continue
		return {
			"store_id": str(store.store_id),
			"record": store.capture_record(entity_id),
		}
	return {}


func restore_entity_payload(payload: Dictionary) -> bool:
	if payload.is_empty():
		return true
	var store_id: StringName = StringName(str(payload.get("store_id", "")))
	var store: BoardDataStore = get_store(store_id)
	if store == null:
		return false
	var record: Dictionary = payload.get("record", {}) as Dictionary
	return store.restore_record(record)


func remap_entity_payload(payload: Dictionary, id_map: Dictionary) -> Dictionary:
	if payload.is_empty():
		return {}
	var store_id: StringName = StringName(str(payload.get("store_id", "")))
	var store: BoardDataStore = get_store(store_id)
	if store == null:
		return payload.duplicate(true)
	var record: Dictionary = payload.get("record", {}) as Dictionary
	return {
		"store_id": str(store_id),
		"record": store.remap_record(record, id_map),
	}


func remove_entity(entity_id: int) -> void:
	for value: Variant in _stores.values():
		var store: BoardDataStore = value as BoardDataStore
		if store != null and store.contains(entity_id):
			store.remove(entity_id)


func clear() -> void:
	for value: Variant in _stores.values():
		var store: BoardDataStore = value as BoardDataStore
		if store != null:
			store.clear()


func deserialize_content(content: Dictionary) -> void:
	for key: Variant in _stores.keys():
		var store_id: StringName = StringName(str(key))
		var store: BoardDataStore = _stores[key] as BoardDataStore
		if store == null:
			continue
		var records_value: Variant = content.get(str(store_id), [])
		if records_value is Array:
			store.deserialize(records_value as Array)
		else:
			store.clear()


func serialize_content() -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in _stores.keys():
		var store_id: StringName = StringName(str(key))
		var store: BoardDataStore = _stores[key] as BoardDataStore
		if store != null:
			result[str(store_id)] = store.serialize()
	return result
