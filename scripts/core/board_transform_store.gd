# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardTransformStore
extends RefCounted

signal transform_added(entity_id: int)
signal transform_changed(entity_id: int)
signal transform_removed(entity_id: int)
signal cleared

const FLAG_VISIBLE: int = 1
const FLAG_LOCKED: int = 2

var entity_ids: PackedInt64Array = PackedInt64Array()
var positions: PackedVector2Array = PackedVector2Array()
var sizes: PackedVector2Array = PackedVector2Array()
var rotations: PackedFloat32Array = PackedFloat32Array()
var z_orders: PackedInt32Array = PackedInt32Array()
var flags: PackedInt32Array = PackedInt32Array()
var revisions: PackedInt64Array = PackedInt64Array()

var _index_by_id: Dictionary = {}
var _store_revision: int = 0
var _max_z_order: int = 0
var _max_z_dirty: bool = false


func add(
	entity_id: int,
	position: Vector2,
	size: Vector2,
	rotation: float = 0.0,
	z_order: int = 0,
	entity_flags: int = FLAG_VISIBLE
) -> bool:
	if entity_id <= 0 or _index_by_id.has(entity_id):
		return false
	var index: int = entity_ids.size()
	entity_ids.append(entity_id)
	positions.append(position)
	sizes.append(Vector2(maxf(size.x, 0.0), maxf(size.y, 0.0)))
	rotations.append(rotation)
	z_orders.append(z_order)
	_max_z_order = maxi(_max_z_order, z_order)
	flags.append(entity_flags)
	revisions.append(1)
	_index_by_id[entity_id] = index
	_store_revision += 1
	transform_added.emit(entity_id)
	return true


func remove(entity_id: int) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	var removed_z_order: int = int(z_orders[index])
	var last_index: int = entity_ids.size() - 1
	if index != last_index:
		var moved_id: int = int(entity_ids[last_index])
		entity_ids[index] = entity_ids[last_index]
		positions[index] = positions[last_index]
		sizes[index] = sizes[last_index]
		rotations[index] = rotations[last_index]
		z_orders[index] = z_orders[last_index]
		flags[index] = flags[last_index]
		revisions[index] = revisions[last_index]
		_index_by_id[moved_id] = index
	entity_ids.resize(last_index)
	positions.resize(last_index)
	sizes.resize(last_index)
	rotations.resize(last_index)
	z_orders.resize(last_index)
	flags.resize(last_index)
	revisions.resize(last_index)
	_index_by_id.erase(entity_id)
	if removed_z_order == _max_z_order:
		_max_z_dirty = true
	_store_revision += 1
	transform_removed.emit(entity_id)
	return true


func contains(entity_id: int) -> bool:
	return _index_by_id.has(entity_id)


func size() -> int:
	return entity_ids.size()


func get_index(entity_id: int) -> int:
	var value: Variant = _index_by_id.get(entity_id, -1)
	return int(value)


func get_bounds(entity_id: int) -> Rect2:
	var index: int = get_index(entity_id)
	if index < 0:
		return Rect2()
	return Rect2(positions[index], sizes[index])


func get_position(entity_id: int) -> Vector2:
	var index: int = get_index(entity_id)
	return positions[index] if index >= 0 else Vector2.ZERO


func get_size(entity_id: int) -> Vector2:
	var index: int = get_index(entity_id)
	return sizes[index] if index >= 0 else Vector2.ZERO


func get_rotation(entity_id: int) -> float:
	var index: int = get_index(entity_id)
	return float(rotations[index]) if index >= 0 else 0.0


func get_z_order(entity_id: int) -> int:
	var index: int = get_index(entity_id)
	return int(z_orders[index]) if index >= 0 else 0


func get_max_z_order() -> int:
	if not _max_z_dirty:
		return _max_z_order
	_max_z_order = 0
	for value: int in z_orders:
		_max_z_order = maxi(_max_z_order, value)
	_max_z_dirty = false
	return _max_z_order


func get_flags(entity_id: int) -> int:
	var index: int = get_index(entity_id)
	return int(flags[index]) if index >= 0 else 0


func get_revision(entity_id: int) -> int:
	var index: int = get_index(entity_id)
	return int(revisions[index]) if index >= 0 else 0


func get_store_revision() -> int:
	return _store_revision


func set_transform(entity_id: int, position: Vector2, size: Vector2, rotation: float) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	var safe_size: Vector2 = Vector2(maxf(size.x, 0.0), maxf(size.y, 0.0))
	if positions[index].is_equal_approx(position) and sizes[index].is_equal_approx(safe_size) and is_equal_approx(rotations[index], rotation):
		return true
	positions[index] = position
	sizes[index] = safe_size
	rotations[index] = rotation
	_touch(index, entity_id)
	return true


func set_position(entity_id: int, position: Vector2) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	if positions[index].is_equal_approx(position):
		return true
	positions[index] = position
	_touch(index, entity_id)
	return true


func set_z_order(entity_id: int, z_order: int) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	var previous_z_order: int = int(z_orders[index])
	if previous_z_order == z_order:
		return true
	z_orders[index] = z_order
	if z_order > _max_z_order:
		_max_z_order = z_order
		_max_z_dirty = false
	elif previous_z_order == _max_z_order and z_order < previous_z_order:
		_max_z_dirty = true
	_touch(index, entity_id)
	return true


func set_flags(entity_id: int, entity_flags: int) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	if flags[index] == entity_flags:
		return true
	flags[index] = entity_flags
	_touch(index, entity_id)
	return true


func is_visible(entity_id: int) -> bool:
	return (get_flags(entity_id) & FLAG_VISIBLE) != 0


func is_locked(entity_id: int) -> bool:
	return (get_flags(entity_id) & FLAG_LOCKED) != 0


func serialize_entries(registry: BoardEntityRegistry) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.resize(entity_ids.size())
	for index: int in range(entity_ids.size()):
		var entity_id: int = int(entity_ids[index])
		result[index] = {
			"id": str(entity_id),
			"type": str(registry.get_type(entity_id)),
			"position": {"x": positions[index].x, "y": positions[index].y},
			"size": {"x": sizes[index].x, "y": sizes[index].y},
			"rotation": float(rotations[index]),
			"z_order": int(z_orders[index]),
			"flags": int(flags[index]),
		}
	return result


func clear() -> void:
	entity_ids = PackedInt64Array()
	positions = PackedVector2Array()
	sizes = PackedVector2Array()
	rotations = PackedFloat32Array()
	z_orders = PackedInt32Array()
	flags = PackedInt32Array()
	revisions = PackedInt64Array()
	_index_by_id.clear()
	_max_z_order = 0
	_max_z_dirty = false
	_store_revision += 1
	cleared.emit()


func _touch(index: int, entity_id: int) -> void:
	revisions[index] = revisions[index] + 1
	_store_revision += 1
	transform_changed.emit(entity_id)
