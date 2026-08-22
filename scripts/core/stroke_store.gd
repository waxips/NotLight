# SPDX-License-Identifier: GPL-3.0-or-later
class_name StrokeStore
extends BoardDataStore

signal stroke_added(entity_id: int)
signal stroke_changed(entity_id: int)
signal stroke_removed(entity_id: int)
signal cleared

const STORE_ID: StringName = &"strokes"
const STYLE_PEN: int = 0
const STYLE_HIGHLIGHTER: int = 1
const STYLE_PENCIL: int = 2
const STYLE_SPRAY: int = 3
const MIN_WIDTH: float = 0.5
const MAX_WIDTH: float = 96.0
const MIN_SPRAY_SPREAD: float = 0.45
const MAX_SPRAY_SPREAD: float = 2.5
const BINARY_FORMAT: String = "notlight.stroke_points"
const BINARY_VERSION: int = 1

var entity_ids: PackedInt64Array = PackedInt64Array()
var style_ids: PackedInt32Array = PackedInt32Array()
var colors: PackedColorArray = PackedColorArray()
var base_widths: PackedFloat32Array = PackedFloat32Array()
var spray_spreads: PackedFloat32Array = PackedFloat32Array()
var original_widths: PackedFloat32Array = PackedFloat32Array()
var original_heights: PackedFloat32Array = PackedFloat32Array()
var point_offsets: PackedInt32Array = PackedInt32Array()
var point_counts: PackedInt32Array = PackedInt32Array()
var revisions: PackedInt64Array = PackedInt64Array()

var _point_arena: PackedVector2Array = PackedVector2Array()
var _index_by_id: Dictionary = {}
var _store_revision: int = 0


func _init() -> void:
	super(STORE_ID)


func add_stroke(entity_id: int, points: PackedVector2Array, style_id: int, color: Color, width: float, original_size: Vector2, spray_spread: float = 1.0) -> bool:
	if entity_id <= 0 or _index_by_id.has(entity_id) or points.is_empty():
		return false
	var offset: int = _point_arena.size()
	_point_arena.append_array(points)
	var index: int = entity_ids.size()
	entity_ids.append(entity_id)
	style_ids.append(clampi(style_id, STYLE_PEN, STYLE_SPRAY))
	colors.append(color)
	base_widths.append(clampf(width, MIN_WIDTH, MAX_WIDTH))
	spray_spreads.append(clampf(spray_spread, MIN_SPRAY_SPREAD, MAX_SPRAY_SPREAD))
	original_widths.append(maxf(original_size.x, 0.001))
	original_heights.append(maxf(original_size.y, 0.001))
	point_offsets.append(offset)
	point_counts.append(points.size())
	revisions.append(1)
	_index_by_id[entity_id] = index
	_store_revision += 1
	stroke_added.emit(entity_id)
	return true


func contains(entity_id: int) -> bool:
	return _index_by_id.has(entity_id)


func size() -> int:
	return entity_ids.size()


func get_index(entity_id: int) -> int:
	return int(_index_by_id.get(entity_id, -1))


func get_style_id(entity_id: int) -> int:
	var index: int = get_index(entity_id)
	return int(style_ids[index]) if index >= 0 else STYLE_PEN


func get_color(entity_id: int) -> Color:
	var index: int = get_index(entity_id)
	return colors[index] if index >= 0 else Color("#24885a")


func get_base_width(entity_id: int) -> float:
	var index: int = get_index(entity_id)
	return float(base_widths[index]) if index >= 0 else 4.0


func get_spray_spread(entity_id: int) -> float:
	var index: int = get_index(entity_id)
	return float(spray_spreads[index]) if index >= 0 else 1.0


func get_original_size(entity_id: int) -> Vector2:
	var index: int = get_index(entity_id)
	if index < 0:
		return Vector2.ONE
	return Vector2(maxf(float(original_widths[index]), 0.001), maxf(float(original_heights[index]), 0.001))


static func editor_max_width_for_style(style_id: int) -> float:
	match clampi(style_id, STYLE_PEN, STYLE_SPRAY):
		STYLE_HIGHLIGHTER:
			return 18.0
		STYLE_PENCIL:
			return 12.0
		STYLE_SPRAY:
			return 16.0
		_:
			return 18.0


func get_revision(entity_id: int) -> int:
	var index: int = get_index(entity_id)
	return int(revisions[index]) if index >= 0 else 0


func get_store_revision() -> int:
	return _store_revision


func get_point_count(entity_id: int) -> int:
	var index: int = get_index(entity_id)
	return int(point_counts[index]) if index >= 0 else 0


func get_local_points(entity_id: int) -> PackedVector2Array:
	var index: int = get_index(entity_id)
	if index < 0:
		return PackedVector2Array()
	var offset: int = int(point_offsets[index])
	var count: int = int(point_counts[index])
	if offset < 0 or count <= 0 or offset + count > _point_arena.size():
		return PackedVector2Array()
	return _point_arena.slice(offset, offset + count)


func get_local_points_decimated(entity_id: int, maximum_points: int) -> PackedVector2Array:
	var index: int = get_index(entity_id)
	if index < 0:
		return PackedVector2Array()
	var offset: int = int(point_offsets[index])
	var count: int = int(point_counts[index])
	if offset < 0 or count <= 0 or offset + count > _point_arena.size():
		return PackedVector2Array()
	var limit: int = maxi(2, maximum_points)
	if count <= limit:
		return _point_arena.slice(offset, offset + count)
	# Rendering LOD frequently needs only a bounded approximation of a dense
	# stroke. Sampling directly from the arena avoids first allocating/copying the
	# complete source polyline just to throw most of it away on the next line.
	var result: PackedVector2Array = PackedVector2Array()
	result.resize(limit)
	var last_source_index: int = count - 1
	var last_target_index: int = limit - 1
	for target_index: int in range(limit):
		var local_source_index: int = int(round(
			float(target_index) * float(last_source_index) / float(last_target_index)
		))
		result[target_index] = _point_arena[offset + clampi(local_source_index, 0, last_source_index)]
	return result


func get_world_points(entity_id: int, bounds: Rect2) -> PackedVector2Array:
	var index: int = get_index(entity_id)
	if index < 0:
		return PackedVector2Array()
	return StrokeGeometry.transformed_points(
		get_local_points(entity_id),
		Vector2(float(original_widths[index]), float(original_heights[index])),
		bounds
	)


func get_effective_width(entity_id: int, bounds: Rect2) -> float:
	var index: int = get_index(entity_id)
	if index < 0:
		return 1.0
	var original: Vector2 = Vector2(maxf(float(original_widths[index]), 0.001), maxf(float(original_heights[index]), 0.001))
	var scale_x: float = bounds.size.x / original.x
	var scale_y: float = bounds.size.y / original.y
	var scale: float = sqrt(maxf(0.0001, absf(scale_x * scale_y)))
	return clampf(float(base_widths[index]) * scale, MIN_WIDTH, MAX_WIDTH * 8.0)


func get_visual_width(entity_id: int, bounds: Rect2) -> float:
	var style_id: int = get_style_id(entity_id)
	var result: float = get_effective_width(entity_id, bounds) * style_width_multiplier(style_id)
	if style_id == STYLE_SPRAY:
		result *= get_spray_spread(entity_id)
	return result


static func style_width_multiplier(style_id: int) -> float:
	match style_id:
		STYLE_HIGHLIGHTER:
			return 2.2
		STYLE_PENCIL:
			return 1.7
		STYLE_SPRAY:
			return 1.8
		_:
			return 1.0


static func visual_padding_for(style_id: int, width: float, spray_spread: float = 1.0) -> float:
	var clean_style: int = clampi(style_id, STYLE_PEN, STYLE_SPRAY)
	var clean_width: float = clampf(width, MIN_WIDTH, MAX_WIDTH)
	var spread_multiplier: float = clampf(spray_spread, MIN_SPRAY_SPREAD, MAX_SPRAY_SPREAD) if clean_style == STYLE_SPRAY else 1.0
	return maxf(4.0, clean_width * style_width_multiplier(clean_style) * 0.62 * spread_multiplier)


static func recommended_bounds_for_world_points(points: PackedVector2Array, style_id: int, width: float, spray_spread: float = 1.0) -> Rect2:
	if points.is_empty():
		return Rect2()
	var result: Rect2 = StrokeGeometry.bounds_for_points(points, visual_padding_for(style_id, width, spray_spread))
	result.size.x = maxf(result.size.x, 1.0)
	result.size.y = maxf(result.size.y, 1.0)
	return result


func apply_style_with_world_geometry(
	entity_id: int,
	style_id: int,
	color: Color,
	width: float,
	spray_spread: float,
	world_points: PackedVector2Array,
	new_bounds: Rect2
) -> bool:
	var index: int = get_index(entity_id)
	if index < 0 or world_points.size() != int(point_counts[index]) or world_points.is_empty():
		return false
	var clean_style: int = clampi(style_id, STYLE_PEN, STYLE_SPRAY)
	var clean_width: float = clampf(width, MIN_WIDTH, MAX_WIDTH)
	var clean_spread: float = clampf(spray_spread, MIN_SPRAY_SPREAD, MAX_SPRAY_SPREAD)
	var safe_bounds: Rect2 = new_bounds
	safe_bounds.size.x = maxf(safe_bounds.size.x, 1.0)
	safe_bounds.size.y = maxf(safe_bounds.size.y, 1.0)
	var local_points: PackedVector2Array = StrokeGeometry.to_local_points(world_points, safe_bounds)
	var offset: int = int(point_offsets[index])
	if offset < 0 or offset + local_points.size() > _point_arena.size():
		return false
	for point_index: int in range(local_points.size()):
		_point_arena[offset + point_index] = local_points[point_index]
	style_ids[index] = clean_style
	colors[index] = color
	base_widths[index] = clean_width
	spray_spreads[index] = clean_spread
	original_widths[index] = safe_bounds.size.x
	original_heights[index] = safe_bounds.size.y
	_touch(index, entity_id)
	return true


func set_style_properties(entity_id: int, style_id: int, color: Color, width: float, spray_spread: float = 1.0) -> bool:
	var index: int = get_index(entity_id)
	if index < 0:
		return false
	var clean_style: int = clampi(style_id, STYLE_PEN, STYLE_SPRAY)
	var clean_width: float = clampf(width, MIN_WIDTH, MAX_WIDTH)
	var clean_spread: float = clampf(spray_spread, MIN_SPRAY_SPREAD, MAX_SPRAY_SPREAD)
	if int(style_ids[index]) == clean_style and colors[index] == color and is_equal_approx(float(base_widths[index]), clean_width) and is_equal_approx(float(spray_spreads[index]), clean_spread):
		return true
	style_ids[index] = clean_style
	colors[index] = color
	base_widths[index] = clean_width
	spray_spreads[index] = clean_spread
	_touch(index, entity_id)
	return true


func hit_test_point(entity_id: int, bounds: Rect2, point: Vector2, tolerance: float) -> bool:
	var radius: float = maxf(2.5, get_visual_width(entity_id, bounds) * 0.5) + maxf(0.0, tolerance)
	return StrokeGeometry.point_hits_polyline(point, get_world_points(entity_id, bounds), radius)


func hit_test_segment(entity_id: int, bounds: Rect2, from_point: Vector2, to_point: Vector2, eraser_radius: float) -> bool:
	var radius: float = maxf(0.0, eraser_radius) + get_visual_width(entity_id, bounds) * 0.5
	return StrokeGeometry.segment_hits_polyline(from_point, to_point, get_world_points(entity_id, bounds), radius)


func capture_record(entity_id: int) -> Dictionary:
	var index: int = get_index(entity_id)
	if index < 0:
		return {}
	return {
		"entity_id": str(entity_id),
		"style_id": int(style_ids[index]),
		"color": colors[index].to_html(true),
		"width": float(base_widths[index]),
		"spray_spread": float(spray_spreads[index]),
		"original_width": float(original_widths[index]),
		"original_height": float(original_heights[index]),
		"points": get_local_points(entity_id),
	}


func restore_record(record: Dictionary) -> bool:
	var entity_id: int = int(str(record.get("entity_id", "0")))
	var points_value: Variant = record.get("points", PackedVector2Array())
	var points: PackedVector2Array = PackedVector2Array()
	if points_value is PackedVector2Array:
		points = points_value as PackedVector2Array
	if entity_id <= 0 or points.is_empty():
		return false
	return add_stroke(
		entity_id,
		points,
		int(record.get("style_id", STYLE_PEN)),
		Color.from_string(str(record.get("color", "#24885aff")), Color("#24885a")),
		float(record.get("width", 4.0)),
		Vector2(maxf(0.001, float(record.get("original_width", 1.0))), maxf(0.001, float(record.get("original_height", 1.0)))),
		float(record.get("spray_spread", 1.0))
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
	var last: int = entity_ids.size() - 1
	if index != last:
		entity_ids[index] = entity_ids[last]
		style_ids[index] = style_ids[last]
		colors[index] = colors[last]
		base_widths[index] = base_widths[last]
		spray_spreads[index] = spray_spreads[last]
		original_widths[index] = original_widths[last]
		original_heights[index] = original_heights[last]
		point_offsets[index] = point_offsets[last]
		point_counts[index] = point_counts[last]
		revisions[index] = revisions[last]
		_index_by_id[int(entity_ids[index])] = index
	entity_ids.resize(last)
	style_ids.resize(last)
	colors.resize(last)
	base_widths.resize(last)
	spray_spreads.resize(last)
	original_widths.resize(last)
	original_heights.resize(last)
	point_offsets.resize(last)
	point_counts.resize(last)
	revisions.resize(last)
	_index_by_id.erase(entity_id)
	_store_revision += 1
	stroke_removed.emit(entity_id)
	return true


func clear() -> void:
	entity_ids = PackedInt64Array()
	style_ids = PackedInt32Array()
	colors = PackedColorArray()
	base_widths = PackedFloat32Array()
	spray_spreads = PackedFloat32Array()
	original_widths = PackedFloat32Array()
	original_heights = PackedFloat32Array()
	point_offsets = PackedInt32Array()
	point_counts = PackedInt32Array()
	revisions = PackedInt64Array()
	_point_arena = PackedVector2Array()
	_index_by_id.clear()
	_store_revision += 1
	cleared.emit()


func serialize() -> Array[Dictionary]:
	_compact_arena()
	var result: Array[Dictionary] = []
	result.resize(entity_ids.size())
	for index: int in range(entity_ids.size()):
		result[index] = {
			"entity_id": str(entity_ids[index]),
			"style_id": int(style_ids[index]),
			"color": colors[index].to_html(true),
			"width": float(base_widths[index]),
			"spray_spread": float(spray_spreads[index]),
			"original_width": float(original_widths[index]),
			"original_height": float(original_heights[index]),
			"point_offset": int(point_offsets[index]),
			"point_count": int(point_counts[index]),
		}
	return result


func deserialize(records: Array) -> void:
	clear()
	# Point data is loaded separately from the binary sidecar. Keep metadata now
	# and build the id index; validate offsets after apply_binary_payload().
	for raw_record: Variant in records:
		if raw_record is not Dictionary:
			continue
		var record: Dictionary = raw_record as Dictionary
		var entity_id: int = int(str(record.get("entity_id", "0")))
		if entity_id <= 0 or _index_by_id.has(entity_id):
			continue
		var index: int = entity_ids.size()
		entity_ids.append(entity_id)
		style_ids.append(clampi(int(record.get("style_id", STYLE_PEN)), STYLE_PEN, STYLE_SPRAY))
		colors.append(Color.from_string(str(record.get("color", "#24885aff")), Color("#24885a")))
		base_widths.append(clampf(float(record.get("width", 4.0)), MIN_WIDTH, MAX_WIDTH))
		spray_spreads.append(clampf(float(record.get("spray_spread", 1.0)), MIN_SPRAY_SPREAD, MAX_SPRAY_SPREAD))
		original_widths.append(maxf(0.001, float(record.get("original_width", 1.0))))
		original_heights.append(maxf(0.001, float(record.get("original_height", 1.0))))
		point_offsets.append(maxi(0, int(record.get("point_offset", 0))))
		point_counts.append(maxi(0, int(record.get("point_count", 0))))
		revisions.append(1)
		_index_by_id[entity_id] = index
	_store_revision = 0


func encode_binary_payload() -> PackedByteArray:
	_compact_arena()
	return var_to_bytes({"format": BINARY_FORMAT, "version": BINARY_VERSION, "points": _point_arena})


func apply_binary_payload(bytes: PackedByteArray) -> bool:
	if entity_ids.is_empty():
		_point_arena = PackedVector2Array()
		return true
	if bytes.is_empty():
		return false
	var decoded: Variant = bytes_to_var(bytes)
	if decoded is not Dictionary:
		return false
	var payload: Dictionary = decoded as Dictionary
	if str(payload.get("format", "")) != BINARY_FORMAT or int(payload.get("version", 0)) != BINARY_VERSION:
		return false
	var points_value: Variant = payload.get("points", PackedVector2Array())
	if points_value is not PackedVector2Array:
		return false
	var points: PackedVector2Array = points_value as PackedVector2Array
	for index: int in range(entity_ids.size()):
		var offset: int = int(point_offsets[index])
		var count: int = int(point_counts[index])
		if count <= 0 or offset < 0 or offset + count > points.size():
			return false
	_point_arena = points
	return true


func _compact_arena() -> void:
	if entity_ids.is_empty():
		_point_arena = PackedVector2Array()
		return
	var compacted: PackedVector2Array = PackedVector2Array()
	for index: int in range(entity_ids.size()):
		var old_offset: int = int(point_offsets[index])
		var count: int = int(point_counts[index])
		var next_offset: int = compacted.size()
		if count > 0 and old_offset >= 0 and old_offset + count <= _point_arena.size():
			compacted.append_array(_point_arena.slice(old_offset, old_offset + count))
		point_offsets[index] = next_offset
	_point_arena = compacted


func _touch(index: int, entity_id: int) -> void:
	revisions[index] = int(revisions[index]) + 1
	_store_revision += 1
	stroke_changed.emit(entity_id)
