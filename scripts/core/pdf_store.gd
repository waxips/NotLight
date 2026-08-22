# SPDX-License-Identifier: GPL-3.0-or-later
class_name PdfStore
extends BoardDataStore

signal pdf_added(entity_id: int)
signal pdf_changed(entity_id: int)
signal pdf_removed(entity_id: int)
signal cleared

const STORE_ID: StringName = &"pdf_blocks"
const DEFAULT_PAGE_SIZE: Vector2i = Vector2i(595, 842)
const MIN_PAGE_DIMENSION: int = 1

var entity_ids: PackedInt64Array = PackedInt64Array()
var asset_ids: PackedStringArray = PackedStringArray()
var instance_titles: PackedStringArray = PackedStringArray()
var page_indices: PackedInt32Array = PackedInt32Array()
var page_counts: PackedInt32Array = PackedInt32Array()
var page_widths: PackedInt32Array = PackedInt32Array()
var page_heights: PackedInt32Array = PackedInt32Array()
var revisions: PackedInt64Array = PackedInt64Array()

var _index_by_id: Dictionary = {}
var _store_revision: int = 0


func _init() -> void:
	super(STORE_ID)


func add_pdf(
	entity_id: int,
	asset_id: String,
	page_count: int = 1,
	page_size: Vector2i = DEFAULT_PAGE_SIZE,
	page_index: int = 0,
	instance_title: String = ""
) -> bool:
	if entity_id <= 0 or _index_by_id.has(entity_id):
		return false
	var clean_asset_id: String = asset_id.strip_edges()
	if clean_asset_id.is_empty():
		return false
	var safe_count: int = maxi(1, page_count)
	var safe_page: int = clampi(page_index, 0, safe_count - 1)
	var safe_size: Vector2i = Vector2i(maxi(MIN_PAGE_DIMENSION, page_size.x), maxi(MIN_PAGE_DIMENSION, page_size.y))
	var index: int = entity_ids.size()
	entity_ids.append(entity_id)
	asset_ids.append(clean_asset_id)
	instance_titles.append(instance_title.strip_edges().left(160))
	page_indices.append(safe_page)
	page_counts.append(safe_count)
	page_widths.append(safe_size.x)
	page_heights.append(safe_size.y)
	revisions.append(1)
	_index_by_id[entity_id] = index
	_store_revision += 1
	pdf_added.emit(entity_id)
	return true


func contains(entity_id: int) -> bool:
	return _index_by_id.has(entity_id)


func size() -> int:
	return entity_ids.size()


func get_index(entity_id: int) -> int:
	return int(_index_by_id.get(entity_id, -1))


func get_asset_id(entity_id: int) -> String:
	var index: int = get_index(entity_id)
	return asset_ids[index] if index >= 0 else ""


func get_instance_title(entity_id: int) -> String:
	var index: int = get_index(entity_id)
	return instance_titles[index] if index >= 0 else ""


func set_instance_title(entity_id: int, title: String) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	var clean: String = title.strip_edges().left(160)
	if instance_titles[index] == clean:
		return true
	instance_titles[index] = clean
	_touch(index, entity_id)
	return true


func get_page_index(entity_id: int) -> int:
	var index: int = get_index(entity_id)
	return int(page_indices[index]) if index >= 0 else 0


func get_page_count(entity_id: int) -> int:
	var index: int = get_index(entity_id)
	return maxi(1, int(page_counts[index])) if index >= 0 else 1


func get_page_size(entity_id: int) -> Vector2i:
	var index: int = get_index(entity_id)
	if index < 0:
		return DEFAULT_PAGE_SIZE
	return Vector2i(maxi(1, int(page_widths[index])), maxi(1, int(page_heights[index])))


func get_revision(entity_id: int) -> int:
	var index: int = get_index(entity_id)
	return int(revisions[index]) if index >= 0 else 0


func get_store_revision() -> int:
	return _store_revision


func set_page_index(entity_id: int, page_index: int) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	var safe_page: int = clampi(page_index, 0, maxi(0, int(page_counts[index]) - 1))
	if int(page_indices[index]) == safe_page:
		return true
	page_indices[index] = safe_page
	_touch(index, entity_id)
	return true


func update_document_info(entity_id: int, page_count: int, page_size: Vector2i) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	var safe_count: int = maxi(1, page_count)
	var safe_size: Vector2i = Vector2i(maxi(1, page_size.x), maxi(1, page_size.y))
	var changed: bool = int(page_counts[index]) != safe_count or int(page_widths[index]) != safe_size.x or int(page_heights[index]) != safe_size.y
	if not changed:
		return true
	page_counts[index] = safe_count
	page_widths[index] = safe_size.x
	page_heights[index] = safe_size.y
	page_indices[index] = mini(int(page_indices[index]), safe_count - 1)
	_touch(index, entity_id)
	return true


func get_record(entity_id: int) -> Dictionary:
	var index: int = get_index(entity_id)
	if index < 0:
		return {}
	return {
		"entity_id": str(entity_ids[index]),
		"asset_id": asset_ids[index],
		"instance_title": instance_titles[index],
		"page_index": int(page_indices[index]),
		"page_count": int(page_counts[index]),
		"page_width": int(page_widths[index]),
		"page_height": int(page_heights[index]),
	}


func capture_record(entity_id: int) -> Dictionary:
	return get_record(entity_id)


func restore_record(record: Dictionary) -> bool:
	var entity_id: int = int(str(record.get("entity_id", "0")))
	var asset_id: String = str(record.get("asset_id", "")).strip_edges()
	if entity_id <= 0 or asset_id.is_empty():
		return false
	return add_pdf(
		entity_id,
		asset_id,
		maxi(1, int(record.get("page_count", 1))),
		Vector2i(maxi(1, int(record.get("page_width", DEFAULT_PAGE_SIZE.x))), maxi(1, int(record.get("page_height", DEFAULT_PAGE_SIZE.y)))),
		maxi(0, int(record.get("page_index", 0))),
		str(record.get("instance_title", ""))
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
		asset_ids[index] = asset_ids[last_index]
		instance_titles[index] = instance_titles[last_index]
		page_indices[index] = page_indices[last_index]
		page_counts[index] = page_counts[last_index]
		page_widths[index] = page_widths[last_index]
		page_heights[index] = page_heights[last_index]
		revisions[index] = revisions[last_index]
		_index_by_id[int(entity_ids[index])] = index
	entity_ids.resize(last_index)
	asset_ids.resize(last_index)
	instance_titles.resize(last_index)
	page_indices.resize(last_index)
	page_counts.resize(last_index)
	page_widths.resize(last_index)
	page_heights.resize(last_index)
	revisions.resize(last_index)
	_index_by_id.erase(entity_id)
	_store_revision += 1
	pdf_removed.emit(entity_id)
	return true


func clear() -> void:
	if entity_ids.is_empty():
		return
	entity_ids = PackedInt64Array()
	asset_ids = PackedStringArray()
	instance_titles = PackedStringArray()
	page_indices = PackedInt32Array()
	page_counts = PackedInt32Array()
	page_widths = PackedInt32Array()
	page_heights = PackedInt32Array()
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


func _touch(index: int, entity_id: int) -> void:
	revisions[index] = int(revisions[index]) + 1
	_store_revision += 1
	pdf_changed.emit(entity_id)
