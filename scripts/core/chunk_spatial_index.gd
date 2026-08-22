# SPDX-License-Identifier: GPL-3.0-or-later
class_name ChunkSpatialIndex
extends RefCounted

const DEFAULT_CHUNK_SIZE: float = 1024.0
const DEFAULT_MAX_CHUNKS_PER_ENTITY: int = 64

var chunk_size: float = DEFAULT_CHUNK_SIZE
var max_chunks_per_entity: int = DEFAULT_MAX_CHUNKS_PER_ENTITY

var _chunks: Dictionary = {}
var _chunk_keys_by_entity: Dictionary = {}
var _bounds_by_entity: Dictionary = {}
var _oversized_entities: Dictionary = {}
var _revision: int = 0


func _init(new_chunk_size: float = DEFAULT_CHUNK_SIZE, new_max_chunks_per_entity: int = DEFAULT_MAX_CHUNKS_PER_ENTITY) -> void:
	chunk_size = maxf(new_chunk_size, 64.0)
	max_chunks_per_entity = maxi(new_max_chunks_per_entity, 1)


func insert(entity_id: int, bounds: Rect2) -> bool:
	if entity_id <= 0 or _bounds_by_entity.has(entity_id):
		return false
	_bounds_by_entity[entity_id] = bounds
	_index_entity(entity_id, bounds)
	_revision += 1
	return true


func update(entity_id: int, bounds: Rect2) -> bool:
	if not _bounds_by_entity.has(entity_id):
		return insert(entity_id, bounds)
	var previous_value: Variant = _bounds_by_entity[entity_id]
	var previous: Rect2 = _rect_from_variant(previous_value)
	if previous == bounds:
		return true
	_remove_membership(entity_id)
	_bounds_by_entity[entity_id] = bounds
	_index_entity(entity_id, bounds)
	_revision += 1
	return true


func remove(entity_id: int) -> bool:
	if not _bounds_by_entity.has(entity_id):
		return false
	_remove_membership(entity_id)
	_bounds_by_entity.erase(entity_id)
	_revision += 1
	return true


func query_rect(area: Rect2) -> PackedInt64Array:
	var unique: Dictionary = {}
	var keys: Array[Vector2i] = _rect_to_chunk_keys(area)
	for key: Vector2i in keys:
		var bucket_value: Variant = _chunks.get(key)
		if bucket_value is Dictionary:
			var bucket: Dictionary = bucket_value as Dictionary
			for entity_key: Variant in bucket.keys():
				var entity_id: int = int(entity_key)
				var bounds_value: Variant = _bounds_by_entity.get(entity_id, Rect2())
				var bounds: Rect2 = _rect_from_variant(bounds_value)
				if bounds.intersects(area, true):
					unique[entity_id] = true
	for entity_key: Variant in _oversized_entities.keys():
		var oversized_id: int = int(entity_key)
		var oversized_value: Variant = _bounds_by_entity.get(oversized_id, Rect2())
		var oversized_bounds: Rect2 = _rect_from_variant(oversized_value)
		if oversized_bounds.intersects(area, true):
			unique[oversized_id] = true
	return _dictionary_keys_to_packed(unique)


func query_point(point: Vector2, margin: float = 0.0) -> PackedInt64Array:
	var area: Rect2 = Rect2(point - Vector2.ONE * margin, Vector2.ONE * maxf(margin * 2.0, 0.001))
	return query_rect(area)


func get_bounds(entity_id: int) -> Rect2:
	var value: Variant = _bounds_by_entity.get(entity_id, Rect2())
	return _rect_from_variant(value)


func get_revision() -> int:
	return _revision


func size() -> int:
	return _bounds_by_entity.size()


func clear() -> void:
	_chunks.clear()
	_chunk_keys_by_entity.clear()
	_bounds_by_entity.clear()
	_oversized_entities.clear()
	_revision += 1


func rebuild(model: BoardModel) -> void:
	clear()
	for entity_id: int in model.transforms.entity_ids:
		insert(entity_id, model.get_entity_bounds(entity_id))


func _index_entity(entity_id: int, bounds: Rect2) -> void:
	var keys: Array[Vector2i] = _rect_to_chunk_keys(bounds)
	if keys.size() > max_chunks_per_entity:
		_oversized_entities[entity_id] = true
		_chunk_keys_by_entity[entity_id] = []
		return
	var stored_keys: Array[Vector2i] = []
	for key: Vector2i in keys:
		var bucket: Dictionary = {}
		var bucket_value: Variant = _chunks.get(key)
		if bucket_value is Dictionary:
			bucket = bucket_value as Dictionary
		bucket[entity_id] = true
		_chunks[key] = bucket
		stored_keys.append(key)
	_chunk_keys_by_entity[entity_id] = stored_keys


func _remove_membership(entity_id: int) -> void:
	_oversized_entities.erase(entity_id)
	var keys_value: Variant = _chunk_keys_by_entity.get(entity_id, [])
	if keys_value is Array:
		var keys: Array = keys_value as Array
		for key_value: Variant in keys:
			if key_value is not Vector2i:
				continue
			var key: Vector2i = key_value as Vector2i
			var bucket_value: Variant = _chunks.get(key)
			if bucket_value is Dictionary:
				var bucket: Dictionary = bucket_value as Dictionary
				bucket.erase(entity_id)
				if bucket.is_empty():
					_chunks.erase(key)
				else:
					_chunks[key] = bucket
	_chunk_keys_by_entity.erase(entity_id)


func _rect_to_chunk_keys(bounds: Rect2) -> Array[Vector2i]:
	var normalized: Rect2 = bounds.abs()
	var end_point: Vector2 = normalized.end
	if normalized.size.x <= 0.0:
		end_point.x = normalized.position.x
	if normalized.size.y <= 0.0:
		end_point.y = normalized.position.y
	var min_key: Vector2i = _world_to_chunk(normalized.position)
	var max_key: Vector2i = _world_to_chunk(end_point)
	var result: Array[Vector2i] = []
	for y: int in range(min_key.y, max_key.y + 1):
		for x: int in range(min_key.x, max_key.x + 1):
			result.append(Vector2i(x, y))
	return result


func _world_to_chunk(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / chunk_size), floori(point.y / chunk_size))


func _dictionary_keys_to_packed(source: Dictionary) -> PackedInt64Array:
	var result: PackedInt64Array = PackedInt64Array()
	result.resize(source.size())
	var index: int = 0
	for key: Variant in source.keys():
		result[index] = int(key)
		index += 1
	return result


func _rect_from_variant(value: Variant) -> Rect2:
	if value is Rect2:
		return value as Rect2
	return Rect2()
