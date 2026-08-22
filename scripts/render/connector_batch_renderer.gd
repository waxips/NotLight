# SPDX-License-Identifier: GPL-3.0-or-later
class_name ConnectorBatchRenderer
extends Node2D

var _runtime: BoardRuntime
var _telemetry: PerformanceTelemetryService
var _visible_connector_ids: PackedInt64Array = PackedInt64Array()
var _hidden_connector_ids: Dictionary = {}
var _batches: Array[Dictionary] = []
var _zoom: float = 1.0
var _maximum_segments: int = 120000
var _lod_level: int = int(BoardRenderPolicy.LodLevel.FULL)
var _last_segment_count: int = 0


func configure_telemetry(telemetry_service: PerformanceTelemetryService) -> void:
	_telemetry = telemetry_service


func rebuild(
	runtime: BoardRuntime,
	candidate_ids: PackedInt64Array,
	maximum_connectors: int,
	zoom: float = 1.0,
	maximum_segments: int = 120000,
	lod_level: int = -1,
	focus_world: Vector2 = Vector2.ZERO
) -> void:
	_runtime = runtime
	_zoom = maxf(zoom, 0.08)
	_maximum_segments = maxi(1000, maximum_segments)
	_lod_level = int(BoardRenderPolicy.LodLevel.FULL)
	if lod_level >= 0:
		_lod_level = lod_level
	elif runtime != null:
		_lod_level = int(runtime.render_policy.lod_for_zoom(_zoom))
	_visible_connector_ids = PackedInt64Array()
	if runtime == null:
		_batches.clear()
		_last_segment_count = 0
		if _telemetry != null:
			_telemetry.set_developer_gauge(&"connector_segments", 0.0)
			_publish_developer_geometry_metrics(0, 0, 0)
		queue_redraw()
		return
	var ids: Array[int] = []
	for entity_id: int in candidate_ids:
		if runtime.model.connectors.contains(entity_id):
			ids.append(entity_id)
	var limit: int = maxi(1, maximum_connectors)
	if ids.size() > limit:
		ids.sort_custom(func(left_id: int, right_id: int) -> bool:
			var left_distance: float = runtime.model.get_entity_bounds(left_id).get_center().distance_squared_to(focus_world)
			var right_distance: float = runtime.model.get_entity_bounds(right_id).get_center().distance_squared_to(focus_world)
			if not is_equal_approx(left_distance, right_distance):
				return left_distance < right_distance
			return left_id < right_id
		)
		ids.resize(limit)
	ids.sort_custom(func(left_id: int, right_id: int) -> bool:
		var left_z: int = runtime.model.get_entity_z_order(left_id)
		var right_z: int = runtime.model.get_entity_z_order(right_id)
		return left_z < right_z if left_z != right_z else left_id < right_id
	)
	_visible_connector_ids.resize(ids.size())
	for index: int in range(ids.size()):
		_visible_connector_ids[index] = ids[index]
	_rebuild_geometry()


func set_hidden_connector_ids(hidden_ids: Dictionary, rebuild_geometry: bool = true) -> void:
	_hidden_connector_ids = hidden_ids.duplicate()
	if rebuild_geometry:
		_rebuild_geometry()


func get_last_segment_count() -> int:
	return _last_segment_count


func clear() -> void:
	_runtime = null
	_visible_connector_ids = PackedInt64Array()
	_hidden_connector_ids.clear()
	_batches.clear()
	_last_segment_count = 0
	if _telemetry != null:
		_telemetry.set_developer_gauge(&"connector_segments", 0.0)
		_publish_developer_geometry_metrics(0, 0, 0)
	queue_redraw()


func _rebuild_geometry() -> void:
	_batches.clear()
	if _runtime == null:
		_last_segment_count = 0
		if _telemetry != null:
			_telemetry.set_developer_gauge(&"connector_segments", 0.0)
			_publish_developer_geometry_metrics(0, 0, 0)
		queue_redraw()
		return
	var batch_by_style: Dictionary = {}
	var emitted_segments: int = 0
	var rendered_connectors: int = 0
	var budget_skipped: int = 0
	for connector_id: int in _visible_connector_ids:
		if emitted_segments >= _maximum_segments:
			budget_skipped += 1
			continue
		if _hidden_connector_ids.has(connector_id) or not _runtime.model.connectors.contains(connector_id):
			continue
		var source_id: int = _runtime.model.connectors.get_source_entity_id(connector_id)
		var target_id: int = _runtime.model.connectors.get_target_entity_id(connector_id)
		if not _runtime.model.contains(source_id) or not _runtime.model.contains(target_id):
			continue
		var source_anchor: int = _runtime.model.connectors.get_source_anchor(connector_id)
		var target_anchor: int = _runtime.model.connectors.get_target_anchor(connector_id)
		var start: Vector2 = ConnectorGeometry.anchor_position(_runtime.model.get_entity_bounds(source_id), source_anchor)
		var finish: Vector2 = ConnectorGeometry.anchor_position(_runtime.model.get_entity_bounds(target_id), target_anchor)
		var router_points: PackedVector2Array = _runtime.model.connectors.get_router_points(connector_id)
		var remaining_segments: int = _maximum_segments - emitted_segments
		var curve: PackedVector2Array = _curve_for_lod(
			start,
			source_anchor,
			finish,
			target_anchor,
			router_points,
			remaining_segments
		)
		if curve.size() < 2:
			continue
		var direction: int = _runtime.model.connectors.get_direction(connector_id)
		var draw_arrows: bool = _lod_level != int(BoardRenderPolicy.LodLevel.PLACEHOLDER)
		var arrow_at_start: bool = draw_arrows and ConnectorGeometry.direction_has_source_arrow(direction)
		var arrow_at_end: bool = draw_arrows and ConnectorGeometry.direction_has_target_arrow(direction)
		var arrow_world_scale: float = 1.0 / _zoom
		var segments: PackedVector2Array = ConnectorGeometry.append_curve_segments(
			PackedVector2Array(),
			curve,
			13.0 * arrow_world_scale,
			7.0 * arrow_world_scale,
			arrow_at_start,
			arrow_at_end
		)
		var segment_cost: int = int(segments.size() / 2)
		if segment_cost > remaining_segments:
			# The shared curve sampler has a deliberate minimum quality floor. Near
			# the global geometry budget, fall back to one deterministic segment
			# rather than overshooting that budget or dropping the connector.
			if remaining_segments <= 0:
				budget_skipped += 1
				continue
			segments = ConnectorGeometry.append_curve_segments(
				PackedVector2Array(),
				PackedVector2Array([start, finish]),
				13.0 * arrow_world_scale,
				7.0 * arrow_world_scale,
				false,
				false
			)
			segment_cost = 1
		var color: Color = _runtime.model.connectors.get_color(connector_id)
		var width: float = _runtime.model.connectors.get_width(connector_id)
		var key: String = "%s|%.3f" % [color.to_html(true), width]
		var batch: Dictionary = {}
		var existing: Variant = batch_by_style.get(key)
		if existing is Dictionary:
			batch = existing as Dictionary
		else:
			batch = {
				"segments": PackedVector2Array(),
				"color": color,
				"width": width,
			}
		var batch_segments: PackedVector2Array = batch.get("segments", PackedVector2Array()) as PackedVector2Array
		for point: Vector2 in segments:
			batch_segments.append(point)
		batch["segments"] = batch_segments
		batch_by_style[key] = batch
		emitted_segments += segment_cost
		rendered_connectors += 1
	for raw_key: Variant in batch_by_style.keys():
		var batch_value: Variant = batch_by_style.get(raw_key)
		if batch_value is Dictionary:
			_batches.append(batch_value as Dictionary)
	_last_segment_count = emitted_segments
	if _telemetry != null:
		_telemetry.set_developer_gauge(&"connector_segments", float(_last_segment_count))
		_publish_developer_geometry_metrics(_visible_connector_ids.size(), rendered_connectors, budget_skipped)
	queue_redraw()


func _publish_developer_geometry_metrics(candidates: int, rendered: int, budget_skipped: int) -> void:
	if _telemetry == null or not _telemetry.developer_diagnostics_enabled():
		return
	_telemetry.set_developer_gauge(&"connector_candidates", float(candidates))
	_telemetry.set_developer_gauge(&"connector_rendered", float(rendered))
	_telemetry.set_developer_gauge(&"connector_budget_skipped", float(budget_skipped))


func _curve_for_lod(
	start: Vector2,
	start_anchor: int,
	finish: Vector2,
	finish_anchor: int,
	router_points: PackedVector2Array,
	remaining_segments: int
) -> PackedVector2Array:
	match _lod_level:
		BoardRenderPolicy.LodLevel.PLACEHOLDER:
			return PackedVector2Array([start, finish])
		BoardRenderPolicy.LodLevel.LOW:
			var polyline: PackedVector2Array = PackedVector2Array()
			polyline.append(start)
			for point: Vector2 in router_points:
				polyline.append(point)
			polyline.append(finish)
			return polyline
		BoardRenderPolicy.LodLevel.MEDIUM:
			var medium_samples: int = clampi(remaining_segments - 4, 16, 120)
			return ConnectorGeometry.sample_routed_curve(
				start,
				start_anchor,
				finish,
				finish_anchor,
				router_points,
				_zoom,
				medium_samples
			)
		_:
			var full_samples: int = clampi(remaining_segments - 4, 16, 320)
			return ConnectorGeometry.sample_routed_curve(
				start,
				start_anchor,
				finish,
				finish_anchor,
				router_points,
				_zoom,
				full_samples
			)


func _draw() -> void:
	var draw_start_usec: int = Time.get_ticks_usec() if _telemetry != null and _telemetry.developer_diagnostics_enabled() else -1
	for batch: Dictionary in _batches:
		var segments: PackedVector2Array = batch.get("segments", PackedVector2Array()) as PackedVector2Array
		if segments.size() < 2:
			continue
		var color: Color = batch.get("color", ConnectorStore.DEFAULT_COLOR) as Color
		var width: float = float(batch.get("width", ConnectorStore.DEFAULT_WIDTH))
		draw_multiline(segments, color, width, true)
	if draw_start_usec >= 0:
		_telemetry.record_developer_timing_usec(&"connector_draw", Time.get_ticks_usec() - draw_start_usec)
