# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardDocumentSchema
extends RefCounted

const SCHEMA_ID: String = "notlight.board"
const CURRENT_VERSION: int = 13
const CONTENT_KEYS: Array[String] = [
	"text_blocks",
	"images",
	"videos",
	"audios",
	"pdf_blocks",
	"formulas",
	"module_objects",
	"note_portals",
	"strokes",
	"shapes",
	"frames",
	"connectors",
]

# Asset references are part of the board schema, not a convention based on field
# names. In particular, ModuleObject.instance_state is intentionally opaque
# module-owned JSON and must never be traversed or rewritten by core portability.
const SINGLE_ASSET_REFERENCE_FIELDS: Dictionary = {
	"images": ["asset_id"],
	"videos": ["asset_id"],
	"audios": ["asset_id"],
	"pdf_blocks": ["asset_id"],
	"note_portals": ["asset_id"],
}
const MULTI_ASSET_REFERENCE_FIELDS: Dictionary = {
	"module_objects": ["asset_ids"],
	"note_portals": ["workspace_tabs"],
}


static func make_empty() -> Dictionary:
	return {
		"schema": SCHEMA_ID,
		"schema_version": CURRENT_VERSION,
		"storage": {
			"transaction_id": "",
			"stroke_payload": "",
		},
		"runtime": {
			"next_entity_id": "1",
		},
		"core": {
			"entities": [],
		},
		"view": {
			"camera_position": {"x": 0.0, "y": 0.0},
			"zoom": 1.0,
		},
		"content": {
			"text_blocks": [],
			"images": [],
			"videos": [],
			"audios": [],
			"pdf_blocks": [],
			"formulas": [],
			"module_objects": [],
			"note_portals": [],
			"strokes": [],
			"shapes": [],
			"frames": [],
			"connectors": [],
		},
		"feature_data": {},
	}


static func is_supported(source: Dictionary) -> bool:
	var schema_id: String = str(source.get("schema", SCHEMA_ID))
	if not schema_id.is_empty() and schema_id != SCHEMA_ID:
		return false
	var version: int = int(source.get("schema_version", 1))
	return version >= 1 and version <= CURRENT_VERSION


static func normalize(source: Dictionary) -> Dictionary:
	var working: Dictionary = source.duplicate(true)
	var version: int = int(working.get("schema_version", 1))
	if version < 1:
		version = 1
	while version < CURRENT_VERSION:
		match version:
			1:
				working = _migrate_v1_to_v2(working)
				version = 2
			2:
				working = _migrate_v2_to_v3(working)
				version = 3
			3:
				working = _migrate_v3_to_v4(working)
				version = 4
			4:
				working = _migrate_v4_to_v5(working)
				version = 5
			5:
				working = _migrate_v5_to_v6(working)
				version = 6
			6:
				working = _migrate_v6_to_v7(working)
				version = 7
			7:
				working = _migrate_v7_to_v8(working)
				version = 8
			8:
				working = _migrate_v8_to_v9(working)
				version = 9
			9:
				working = _migrate_v9_to_v10(working)
				version = 10
			10:
				working = _migrate_v10_to_v11(working)
				version = 11
			11:
				working = _migrate_v11_to_v12(working)
				version = 12
			12:
				working = _migrate_v12_to_v13(working)
				version = 13
			_:
				break
	return _normalize_v13(working)


static func _migrate_v1_to_v2(source: Dictionary) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	result["schema"] = SCHEMA_ID
	result["schema_version"] = 2
	if not result.has("storage"):
		result["storage"] = {"transaction_id": ""}
	if not result.has("runtime"):
		result["runtime"] = {"next_entity_id": "1"}
	if not result.has("core"):
		result["core"] = {"entities": []}
	return result


static func _migrate_v2_to_v3(source: Dictionary) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	result["schema"] = SCHEMA_ID
	result["schema_version"] = 3
	var content: Dictionary = result.get("content", {}) as Dictionary
	var text_records: Array = content.get("text_blocks", []) as Array
	for index: int in range(text_records.size()):
		if text_records[index] is not Dictionary:
			continue
		var record: Dictionary = (text_records[index] as Dictionary).duplicate(true)
		var legacy_style: int = clampi(int(record.get("style_id", TextBlockStore.STYLE_PLAIN)), TextBlockStore.STYLE_PLAIN, TextBlockStore.STYLE_HEADING)
		if not record.has("background_color") or str(record.get("background_color", "")).is_empty():
			record["background_color"] = TextBlockStore.default_background_for_style(legacy_style).to_html(true)
		record["style_id"] = TextBlockStore.STYLE_PLAIN
		if not record.has("font_family"):
			record["font_family"] = TextBlockStore.DEFAULT_FONT_FAMILY
		if not record.has("base_style_flags"):
			record["base_style_flags"] = 0
		if not record.has("style_runs"):
			record["style_runs"] = []
		if not record.has("paragraphs"):
			record["paragraphs"] = []
		text_records[index] = record
	content["text_blocks"] = text_records
	result["content"] = content
	return result


static func _migrate_v3_to_v4(source: Dictionary) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	result["schema"] = SCHEMA_ID
	result["schema_version"] = 4
	var content: Dictionary = result.get("content", {}) as Dictionary
	if not content.has("images"):
		content["images"] = []
	result["content"] = content
	return result


static func _migrate_v4_to_v5(source: Dictionary) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	result["schema"] = SCHEMA_ID
	result["schema_version"] = 5
	var content: Dictionary = result.get("content", {}) as Dictionary
	if not content.has("videos"):
		content["videos"] = []
	result["content"] = content
	return result


static func _migrate_v5_to_v6(source: Dictionary) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	result["schema"] = SCHEMA_ID
	result["schema_version"] = 6
	var content: Dictionary = result.get("content", {}) as Dictionary
	for key: String in ["images", "videos"]:
		var records: Array = content.get(key, []) as Array
		for index: int in range(records.size()):
			if records[index] is not Dictionary:
				continue
			var record: Dictionary = (records[index] as Dictionary).duplicate(true)
			if not record.has("instance_title"):
				record["instance_title"] = ""
			records[index] = record
		content[key] = records
	result["content"] = content
	return result


static func _migrate_v6_to_v7(source: Dictionary) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	result["schema"] = SCHEMA_ID
	result["schema_version"] = 7
	var storage: Dictionary = result.get("storage", {}) as Dictionary
	if not storage.has("stroke_payload"):
		storage["stroke_payload"] = ""
	result["storage"] = storage
	return result


static func _migrate_v7_to_v8(source: Dictionary) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	result["schema"] = SCHEMA_ID
	result["schema_version"] = 8
	var content: Dictionary = result.get("content", {}) as Dictionary
	var records: Array = content.get("strokes", []) as Array
	for index: int in range(records.size()):
		if records[index] is not Dictionary:
			continue
		var record: Dictionary = (records[index] as Dictionary).duplicate(true)
		if not record.has("spray_spread"):
			record["spray_spread"] = 1.0
		records[index] = record
	content["strokes"] = records
	result["content"] = content
	return result


static func _migrate_v8_to_v9(source: Dictionary) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	result["schema"] = SCHEMA_ID
	result["schema_version"] = 9
	var content: Dictionary = result.get("content", {}) as Dictionary
	if not content.has("audios"):
		content["audios"] = []
	result["content"] = content
	return result


static func _migrate_v9_to_v10(source: Dictionary) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	result["schema"] = SCHEMA_ID
	result["schema_version"] = 10
	var content: Dictionary = result.get("content", {}) as Dictionary
	if not content.has("pdf_blocks"):
		content["pdf_blocks"] = []
	result["content"] = content
	return result


static func _migrate_v10_to_v11(source: Dictionary) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	result["schema"] = SCHEMA_ID
	result["schema_version"] = 11
	var content: Dictionary = result.get("content", {}) as Dictionary
	if not content.has("formulas"):
		content["formulas"] = []
	result["content"] = content
	return result


static func _migrate_v11_to_v12(source: Dictionary) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	result["schema"] = SCHEMA_ID
	result["schema_version"] = 12
	var content: Dictionary = result.get("content", {}) as Dictionary
	if not content.has("module_objects"):
		content["module_objects"] = []
	result["content"] = content
	return result


static func _migrate_v12_to_v13(source: Dictionary) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	result["schema"] = SCHEMA_ID
	result["schema_version"] = 13
	var content: Dictionary = result.get("content", {}) as Dictionary
	if not content.has("note_portals"):
		content["note_portals"] = []
	result["content"] = content
	return result


static func _normalize_v13(source: Dictionary) -> Dictionary:
	var result: Dictionary = make_empty()
	result["schema"] = SCHEMA_ID
	result["schema_version"] = CURRENT_VERSION

	var storage_source: Dictionary = source.get("storage", {}) as Dictionary
	var stroke_payload: String = str(storage_source.get("stroke_payload", "")).strip_edges()
	if not _is_safe_payload_filename(stroke_payload):
		stroke_payload = ""
	result["storage"] = {
		"transaction_id": str(storage_source.get("transaction_id", "")),
		"stroke_payload": stroke_payload,
	}

	var runtime_source: Dictionary = source.get("runtime", {}) as Dictionary
	result["runtime"] = {
		"next_entity_id": str(runtime_source.get("next_entity_id", "1")),
	}

	var core_source: Dictionary = source.get("core", {}) as Dictionary
	var core_entities: Array = core_source.get("entities", []) as Array
	result["core"] = {
		"entities": core_entities.duplicate(true),
	}

	var view_source: Dictionary = source.get("view", {}) as Dictionary
	var camera_source: Dictionary = view_source.get("camera_position", {}) as Dictionary
	result["view"] = {
		"camera_position": {
			"x": float(camera_source.get("x", 0.0)),
			"y": float(camera_source.get("y", 0.0)),
		},
		"zoom": clampf(float(view_source.get("zoom", 1.0)), 0.08, 8.0),
	}

	var content_source: Dictionary = source.get("content", {}) as Dictionary
	var content_result: Dictionary = result["content"] as Dictionary
	for key: String in CONTENT_KEYS:
		var records: Array = content_source.get(key, []) as Array
		content_result[key] = records.duplicate(true)
	result["content"] = content_result

	var feature_source: Dictionary = source.get("feature_data", {}) as Dictionary
	result["feature_data"] = feature_source.duplicate(true)
	return result


static func collect_module_references(document: Dictionary) -> PackedStringArray:
	var found: Dictionary = {}
	var content: Dictionary = document.get("content", {}) as Dictionary
	var records: Array = content.get("module_objects", []) as Array
	for raw_record: Variant in records:
		if raw_record is not Dictionary:
			continue
		var module_id: String = str((raw_record as Dictionary).get("module_id", "")).strip_edges().to_lower()
		if ModuleManifest.is_valid_module_id(module_id):
			found[module_id] = true
	var result: PackedStringArray = PackedStringArray()
	var keys: Array = found.keys()
	keys.sort()
	for raw_key: Variant in keys:
		result.append(str(raw_key))
	return result


static func collect_note_references(document: Dictionary) -> PackedStringArray:
	var found: Dictionary = {}
	var content_value: Variant = document.get("content", {})
	if content_value is Dictionary:
		var records_value: Variant = (content_value as Dictionary).get("note_portals", [])
		if records_value is Array:
			for raw_record: Variant in records_value as Array:
				if raw_record is not Dictionary:
					continue
				var record: Dictionary = raw_record as Dictionary
				var note_id: String = str(record.get("asset_id", record.get("note_id", ""))).strip_edges()
				if not note_id.is_empty():
					found[note_id] = true
				var tabs_value: Variant = record.get("workspace_tabs", [])
				if tabs_value is Array:
					for raw_tab: Variant in tabs_value as Array:
						var tab_id: String = str(raw_tab).strip_edges()
						if not tab_id.is_empty():
							found[tab_id] = true
	var result: PackedStringArray = PackedStringArray()
	var keys: Array = found.keys()
	keys.sort()
	for raw_key: Variant in keys:
		result.append(str(raw_key))
	return result


static func collect_asset_references(document: Dictionary) -> PackedStringArray:
	var found: Dictionary = {}
	var content_value: Variant = document.get("content", {})
	if content_value is Dictionary:
		var content: Dictionary = content_value as Dictionary
		_collect_declared_asset_fields(content, SINGLE_ASSET_REFERENCE_FIELDS, found, false)
		_collect_declared_asset_fields(content, MULTI_ASSET_REFERENCE_FIELDS, found, true)
	var result: PackedStringArray = PackedStringArray()
	var keys: Array = found.keys()
	keys.sort()
	for raw_key: Variant in keys:
		result.append(str(raw_key))
	return result


static func remap_asset_references(document: Dictionary, asset_id_map: Dictionary) -> Dictionary:
	# Remapping follows the same explicit schema used for collection. Unknown
	# feature_data and nested module state are copied byte-for-byte at the Variant
	# level so a module is free to use keys such as `asset_id` for its own domain.
	var result: Dictionary = document.duplicate(true)
	var content_value: Variant = result.get("content", {})
	if content_value is not Dictionary:
		return result
	var content: Dictionary = content_value as Dictionary
	_remap_declared_asset_fields(content, SINGLE_ASSET_REFERENCE_FIELDS, asset_id_map, false)
	_remap_declared_asset_fields(content, MULTI_ASSET_REFERENCE_FIELDS, asset_id_map, true)
	result["content"] = content
	return result


static func _collect_declared_asset_fields(
	content: Dictionary,
	fields_by_content_key: Dictionary,
	found: Dictionary,
	multiple: bool
) -> void:
	for raw_content_key: Variant in fields_by_content_key.keys():
		var content_key: String = str(raw_content_key)
		var records_value: Variant = content.get(content_key, [])
		if records_value is not Array:
			continue
		var field_names_value: Variant = fields_by_content_key[raw_content_key]
		if field_names_value is not Array:
			continue
		for raw_record: Variant in records_value as Array:
			if raw_record is not Dictionary:
				continue
			var record: Dictionary = raw_record as Dictionary
			for raw_field_name: Variant in field_names_value as Array:
				var field_name: String = str(raw_field_name)
				if multiple:
					_collect_asset_id_list(record.get(field_name, []), found)
				else:
					var asset_id: String = str(record.get(field_name, "")).strip_edges()
					if not asset_id.is_empty():
						found[asset_id] = true


static func _collect_asset_id_list(value: Variant, found: Dictionary) -> void:
	if value is Array:
		for raw_asset_id: Variant in value as Array:
			var asset_id: String = str(raw_asset_id).strip_edges()
			if not asset_id.is_empty():
				found[asset_id] = true
	elif value is PackedStringArray:
		for asset_id: String in value as PackedStringArray:
			var clean_id: String = asset_id.strip_edges()
			if not clean_id.is_empty():
				found[clean_id] = true


static func _remap_declared_asset_fields(
	content: Dictionary,
	fields_by_content_key: Dictionary,
	asset_id_map: Dictionary,
	multiple: bool
) -> void:
	for raw_content_key: Variant in fields_by_content_key.keys():
		var content_key: String = str(raw_content_key)
		var records_value: Variant = content.get(content_key, [])
		if records_value is not Array:
			continue
		var records: Array = records_value as Array
		var field_names_value: Variant = fields_by_content_key[raw_content_key]
		if field_names_value is not Array:
			continue
		for record_index: int in range(records.size()):
			if records[record_index] is not Dictionary:
				continue
			var record: Dictionary = (records[record_index] as Dictionary).duplicate(true)
			for raw_field_name: Variant in field_names_value as Array:
				var field_name: String = str(raw_field_name)
				if not record.has(field_name):
					continue
				if multiple:
					record[field_name] = _remap_asset_id_list(record[field_name], asset_id_map)
				else:
					var source_id: String = str(record[field_name])
					record[field_name] = str(asset_id_map.get(source_id, source_id))
			records[record_index] = record
		content[content_key] = records


static func _remap_asset_id_list(value: Variant, asset_id_map: Dictionary) -> Variant:
	if value is PackedStringArray:
		var remapped_packed: PackedStringArray = PackedStringArray()
		for source_id: String in value as PackedStringArray:
			remapped_packed.append(str(asset_id_map.get(source_id, source_id)))
		return remapped_packed
	if value is Array:
		var remapped: Array[String] = []
		for raw_id: Variant in value as Array:
			var source_id: String = str(raw_id)
			remapped.append(str(asset_id_map.get(source_id, source_id)))
		return remapped
	return value


static func _is_safe_payload_filename(filename: String) -> bool:
	if filename.is_empty():
		return true
	if filename.get_file() != filename or filename.contains("/") or filename.contains("\\"):
		return false
	return filename.begins_with("strokes_") and filename.ends_with(".bin")
