# SPDX-License-Identifier: GPL-3.0-or-later
class_name ConnectorStore
extends BoardDataStore

signal connector_added(entity_id: int)
signal connector_changed(entity_id: int)
signal connector_removed(entity_id: int)
signal cleared

const STORE_ID: StringName = &"connectors"
const DEFAULT_COLOR: Color = Color("#2f8f5b")
const DEFAULT_WIDTH: float = 2.4
const DIRECTION_NONE: int = ConnectorGeometry.DIRECTION_NONE
const DIRECTION_FORWARD: int = ConnectorGeometry.DIRECTION_FORWARD
const DIRECTION_REVERSE: int = ConnectorGeometry.DIRECTION_REVERSE
const DIRECTION_BOTH: int = ConnectorGeometry.DIRECTION_BOTH
const DEFAULT_DIRECTION: int = ConnectorGeometry.DEFAULT_DIRECTION
const ROUTER_COMPACT_MINIMUM_POINTS: int = 1024

var entity_ids: PackedInt64Array = PackedInt64Array()
var source_entity_ids: PackedInt64Array = PackedInt64Array()
var target_entity_ids: PackedInt64Array = PackedInt64Array()
var source_anchors: PackedInt32Array = PackedInt32Array()
var target_anchors: PackedInt32Array = PackedInt32Array()
var router_point_offsets: PackedInt32Array = PackedInt32Array()
var router_point_counts: PackedInt32Array = PackedInt32Array()
var colors: PackedColorArray = PackedColorArray()
var widths: PackedFloat32Array = PackedFloat32Array()
var directions: PackedInt32Array = PackedInt32Array()
var revisions: PackedInt64Array = PackedInt64Array()

var _router_point_pool: PackedVector2Array = PackedVector2Array()
var _router_point_garbage: int = 0
var _index_by_id: Dictionary = {}
var _connector_ids_by_endpoint: Dictionary = {}
var _store_revision: int = 0


func _init() -> void:
	super(STORE_ID)


func add_connector(
	entity_id: int,
	source_entity_id: int,
	target_entity_id: int,
	source_anchor: int,
	target_anchor: int,
	color: Color = DEFAULT_COLOR,
	width: float = DEFAULT_WIDTH,
	router_points: PackedVector2Array = PackedVector2Array(),
	direction: int = DEFAULT_DIRECTION
) -> bool:
	if (
		entity_id <= 0
		or source_entity_id <= 0
		or target_entity_id <= 0
		or source_entity_id == target_entity_id
		or _index_by_id.has(entity_id)
	):
		return false
	var index: int = entity_ids.size()
	var router_offset: int = _append_router_points(router_points)
	entity_ids.append(entity_id)
	source_entity_ids.append(source_entity_id)
	target_entity_ids.append(target_entity_id)
	source_anchors.append(clampi(source_anchor, ConnectorGeometry.ANCHOR_TOP, ConnectorGeometry.ANCHOR_LEFT))
	target_anchors.append(clampi(target_anchor, ConnectorGeometry.ANCHOR_TOP, ConnectorGeometry.ANCHOR_LEFT))
	router_point_offsets.append(router_offset)
	router_point_counts.append(router_points.size())
	colors.append(color)
	widths.append(maxf(width, 0.5))
	directions.append(clampi(direction, DIRECTION_NONE, DIRECTION_BOTH))
	revisions.append(1)
	_index_by_id[entity_id] = index
	_add_endpoint_membership(source_entity_id, entity_id)
	_add_endpoint_membership(target_entity_id, entity_id)
	_store_revision += 1
	connector_added.emit(entity_id)
	return true


func contains(entity_id: int) -> bool:
	return _index_by_id.has(entity_id)


func size() -> int:
	return entity_ids.size()


func get_index(entity_id: int) -> int:
	return int(_index_by_id.get(entity_id, -1))


func get_store_revision() -> int:
	return _store_revision


func get_source_entity_id(entity_id: int) -> int:
	var index: int = get_index(entity_id)
	return int(source_entity_ids[index]) if index >= 0 else 0


func get_target_entity_id(entity_id: int) -> int:
	var index: int = get_index(entity_id)
	return int(target_entity_ids[index]) if index >= 0 else 0


func get_source_anchor(entity_id: int) -> int:
	var index: int = get_index(entity_id)
	return int(source_anchors[index]) if index >= 0 else ConnectorGeometry.ANCHOR_RIGHT


func get_target_anchor(entity_id: int) -> int:
	var index: int = get_index(entity_id)
	return int(target_anchors[index]) if index >= 0 else ConnectorGeometry.ANCHOR_LEFT


func get_router_points(entity_id: int) -> PackedVector2Array:
	var index: int = get_index(entity_id)
	if index < 0:
		return PackedVector2Array()
	var offset: int = int(router_point_offsets[index])
	var count: int = int(router_point_counts[index])
	var result: PackedVector2Array = PackedVector2Array()
	if count <= 0 or offset < 0 or offset + count > _router_point_pool.size():
		return result
	result.resize(count)
	for point_index: int in range(count):
		result[point_index] = _router_point_pool[offset + point_index]
	return result


func get_color(entity_id: int) -> Color:
	var index: int = get_index(entity_id)
	return colors[index] if index >= 0 else DEFAULT_COLOR


func get_width(entity_id: int) -> float:
	var index: int = get_index(entity_id)
	return float(widths[index]) if index >= 0 else DEFAULT_WIDTH


func get_direction(entity_id: int) -> int:
	var index: int = get_index(entity_id)
	return int(directions[index]) if index >= 0 else DEFAULT_DIRECTION


func set_color(entity_id: int, color: Color) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	if colors[index] == color:
		return true
	colors[index] = color
	_touch(index, entity_id)
	return true


func set_direction(entity_id: int, direction: int) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	var safe_direction: int = clampi(direction, DIRECTION_NONE, DIRECTION_BOTH)
	if int(directions[index]) == safe_direction:
		return true
	directions[index] = safe_direction
	_touch(index, entity_id)
	return true


func get_attached_connector_ids(endpoint_entity_id: int) -> PackedInt64Array:
	var result: PackedInt64Array = PackedInt64Array()
	var value: Variant = _connector_ids_by_endpoint.get(endpoint_entity_id)
	if value is not Dictionary:
		return result
	var membership: Dictionary = value as Dictionary
	result.resize(membership.size())
	var write_index: int = 0
	for connector_key: Variant in membership.keys():
		result[write_index] = int(connector_key)
		write_index += 1
	return result


func set_endpoints(
	entity_id: int,
	source_entity_id: int,
	target_entity_id: int,
	source_anchor: int,
	target_anchor: int
) -> bool:
	var index: int = get_index(entity_id)
	if index < 0 or source_entity_id <= 0 or target_entity_id <= 0 or source_entity_id == target_entity_id:
		return false
	var old_source: int = int(source_entity_ids[index])
	var old_target: int = int(target_entity_ids[index])
	var safe_source_anchor: int = clampi(source_anchor, ConnectorGeometry.ANCHOR_TOP, ConnectorGeometry.ANCHOR_LEFT)
	var safe_target_anchor: int = clampi(target_anchor, ConnectorGeometry.ANCHOR_TOP, ConnectorGeometry.ANCHOR_LEFT)
	if (
		old_source == source_entity_id
		and old_target == target_entity_id
		and int(source_anchors[index]) == safe_source_anchor
		and int(target_anchors[index]) == safe_target_anchor
	):
		return true
	if old_source != source_entity_id:
		_remove_endpoint_membership(old_source, entity_id)
		_add_endpoint_membership(source_entity_id, entity_id)
	if old_target != target_entity_id:
		_remove_endpoint_membership(old_target, entity_id)
		_add_endpoint_membership(target_entity_id, entity_id)
	source_entity_ids[index] = source_entity_id
	target_entity_ids[index] = target_entity_id
	source_anchors[index] = safe_source_anchor
	target_anchors[index] = safe_target_anchor
	_touch(index, entity_id)
	return true


func set_router_points(entity_id: int, router_points: PackedVector2Array) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	var previous: PackedVector2Array = get_router_points(entity_id)
	if previous == router_points:
		return true
	_router_point_garbage += int(router_point_counts[index])
	router_point_offsets[index] = _append_router_points(router_points)
	router_point_counts[index] = router_points.size()
	_touch(index, entity_id)
	_maybe_compact_router_pool()
	return true


func get_record(entity_id: int) -> Dictionary:
	var index: int = get_index(entity_id)
	if index < 0:
		return {}
	var serialized_points: Array[Dictionary] = []
	for point: Vector2 in get_router_points(entity_id):
		serialized_points.append({"x": point.x, "y": point.y})
	return {
		"entity_id": str(entity_ids[index]),
		"source_entity_id": str(source_entity_ids[index]),
		"target_entity_id": str(target_entity_ids[index]),
		"source_anchor": int(source_anchors[index]),
		"target_anchor": int(target_anchors[index]),
		"router_points": serialized_points,
		"color": colors[index].to_html(true),
		"width": float(widths[index]),
		"direction": int(directions[index]),
	}


func capture_record(entity_id: int) -> Dictionary:
	return get_record(entity_id)


func restore_record(record: Dictionary) -> bool:
	var entity_id: int = int(str(record.get("entity_id", "0")))
	var source_entity_id: int = int(str(record.get("source_entity_id", "0")))
	var target_entity_id: int = int(str(record.get("target_entity_id", "0")))
	var color: Color = _parse_color(record.get("color", ""), DEFAULT_COLOR)
	return add_connector(
		entity_id,
		source_entity_id,
		target_entity_id,
		int(record.get("source_anchor", ConnectorGeometry.ANCHOR_RIGHT)),
		int(record.get("target_anchor", ConnectorGeometry.ANCHOR_LEFT)),
		color,
		float(record.get("width", DEFAULT_WIDTH)),
		parse_router_points(record.get("router_points", [])),
		int(record.get("direction", DEFAULT_DIRECTION))
	)


func apply_record(entity_id: int, record: Dictionary) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		var restored: Dictionary = record.duplicate(true)
		restored["entity_id"] = str(entity_id)
		return restore_record(restored)
	var source_id: int = int(str(record.get("source_entity_id", source_entity_ids[index])))
	var target_id: int = int(str(record.get("target_entity_id", target_entity_ids[index])))
	if not set_endpoints(
		entity_id,
		source_id,
		target_id,
		int(record.get("source_anchor", source_anchors[index])),
		int(record.get("target_anchor", target_anchors[index]))
	):
		return false
	set_router_points(entity_id, parse_router_points(record.get("router_points", [])))
	var current_index: int = get_index(entity_id)
	if current_index < 0:
		return false
	var next_color: Color = _parse_color(record.get("color", ""), colors[current_index])
	var next_width: float = maxf(float(record.get("width", widths[current_index])), 0.5)
	var next_direction: int = clampi(int(record.get("direction", directions[current_index])), DIRECTION_NONE, DIRECTION_BOTH)
	if (
		colors[current_index] != next_color
		or not is_equal_approx(float(widths[current_index]), next_width)
		or int(directions[current_index]) != next_direction
	):
		colors[current_index] = next_color
		widths[current_index] = next_width
		directions[current_index] = next_direction
		_touch(current_index, entity_id)
	return true


func remap_record(record: Dictionary, id_map: Dictionary) -> Dictionary:
	var remapped: Dictionary = record.duplicate(true)
	var old_entity_id: int = int(str(record.get("entity_id", "0")))
	var old_source_id: int = int(str(record.get("source_entity_id", "0")))
	var old_target_id: int = int(str(record.get("target_entity_id", "0")))
	remapped["entity_id"] = str(int(id_map.get(old_entity_id, old_entity_id)))
	remapped["source_entity_id"] = str(int(id_map.get(old_source_id, old_source_id)))
	remapped["target_entity_id"] = str(int(id_map.get(old_target_id, old_target_id)))
	return remapped


func remove(entity_id: int) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	var source_id: int = int(source_entity_ids[index])
	var target_id: int = int(target_entity_ids[index])
	_remove_endpoint_membership(source_id, entity_id)
	_remove_endpoint_membership(target_id, entity_id)
	_router_point_garbage += int(router_point_counts[index])
	var last_index: int = entity_ids.size() - 1
	if index != last_index:
		var moved_id: int = int(entity_ids[last_index])
		entity_ids[index] = entity_ids[last_index]
		source_entity_ids[index] = source_entity_ids[last_index]
		target_entity_ids[index] = target_entity_ids[last_index]
		source_anchors[index] = source_anchors[last_index]
		target_anchors[index] = target_anchors[last_index]
		router_point_offsets[index] = router_point_offsets[last_index]
		router_point_counts[index] = router_point_counts[last_index]
		colors[index] = colors[last_index]
		widths[index] = widths[last_index]
		directions[index] = directions[last_index]
		revisions[index] = revisions[last_index]
		_index_by_id[moved_id] = index
	entity_ids.resize(last_index)
	source_entity_ids.resize(last_index)
	target_entity_ids.resize(last_index)
	source_anchors.resize(last_index)
	target_anchors.resize(last_index)
	router_point_offsets.resize(last_index)
	router_point_counts.resize(last_index)
	colors.resize(last_index)
	widths.resize(last_index)
	directions.resize(last_index)
	revisions.resize(last_index)
	_index_by_id.erase(entity_id)
	_store_revision += 1
	connector_removed.emit(entity_id)
	_maybe_compact_router_pool()
	return true


func clear() -> void:
	entity_ids = PackedInt64Array()
	source_entity_ids = PackedInt64Array()
	target_entity_ids = PackedInt64Array()
	source_anchors = PackedInt32Array()
	target_anchors = PackedInt32Array()
	router_point_offsets = PackedInt32Array()
	router_point_counts = PackedInt32Array()
	colors = PackedColorArray()
	widths = PackedFloat32Array()
	directions = PackedInt32Array()
	revisions = PackedInt64Array()
	_router_point_pool = PackedVector2Array()
	_router_point_garbage = 0
	_index_by_id.clear()
	_connector_ids_by_endpoint.clear()
	_store_revision += 1
	cleared.emit()


func serialize() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.resize(entity_ids.size())
	for index: int in range(entity_ids.size()):
		result[index] = get_record(int(entity_ids[index]))
	return result


func deserialize(records: Array) -> void:
	clear()
	for raw_record: Variant in records:
		if raw_record is Dictionary:
			restore_record(raw_record as Dictionary)
	_store_revision = 0


func _append_router_points(points: PackedVector2Array) -> int:
	var offset: int = _router_point_pool.size()
	for point: Vector2 in points:
		_router_point_pool.append(point)
	return offset


func _maybe_compact_router_pool() -> void:
	if (
		_router_point_pool.size() < ROUTER_COMPACT_MINIMUM_POINTS
		or _router_point_garbage * 2 < _router_point_pool.size()
	):
		return
	var compacted: PackedVector2Array = PackedVector2Array()
	for index: int in range(entity_ids.size()):
		var points: PackedVector2Array = get_router_points(int(entity_ids[index]))
		router_point_offsets[index] = compacted.size()
		router_point_counts[index] = points.size()
		for point: Vector2 in points:
			compacted.append(point)
	_router_point_pool = compacted
	_router_point_garbage = 0


func _add_endpoint_membership(endpoint_entity_id: int, connector_entity_id: int) -> void:
	var membership: Dictionary = {}
	var value: Variant = _connector_ids_by_endpoint.get(endpoint_entity_id)
	if value is Dictionary:
		membership = value as Dictionary
	membership[connector_entity_id] = true
	_connector_ids_by_endpoint[endpoint_entity_id] = membership


func _remove_endpoint_membership(endpoint_entity_id: int, connector_entity_id: int) -> void:
	var value: Variant = _connector_ids_by_endpoint.get(endpoint_entity_id)
	if value is not Dictionary:
		return
	var membership: Dictionary = value as Dictionary
	membership.erase(connector_entity_id)
	if membership.is_empty():
		_connector_ids_by_endpoint.erase(endpoint_entity_id)
	else:
		_connector_ids_by_endpoint[endpoint_entity_id] = membership


func _touch(index: int, entity_id: int) -> void:
	revisions[index] = revisions[index] + 1
	_store_revision += 1
	connector_changed.emit(entity_id)


static func parse_router_points(value: Variant) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	if value is not Array:
		return result
	for raw_point: Variant in value as Array:
		if raw_point is Dictionary:
			var point_data: Dictionary = raw_point as Dictionary
			result.append(Vector2(float(point_data.get("x", 0.0)), float(point_data.get("y", 0.0))))
		elif raw_point is Vector2:
			result.append(raw_point as Vector2)
	return result


func _parse_color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value as Color
	var text: String = str(value)
	return Color(text) if not text.is_empty() and Color.html_is_valid(text) else fallback
