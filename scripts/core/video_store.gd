# SPDX-License-Identifier: GPL-3.0-or-later
class_name VideoStore
extends BoardDataStore

signal video_added(entity_id: int)
signal video_changed(entity_id: int)
signal video_removed(entity_id: int)
signal cleared

const STORE_ID: StringName = &"videos"
const DEFAULT_PIXEL_SIZE: Vector2i = Vector2i(1280, 720)
const MIN_PIXEL_DIMENSION: int = 1

const FLAG_LOOP: int = 1 << 0
const FLAG_MUTED: int = 1 << 1

var entity_ids: PackedInt64Array = PackedInt64Array()
var asset_ids: PackedStringArray = PackedStringArray()
var instance_titles: PackedStringArray = PackedStringArray()
var pixel_widths: PackedInt32Array = PackedInt32Array()
var pixel_heights: PackedInt32Array = PackedInt32Array()
var duration_msec: PackedInt64Array = PackedInt64Array()
var playback_flags: PackedInt32Array = PackedInt32Array()
var revisions: PackedInt64Array = PackedInt64Array()

var _index_by_id: Dictionary = {}
var _store_revision: int = 0


func _init() -> void:
	super(STORE_ID)


func add_video(
	entity_id: int,
	asset_id: String,
	pixel_size: Vector2i = DEFAULT_PIXEL_SIZE,
	duration_seconds: float = 0.0,
	flags: int = 0,
	instance_title: String = ""
) -> bool:
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
	duration_msec.append(maxi(0, int(round(duration_seconds * 1000.0))))
	playback_flags.append(flags)
	revisions.append(1)
	_index_by_id[entity_id] = index
	_store_revision += 1
	video_added.emit(entity_id)
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
	var size_value: Vector2i = get_pixel_size(entity_id)
	return float(maxi(1, size_value.x)) / float(maxi(1, size_value.y))


func get_duration(entity_id: int) -> float:
	var index: int = get_index(entity_id)
	return float(duration_msec[index]) / 1000.0 if index >= 0 else 0.0


func get_flags(entity_id: int) -> int:
	var index: int = get_index(entity_id)
	return int(playback_flags[index]) if index >= 0 else 0


func get_store_revision() -> int:
	return _store_revision


func set_flags(entity_id: int, flags: int) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	if int(playback_flags[index]) == flags:
		return true
	playback_flags[index] = flags
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
		"duration_msec": str(duration_msec[index]),
		"playback_flags": int(playback_flags[index]),
	}


func capture_record(entity_id: int) -> Dictionary:
	return get_record(entity_id)


func restore_record(record: Dictionary) -> bool:
	var entity_id: int = int(str(record.get("entity_id", "0")))
	var asset_id: String = str(record.get("asset_id", "")).strip_edges()
	if entity_id <= 0 or asset_id.is_empty():
		return false
	var size_value: Vector2i = Vector2i(
		maxi(MIN_PIXEL_DIMENSION, int(record.get("pixel_width", DEFAULT_PIXEL_SIZE.x))),
		maxi(MIN_PIXEL_DIMENSION, int(record.get("pixel_height", DEFAULT_PIXEL_SIZE.y)))
	)
	var duration_seconds: float = float(int(str(record.get("duration_msec", "0")))) / 1000.0
	var flags: int = int(record.get("playback_flags", 0))
	return add_video(entity_id, asset_id, size_value, duration_seconds, flags, str(record.get("instance_title", "")))


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
		duration_msec[index] = duration_msec[last_index]
		playback_flags[index] = playback_flags[last_index]
		revisions[index] = revisions[last_index]
		_index_by_id[int(entity_ids[index])] = index
	entity_ids.resize(last_index)
	asset_ids.resize(last_index)
	instance_titles.resize(last_index)
	pixel_widths.resize(last_index)
	pixel_heights.resize(last_index)
	duration_msec.resize(last_index)
	playback_flags.resize(last_index)
	revisions.resize(last_index)
	_index_by_id.erase(entity_id)
	_store_revision += 1
	video_removed.emit(entity_id)
	return true


func clear() -> void:
	if entity_ids.is_empty():
		return
	entity_ids = PackedInt64Array()
	asset_ids = PackedStringArray()
	instance_titles = PackedStringArray()
	pixel_widths = PackedInt32Array()
	pixel_heights = PackedInt32Array()
	duration_msec = PackedInt64Array()
	playback_flags = PackedInt32Array()
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
			"duration_msec": str(duration_msec[index]),
			"playback_flags": int(playback_flags[index]),
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
	video_changed.emit(entity_id)
