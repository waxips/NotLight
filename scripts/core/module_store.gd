# SPDX-License-Identifier: GPL-3.0-or-later
class_name ModuleStore
extends BoardDataStore

signal module_added(entity_id: int)
signal module_changed(entity_id: int)
signal module_removed(entity_id: int)
signal cleared

const STORE_ID: StringName = &"module_objects"
const MAX_STATE_BYTES: int = 524288
const MAX_STATE_DEPTH: int = 20
const MAX_ARRAY_ITEMS: int = 4096
const MAX_DICTIONARY_ITEMS: int = 4096
const MAX_STRING_LENGTH: int = 65536
const MAX_ASSET_REFS: int = 128
const MAX_TITLE_LENGTH: int = 160

var entity_ids: PackedInt64Array = PackedInt64Array()
var module_ids: PackedStringArray = PackedStringArray()
var state_schema_versions: PackedInt32Array = PackedInt32Array()
var states: Array[Dictionary] = []
var instance_titles: PackedStringArray = PackedStringArray()
var asset_refs: Array[PackedStringArray] = []
var revisions: PackedInt64Array = PackedInt64Array()

var _index_by_id: Dictionary = {}
var _store_revision: int = 0


func _init() -> void:
	super(STORE_ID)


func add_module(
	entity_id: int,
	module_id: String,
	state_schema_version: int,
	instance_state: Dictionary,
	instance_title: String = "",
	asset_ids: PackedStringArray = PackedStringArray()
) -> bool:
	if entity_id <= 0 or _index_by_id.has(entity_id):
		return false
	var clean_module_id: String = module_id.strip_edges().to_lower()
	if not ModuleManifest.is_valid_module_id(clean_module_id) or state_schema_version <= 0:
		return false
	var state_result: Dictionary = normalize_state(instance_state)
	if not bool(state_result.get("ok", false)):
		return false
	var normalized_assets: PackedStringArray = normalize_asset_refs(asset_ids)
	if normalized_assets.size() > MAX_ASSET_REFS:
		return false
	var index: int = entity_ids.size()
	entity_ids.append(entity_id)
	module_ids.append(clean_module_id)
	state_schema_versions.append(state_schema_version)
	states.append((state_result.get("state", {}) as Dictionary).duplicate(true))
	instance_titles.append(instance_title.strip_edges().left(MAX_TITLE_LENGTH))
	asset_refs.append(normalized_assets)
	revisions.append(1)
	_index_by_id[entity_id] = index
	_store_revision += 1
	module_added.emit(entity_id)
	return true


func contains(entity_id: int) -> bool:
	return _index_by_id.has(entity_id)


func size() -> int:
	return entity_ids.size()


func get_index(entity_id: int) -> int:
	return int(_index_by_id.get(entity_id, -1))


func get_module_id(entity_id: int) -> String:
	var index: int = get_index(entity_id)
	return module_ids[index] if index >= 0 else ""


func get_state_schema_version(entity_id: int) -> int:
	var index: int = get_index(entity_id)
	return int(state_schema_versions[index]) if index >= 0 else 0


func get_state(entity_id: int) -> Dictionary:
	var index: int = get_index(entity_id)
	return states[index].duplicate(true) if index >= 0 else {}


func get_instance_title(entity_id: int) -> String:
	var index: int = get_index(entity_id)
	return instance_titles[index] if index >= 0 else ""


func get_asset_refs(entity_id: int) -> PackedStringArray:
	var index: int = get_index(entity_id)
	return asset_refs[index].duplicate() if index >= 0 else PackedStringArray()


func get_revision(entity_id: int) -> int:
	var index: int = get_index(entity_id)
	return int(revisions[index]) if index >= 0 else 0


func get_store_revision() -> int:
	return _store_revision


func get_record(entity_id: int) -> Dictionary:
	var index: int = get_index(entity_id)
	if index < 0:
		return {}
	var listed_assets: Array[String] = []
	for asset_id: String in asset_refs[index]:
		listed_assets.append(asset_id)
	return {
		"entity_id": str(entity_ids[index]),
		"module_id": module_ids[index],
		"state_schema_version": int(state_schema_versions[index]),
		"instance_state": states[index].duplicate(true),
		"instance_title": instance_titles[index],
		"asset_ids": listed_assets,
	}


func capture_record(entity_id: int) -> Dictionary:
	return get_record(entity_id)


func apply_record(entity_id: int, record: Dictionary) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	var next_module_id: String = str(record.get("module_id", module_ids[index])).strip_edges().to_lower()
	if next_module_id != module_ids[index]:
		return false
	var next_schema: int = int(record.get("state_schema_version", int(state_schema_versions[index])))
	if next_schema <= 0:
		return false
	var state_value: Variant = record.get("instance_state", states[index])
	if state_value is not Dictionary:
		return false
	var state_result: Dictionary = normalize_state(state_value as Dictionary)
	if not bool(state_result.get("ok", false)):
		return false
	var next_state: Dictionary = (state_result.get("state", {}) as Dictionary).duplicate(true)
	var next_title: String = str(record.get("instance_title", instance_titles[index])).strip_edges().left(MAX_TITLE_LENGTH)
	var next_assets: PackedStringArray = _asset_refs_from_variant(record.get("asset_ids", asset_refs[index]))
	if next_assets.size() > MAX_ASSET_REFS:
		return false
	if (
		int(state_schema_versions[index]) == next_schema
		and states[index] == next_state
		and instance_titles[index] == next_title
		and asset_refs[index] == next_assets
	):
		return true
	state_schema_versions[index] = next_schema
	states[index] = next_state
	instance_titles[index] = next_title
	asset_refs[index] = next_assets
	_touch(index, entity_id)
	return true


func restore_record(record: Dictionary) -> bool:
	var entity_id: int = int(str(record.get("entity_id", "0")))
	if entity_id <= 0:
		return false
	var state_value: Variant = record.get("instance_state", {})
	if state_value is not Dictionary:
		return false
	return add_module(
		entity_id,
		str(record.get("module_id", "")),
		int(record.get("state_schema_version", 1)),
		state_value as Dictionary,
		str(record.get("instance_title", "")),
		_asset_refs_from_variant(record.get("asset_ids", []))
	)


func remap_record(record: Dictionary, id_map: Dictionary) -> Dictionary:
	var remapped: Dictionary = record.duplicate(true)
	var old_entity_id: int = int(str(record.get("entity_id", "0")))
	if old_entity_id > 0 and id_map.has(old_entity_id):
		remapped["entity_id"] = str(int(id_map[old_entity_id]))
	return remapped


func remove(entity_id: int) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	var last_index: int = entity_ids.size() - 1
	if index != last_index:
		entity_ids[index] = entity_ids[last_index]
		module_ids[index] = module_ids[last_index]
		state_schema_versions[index] = state_schema_versions[last_index]
		states[index] = states[last_index]
		instance_titles[index] = instance_titles[last_index]
		asset_refs[index] = asset_refs[last_index]
		revisions[index] = revisions[last_index]
		_index_by_id[int(entity_ids[index])] = index
	entity_ids.resize(last_index)
	module_ids.resize(last_index)
	state_schema_versions.resize(last_index)
	states.resize(last_index)
	instance_titles.resize(last_index)
	asset_refs.resize(last_index)
	revisions.resize(last_index)
	_index_by_id.erase(entity_id)
	_store_revision += 1
	module_removed.emit(entity_id)
	return true


func clear() -> void:
	if entity_ids.is_empty():
		return
	entity_ids = PackedInt64Array()
	module_ids = PackedStringArray()
	state_schema_versions = PackedInt32Array()
	states.clear()
	instance_titles = PackedStringArray()
	asset_refs.clear()
	revisions = PackedInt64Array()
	_index_by_id.clear()
	_store_revision += 1
	cleared.emit()


func serialize() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entity_id: int in entity_ids:
		result.append(get_record(entity_id))
	return result


func deserialize(records: Array) -> void:
	clear()
	for raw_record: Variant in records:
		if raw_record is Dictionary:
			restore_record(raw_record as Dictionary)
	_store_revision = 0


static func normalize_state(source: Dictionary) -> Dictionary:
	var result: Dictionary = _normalize_variant(source, 0)
	if not bool(result.get("ok", false)):
		return result
	var normalized: Variant = result.get("value", {})
	if normalized is not Dictionary:
		return {"ok": false, "error": NotLightL10n.text("runtime.core.module_store.9d9959c86c")}
	var json_text: String = JSON.stringify(normalized)
	if json_text.to_utf8_buffer().size() > MAX_STATE_BYTES:
		return {"ok": false, "error": NotLightL10n.text("runtime.core.module_store.947cce683f")}
	return {"ok": true, "state": (normalized as Dictionary).duplicate(true)}


static func normalize_asset_refs(values: PackedStringArray) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	for raw_asset_id: String in values:
		var asset_id: String = raw_asset_id.strip_edges()
		if asset_id.is_empty() or seen.has(asset_id):
			continue
		seen[asset_id] = true
		result.append(asset_id)
		if result.size() >= MAX_ASSET_REFS:
			break
	return result


static func _asset_refs_from_variant(value: Variant) -> PackedStringArray:
	var raw: PackedStringArray = PackedStringArray()
	if value is PackedStringArray:
		raw = (value as PackedStringArray).duplicate()
	elif value is Array:
		for item: Variant in (value as Array):
			raw.append(str(item))
	return normalize_asset_refs(raw)


static func _normalize_variant(value: Variant, depth: int) -> Dictionary:
	if depth > MAX_STATE_DEPTH:
		return {"ok": false, "error": NotLightL10n.text("runtime.core.module_store.04800d1d5b")}
	if value == null or value is bool or value is int:
		return {"ok": true, "value": value}
	if value is float:
		var number: float = float(value)
		if not is_finite(number):
			return {"ok": false, "error": NotLightL10n.text("runtime.core.module_store.13d2ec7011")}
		return {"ok": true, "value": number}
	if value is String or value is StringName:
		return {"ok": true, "value": str(value).left(MAX_STRING_LENGTH)}
	if value is Array:
		var source_array: Array = value as Array
		if source_array.size() > MAX_ARRAY_ITEMS:
			return {"ok": false, "error": NotLightL10n.text("runtime.core.module_store.7bd071fa4f")}
		var result_array: Array = []
		for item: Variant in source_array:
			var item_result: Dictionary = _normalize_variant(item, depth + 1)
			if not bool(item_result.get("ok", false)):
				return item_result
			result_array.append(item_result.get("value"))
		return {"ok": true, "value": result_array}
	if value is Dictionary:
		var source_dictionary: Dictionary = value as Dictionary
		if source_dictionary.size() > MAX_DICTIONARY_ITEMS:
			return {"ok": false, "error": NotLightL10n.text("runtime.core.module_store.50170167b4")}
		var result_dictionary: Dictionary = {}
		for raw_key: Variant in source_dictionary.keys():
			if raw_key is not String and raw_key is not StringName:
				return {"ok": false, "error": NotLightL10n.text("runtime.core.module_store.fd4fd89dc3")}
			var key: String = str(raw_key).left(256)
			if key.is_empty() or result_dictionary.has(key):
				return {"ok": false, "error": NotLightL10n.text("runtime.core.module_store.22e2337529")}
			var child_result: Dictionary = _normalize_variant(source_dictionary[raw_key], depth + 1)
			if not bool(child_result.get("ok", false)):
				return child_result
			result_dictionary[key] = child_result.get("value")
		return {"ok": true, "value": result_dictionary}
	return {"ok": false, "error": NotLightL10n.text("runtime.core.module_store.1fb1eab12c") % type_string(typeof(value))}


func _touch(index: int, entity_id: int) -> void:
	revisions[index] = int(revisions[index]) + 1
	_store_revision += 1
	module_changed.emit(entity_id)
