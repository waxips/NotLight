# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardHitTestSystem
extends RefCounted

const FALLBACK_GROW_MULTIPLIER: float = 2.5

var model: BoardModel
var spatial_index: ChunkSpatialIndex


func configure(board_model: BoardModel, index: ChunkSpatialIndex) -> void:
	model = board_model
	spatial_index = index


func hit_test_point(world_position: Vector2, tolerance: float = 0.0) -> BoardHitResult:
	var result: BoardHitResult = BoardHitResult.new()
	result.world_position = world_position
	if model == null or spatial_index == null:
		return result
	var safe_tolerance: float = maxf(tolerance, 0.001)
	var candidates: PackedInt64Array = spatial_index.query_point(world_position, safe_tolerance)
	var best_id: int = _best_selectable_candidate(candidates, world_position, safe_tolerance)
	if best_id == 0:
		var fallback_margin: float = maxf(safe_tolerance * FALLBACK_GROW_MULTIPLIER, 4.0)
		var fallback_area: Rect2 = Rect2(
			world_position - Vector2.ONE * fallback_margin,
			Vector2.ONE * fallback_margin * 2.0
		)
		candidates = spatial_index.query_rect(fallback_area)
		best_id = _best_selectable_candidate(candidates, world_position, fallback_margin)
	if best_id == 0:
		best_id = _fallback_scan_dense_objects(world_position, maxf(safe_tolerance, 4.0))
	if best_id == 0:
		return result
	var best_bounds: Rect2 = model.get_entity_bounds(best_id)
	result.entity_id = best_id
	result.type_id = model.get_entity_type(best_id)
	result.local_position = world_position - best_bounds.position
	result.z_order = model.get_entity_z_order(best_id)
	return result


func _best_selectable_candidate(
	candidates: PackedInt64Array,
	world_position: Vector2,
	tolerance: float
) -> int:
	var best_id: int = 0
	var best_priority: int = -1
	var best_z: int = -2147483648
	var best_distance: float = INF
	for entity_id: int in candidates:
		if not model.contains(entity_id) or not model.transforms.is_visible(entity_id):
			continue
		var type_id: StringName = model.get_entity_type(entity_id)
		var bounds: Rect2 = model.get_entity_bounds(entity_id)
		if not bounds.grow(tolerance).has_point(world_position):
			continue
		var distance: float = _distance_squared_to_rect(world_position, bounds)
		if type_id == BoardEntityTypes.CONNECTOR:
			distance = _connector_distance_squared(entity_id, world_position)
			if distance > tolerance * tolerance:
				continue
		elif type_id == BoardEntityTypes.STROKE:
			if not model.strokes.hit_test_point(entity_id, bounds, world_position, tolerance):
				continue
			distance = 0.0
		var priority: int = 0 if type_id == BoardEntityTypes.CONNECTOR else 1
		var z_order: int = model.get_entity_z_order(entity_id)
		if (
			best_id == 0
			or priority > best_priority
			or (priority == best_priority and z_order > best_z)
			or (priority == best_priority and z_order == best_z and distance < best_distance)
			or (
				priority == best_priority
				and z_order == best_z
				and is_equal_approx(distance, best_distance)
				and entity_id > best_id
			)
		):
			best_id = entity_id
			best_priority = priority
			best_z = z_order
			best_distance = distance
	return best_id


func _connector_distance_squared(connector_id: int, world_position: Vector2) -> float:
	if model == null or not model.connectors.contains(connector_id):
		return INF
	var source_id: int = model.connectors.get_source_entity_id(connector_id)
	var target_id: int = model.connectors.get_target_entity_id(connector_id)
	if not model.contains(source_id) or not model.contains(target_id):
		return INF
	var source_anchor: int = model.connectors.get_source_anchor(connector_id)
	var target_anchor: int = model.connectors.get_target_anchor(connector_id)
	var start: Vector2 = ConnectorGeometry.anchor_position(model.get_entity_bounds(source_id), source_anchor)
	var finish: Vector2 = ConnectorGeometry.anchor_position(model.get_entity_bounds(target_id), target_anchor)
	return ConnectorGeometry.distance_squared_to_curve(
		start,
		source_anchor,
		finish,
		target_anchor,
		world_position,
		model.connectors.get_router_points(connector_id),
		72
	)


func _fallback_scan_dense_objects(world_position: Vector2, tolerance: float) -> int:
	if model == null:
		return 0
	var candidate_ids: PackedInt64Array = PackedInt64Array()
	candidate_ids.append_array(model.text_blocks.entity_ids)
	candidate_ids.append_array(model.images.entity_ids)
	candidate_ids.append_array(model.pdfs.entity_ids)
	candidate_ids.append_array(model.formulas.entity_ids)
	candidate_ids.append_array(model.videos.entity_ids)
	candidate_ids.append_array(model.audios.entity_ids)
	candidate_ids.append_array(model.strokes.entity_ids)
	var best_id: int = 0
	var best_z: int = -2147483648
	var best_distance: float = INF
	for entity_id: int in candidate_ids:
		if not model.contains(entity_id) or not model.transforms.is_visible(entity_id):
			continue
		var bounds: Rect2 = model.get_entity_bounds(entity_id)
		if not bounds.grow(tolerance).has_point(world_position):
			continue
		if model.get_entity_type(entity_id) == BoardEntityTypes.STROKE and not model.strokes.hit_test_point(entity_id, bounds, world_position, tolerance):
			continue
		var z_order: int = model.get_entity_z_order(entity_id)
		var distance: float = _distance_squared_to_rect(world_position, bounds)
		if (
			best_id == 0
			or z_order > best_z
			or (z_order == best_z and distance < best_distance)
			or (z_order == best_z and is_equal_approx(distance, best_distance) and entity_id > best_id)
		):
			best_id = entity_id
			best_z = z_order
			best_distance = distance
	return best_id


func _distance_squared_to_rect(point: Vector2, rect: Rect2) -> float:
	var nearest: Vector2 = Vector2(
		clampf(point.x, rect.position.x, rect.end.x),
		clampf(point.y, rect.position.y, rect.end.y)
	)
	return nearest.distance_squared_to(point)
