# SPDX-License-Identifier: GPL-3.0-or-later
class_name ImageStore
extends BoardDataStore

signal image_added(entity_id: int)
signal image_changed(entity_id: int)
signal image_removed(entity_id: int)
signal cleared

const STORE_ID: StringName = &"images"
const MIN_PIXEL_DIMENSION: int = 1
const DEFAULT_PIXEL_SIZE: Vector2i = Vector2i(640, 480)

var entity_ids: PackedInt64Array = PackedInt64Array()
var asset_ids: PackedStringArray = PackedStringArray()
var instance_titles: PackedStringArray = PackedStringArray()
var pixel_widths: PackedInt32Array = PackedInt32Array()
var pixel_heights: PackedInt32Array = PackedInt32Array()
var revisions: PackedInt64Array = PackedInt64Array()

var _index_by_id: Dictionary = {}
var _store_revision: int = 0


func _init() -> void:
	super(STORE_ID)


func add_image(entity_id: int, asset_id: String, pixel_size: Vector2i = DEFAULT_PIXEL_SIZE, instance_title: String = "") -> bool:
	if entity_id <= 0 or _index_by_id.has(entity_id):
		return false
	var clean_asset_id: String = asset_id.strip_edges()
	if clean_asset_id.is_empty():
		return false
	var safe_size: Vector2i = Vector2i(
		maxi(MIN_PIXEL_DIMENSION, pixel_size.x),
		maxi(MIN_PIXEL_DIMENSION, pixel_size.y)
	)
	var index: int = entity_ids.size()
	entity_ids.append(entity_id)
	asset_ids.append(clean_asset_id)
	instance_titles.append(instance_title.strip_edges().left(160))
	pixel_widths.append(safe_size.x)
	pixel_heights.append(safe_size.y)
	revisions.append(1)
	_index_by_id[entity_id] = index
	_store_revision += 1
	image_added.emit(entity_id)
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


func get_pixel_size(entity_id: int) -> Vector2i:
	var index: int = get_index(entity_id)
	if index < 0:
		return DEFAULT_PIXEL_SIZE
	return Vector2i(int(pixel_widths[index]), int(pixel_heights[index]))


func get_aspect_ratio(entity_id: int) -> float:
	var pixel_size: Vector2i = get_pixel_size(entity_id)
	return float(maxi(pixel_size.x, 1)) / float(maxi(pixel_size.y, 1))


func get_revision(entity_id: int) -> int:
	var index: int = get_index(entity_id)
	return int(revisions[index]) if index >= 0 else 0


func get_store_revision() -> int:
	return _store_revision


func set_pixel_size(entity_id: int, pixel_size: Vector2i) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	var safe_width: int = maxi(MIN_PIXEL_DIMENSION, pixel_size.x)
	var safe_height: int = maxi(MIN_PIXEL_DIMENSION, pixel_size.y)
	if int(pixel_widths[index]) == safe_width and int(pixel_heights[index]) == safe_height:
		return true
	pixel_widths[index] = safe_width
	pixel_heights[index] = safe_height
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
		"pixel_width": int(pixel_widths[index]),
		"pixel_height": int(pixel_heights[index]),
	}


func capture_record(entity_id: int) -> Dictionary:
	return get_record(entity_id)


func restore_record(record: Dictionary) -> bool:
	var entity_id: int = int(str(record.get("entity_id", "0")))
	var asset_id: String = str(record.get("asset_id", "")).strip_edges()
	if entity_id <= 0 or asset_id.is_empty():
		return false
	var pixel_size: Vector2i = Vector2i(
		maxi(MIN_PIXEL_DIMENSION, int(record.get("pixel_width", DEFAULT_PIXEL_SIZE.x))),
		maxi(MIN_PIXEL_DIMENSION, int(record.get("pixel_height", DEFAULT_PIXEL_SIZE.y)))
	)
	return add_image(entity_id, asset_id, pixel_size, str(record.get("instance_title", "")))


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
		pixel_widths[index] = pixel_widths[last_index]
		pixel_heights[index] = pixel_heights[last_index]
		revisions[index] = revisions[last_index]
		_index_by_id[int(entity_ids[index])] = index
	entity_ids.resize(last_index)
	asset_ids.resize(last_index)
	instance_titles.resize(last_index)
	pixel_widths.resize(last_index)
	pixel_heights.resize(last_index)
	revisions.resize(last_index)
	_index_by_id.erase(entity_id)
	_store_revision += 1
	image_removed.emit(entity_id)
	return true


func clear() -> void:
	if entity_ids.is_empty():
		return
	entity_ids = PackedInt64Array()
	asset_ids = PackedStringArray()
	instance_titles = PackedStringArray()
	pixel_widths = PackedInt32Array()
	pixel_heights = PackedInt32Array()
	revisions = PackedInt64Array()
	_index_by_id.clear()
	_store_revision += 1
	cleared.emit()


func serialize() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.resize(entity_ids.size())
	for index: int in range(entity_ids.size()):
		result[index] = {
			"entity_id": str(entity_ids[index]),
			"asset_id": asset_ids[index],
			"instance_title": instance_titles[index],
			"pixel_width": int(pixel_widths[index]),
			"pixel_height": int(pixel_heights[index]),
		}
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
	image_changed.emit(entity_id)
