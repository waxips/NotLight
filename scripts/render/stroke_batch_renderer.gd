# SPDX-License-Identifier: GPL-3.0-or-later
class_name StrokeBatchRenderer
extends Node2D

signal handoff_entities_ready(entity_ids: PackedInt64Array)

const SPRAY_TEXTURE_SIZE: int = 24
const MEDIUM_MAX_POINTS: int = 256
const LOW_MAX_POINTS: int = 96
const PLACEHOLDER_MAX_POINTS: int = 32
const MEDIUM_REPRESENTATIVE_ZOOM: float = 0.72
const LOW_REPRESENTATIVE_ZOOM: float = 0.18
const PLACEHOLDER_REPRESENTATIVE_ZOOM: float = 0.08
const TARGET_RETAINED_STROKE_SEGMENTS_FULL: int = 36000
const TARGET_RETAINED_STROKE_SEGMENTS_MEDIUM: int = 24000
const TARGET_RETAINED_STROKE_SEGMENTS_LOW: int = 12000
const TARGET_RETAINED_STROKE_SEGMENTS_PLACEHOLDER: int = 6000
const MIN_ADAPTIVE_POINTS_PER_STROKE: int = 2

var runtime: BoardRuntime
var telemetry: PerformanceTelemetryService
var hidden_entity_ids: Dictionary = {}
var _handoff_watch_ids: Dictionary = {}
var zoom_value: float = 1.0
var _visible_candidates: PackedInt64Array = PackedInt64Array()
var _segment_budget: int = 160000
var _lod_level: int = int(BoardRenderPolicy.LodLevel.FULL)
var _requested_lod_level: int = int(BoardRenderPolicy.LodLevel.FULL)
var _adaptive_point_limit: int = 0
var _adaptive_source_points: int = 0
var _adaptive_spray_particle_limit: int = 0
var _effective_segment_budget: int = 160000
var _zoom_bucket: int = 0
var _simplified_cache: Dictionary = {}
var _spray_cache: Dictionary = {}
var _spray_texture: Texture2D
var _spray_quad_mesh: QuadMesh
var _last_segment_count: int = 0


func configure(board_runtime: BoardRuntime, telemetry_service: PerformanceTelemetryService = null) -> void:
	if runtime != board_runtime:
		_spray_cache.clear()
		_simplified_cache.clear()
	runtime = board_runtime
	telemetry = telemetry_service
	queue_redraw()


func rebuild(candidate_ids: PackedInt64Array, zoom: float, lod_level: int = -1, zoom_bucket: int = -999) -> void:
	_visible_candidates = candidate_ids.duplicate()
	zoom_value = maxf(zoom, 0.01)
	_zoom_bucket = zoom_bucket
	if runtime != null:
		_segment_budget = maxi(2000, runtime.render_policy.max_visible_stroke_segments)
		_requested_lod_level = lod_level if lod_level >= 0 else int(runtime.render_policy.lod_for_zoom(zoom_value))
		_configure_adaptive_lod()
	queue_redraw()


func set_hidden_entity_ids(ids: Dictionary) -> void:
	hidden_entity_ids = ids.duplicate()
	queue_redraw()


func set_handoff_watch_ids(ids: Dictionary) -> void:
	# This watch list is normally empty. Keeping it in the renderer lets the
	# post-commit handoff confirm only the few newly committed strokes without
	# allocating/reporting every rendered entity on ordinary board redraws.
	_handoff_watch_ids = ids.duplicate()


func get_last_segment_count() -> int:
	return _last_segment_count


func get_requested_lod_level() -> int:
	return _requested_lod_level


func get_effective_lod_level() -> int:
	return _lod_level


func get_adaptive_point_limit() -> int:
	return _adaptive_point_limit


func get_effective_segment_budget() -> int:
	return _effective_segment_budget


func _draw() -> void:
	var developer_metrics: bool = telemetry != null and telemetry.developer_diagnostics_enabled()
	var draw_start_usec: int = Time.get_ticks_usec() if developer_metrics else -1
	if runtime == null:
		_last_segment_count = 0
		if telemetry != null:
			telemetry.set_developer_gauge(&"stroke_segments", 0.0)
			if developer_metrics:
				_publish_developer_geometry_metrics(0, 0, 0, 0, 0, 0)
		return
	var entries: Array[int] = []
	for entity_id: int in _visible_candidates:
		if hidden_entity_ids.has(entity_id) or not runtime.model.strokes.contains(entity_id):
			continue
		entries.append(entity_id)
	entries.sort_custom(func(left_id: int, right_id: int) -> bool:
		var left_z: int = runtime.model.get_entity_z_order(left_id)
		var right_z: int = runtime.model.get_entity_z_order(right_id)
		return left_z < right_z if left_z != right_z else left_id < right_id
	)
	var segments_used: int = 0
	var rendered_strokes: int = 0
	var source_points: int = 0
	var rendered_points: int = 0
	var budget_skipped: int = 0
	var spray_particles: int = 0
	var watching_handoffs: bool = not _handoff_watch_ids.is_empty()
	var handoff_ready_ids: PackedInt64Array = PackedInt64Array()
	for entity_id: int in entries:
		var style_id: int = runtime.model.strokes.get_style_id(entity_id)
		if developer_metrics:
			source_points += runtime.model.strokes.get_point_count(entity_id)
		if style_id == StrokeStore.STYLE_SPRAY:
			var spray_cost: int = _estimated_spray_cost(entity_id)
			if segments_used + spray_cost > _effective_segment_budget:
				budget_skipped += 1
				continue
			segments_used += spray_cost
			if watching_handoffs and _handoff_watch_ids.has(entity_id):
				# The transient overlay remains authoritative for this frame. Report
				# readiness without drawing the retained copy underneath it, otherwise
				# translucent/highlighter strokes briefly become darker at handoff.
				handoff_ready_ids.append(entity_id)
				continue
			spray_particles += spray_cost
			rendered_strokes += 1
			_draw_cached_spray(entity_id)
			continue
		var bounds: Rect2 = runtime.model.get_entity_bounds(entity_id)
		var points: PackedVector2Array = _render_points(entity_id, bounds)
		if points.is_empty():
			continue
		var width: float = runtime.model.strokes.get_effective_width(entity_id, bounds)
		var needed: int = _estimated_render_cost_for_lod(points.size(), style_id)
		if segments_used + needed > _effective_segment_budget:
			budget_skipped += 1
			continue
		segments_used += needed
		if watching_handoffs and _handoff_watch_ids.has(entity_id):
			# See the spray path above: acknowledge that retained geometry is ready,
			# but let the transient copy own this frame for an atomic visual handoff.
			handoff_ready_ids.append(entity_id)
			continue
		rendered_strokes += 1
		rendered_points += points.size()
		var stroke_color: Color = runtime.model.strokes.get_color(entity_id)
		if _lod_level >= int(BoardRenderPolicy.LodLevel.MEDIUM):
			_draw_far_lod_stroke(self, points, style_id, stroke_color, width)
		else:
			draw_stroke(self, points, style_id, stroke_color, width, entity_id)
	_last_segment_count = segments_used
	if telemetry != null:
		telemetry.set_developer_gauge(&"stroke_segments", float(_last_segment_count))
		if developer_metrics:
			_publish_developer_geometry_metrics(
				entries.size(),
				rendered_strokes,
				source_points,
				rendered_points,
				budget_skipped,
				spray_particles
			)
	if _spray_cache.size() > runtime.model.strokes.size() + 32:
		_prune_spray_cache()
	if _simplified_cache.size() > runtime.model.strokes.size() + 64:
		_prune_simplified_cache()
	if draw_start_usec >= 0:
		telemetry.record_developer_timing_usec(&"stroke_draw", Time.get_ticks_usec() - draw_start_usec)
	if not handoff_ready_ids.is_empty():
		handoff_entities_ready.emit(handoff_ready_ids)


func _publish_developer_geometry_metrics(
	candidates: int,
	rendered: int,
	source_points: int,
	render_points: int,
	budget_skipped: int,
	spray_particles: int
) -> void:
	if telemetry == null:
		return
	telemetry.set_developer_gauge(&"stroke_candidates", float(candidates))
	telemetry.set_developer_gauge(&"stroke_rendered", float(rendered))
	telemetry.set_developer_gauge(&"stroke_source_points", float(source_points))
	telemetry.set_developer_gauge(&"stroke_render_points", float(render_points))
	telemetry.set_developer_gauge(&"stroke_budget_skipped", float(budget_skipped))
	telemetry.set_developer_gauge(&"stroke_spray_particles", float(spray_particles))
	telemetry.set_developer_gauge(&"stroke_requested_lod", float(_requested_lod_level))
	telemetry.set_developer_gauge(&"stroke_effective_lod", float(_lod_level))
	telemetry.set_developer_gauge(&"stroke_adaptive_point_limit", float(_adaptive_point_limit))
	telemetry.set_developer_gauge(&"stroke_adaptive_source_points", float(_adaptive_source_points))
	telemetry.set_developer_gauge(&"stroke_target_segments", float(_effective_segment_budget))
	telemetry.set_developer_gauge(&"stroke_adaptive_spray_limit", float(_adaptive_spray_particle_limit))


func _render_points(entity_id: int, bounds: Rect2) -> PackedVector2Array:
	if runtime == null:
		return PackedVector2Array()
	if _lod_level == int(BoardRenderPolicy.LodLevel.FULL):
		return runtime.model.strokes.get_world_points(entity_id, bounds)
	var strokes: StrokeStore = runtime.model.strokes
	var revision: int = strokes.get_revision(entity_id)
	var existing: Dictionary = _simplified_cache.get(entity_id, {}) as Dictionary
	if (
		int(existing.get("revision", -1)) == revision
		and int(existing.get("lod", -1)) == _lod_level
		and int(existing.get("limit", -1)) == _effective_point_limit_for_lod(_lod_level)
		and existing.get("bounds", Rect2()) == bounds
	):
		if telemetry != null and telemetry.developer_diagnostics_enabled():
			telemetry.record_developer_counter(&"stroke_simplify_cache_hits")
		return existing.get("points", PackedVector2Array()) as PackedVector2Array
	if telemetry != null and telemetry.developer_diagnostics_enabled():
		telemetry.record_developer_counter(&"stroke_simplify_cache_misses")
	var tolerance_pixels: float = 1.45
	var maximum_points: int = MEDIUM_MAX_POINTS
	var representative_zoom: float = MEDIUM_REPRESENTATIVE_ZOOM
	match _lod_level:
		BoardRenderPolicy.LodLevel.LOW:
			tolerance_pixels = 2.40
			maximum_points = LOW_MAX_POINTS
			representative_zoom = LOW_REPRESENTATIVE_ZOOM
		BoardRenderPolicy.LodLevel.PLACEHOLDER:
			tolerance_pixels = 3.8
			maximum_points = PLACEHOLDER_MAX_POINTS
			representative_zoom = PLACEHOLDER_REPRESENTATIVE_ZOOM
		_:
			pass
	if _adaptive_point_limit > 1:
		maximum_points = mini(maximum_points, _adaptive_point_limit)
	# Simplification is intentionally stable for an entire LOD. Camera zoom is a
	# transform of retained geometry; tying this cache to every zoom bucket caused
	# expensive redraws while pinching without producing a visible benefit.
	var original_size: Vector2 = strokes.get_original_size(entity_id)
	var scale: Vector2 = Vector2(
		bounds.size.x / maxf(original_size.x, 0.001),
		bounds.size.y / maxf(original_size.y, 0.001)
	)
	var maximum_axis_scale: float = maxf(maxf(absf(scale.x), absf(scale.y)), 0.001)
	var world_tolerance: float = tolerance_pixels / representative_zoom
	var local_tolerance: float = world_tolerance / maximum_axis_scale
	var bounded_source_limit: int = maxi(2, maximum_points * 3)
	var local_points: PackedVector2Array = strokes.get_local_points_decimated(entity_id, bounded_source_limit)
	if local_points.size() <= 2:
		return StrokeGeometry.transformed_points(local_points, original_size, bounds)
	var simplify_start_usec: int = Time.get_ticks_usec() if telemetry != null and telemetry.developer_diagnostics_enabled() else -1
	var simplified_local: PackedVector2Array = StrokeGeometry.simplify_polyline_fast(
		local_points,
		local_tolerance,
		maximum_points
	)
	if simplify_start_usec >= 0:
		telemetry.record_developer_timing_usec(&"stroke_simplify", Time.get_ticks_usec() - simplify_start_usec)
	var simplified: PackedVector2Array = StrokeGeometry.transformed_points(simplified_local, original_size, bounds)
	_simplified_cache[entity_id] = {
		"revision": revision,
		"lod": _lod_level,
		"limit": maximum_points,
		"bounds": bounds,
		"points": simplified,
	}
	return simplified


func _configure_adaptive_lod() -> void:
	_lod_level = _requested_lod_level
	_adaptive_point_limit = 0
	_adaptive_source_points = 0
	_adaptive_spray_particle_limit = 0
	_effective_segment_budget = _segment_budget
	if runtime == null or _visible_candidates.is_empty():
		return
	var stroke_count: int = 0
	var estimated_full_cost: int = 0
	for entity_id: int in _visible_candidates:
		if not runtime.model.strokes.contains(entity_id):
			continue
		stroke_count += 1
		var point_count: int = runtime.model.strokes.get_point_count(entity_id)
		_adaptive_source_points += point_count
		estimated_full_cost += _estimated_full_source_cost(entity_id, point_count)
	if stroke_count <= 0:
		return
	var target_segments: int = mini(_segment_budget, _target_segments_for_lod(_lod_level))
	# Exact brush rendering is preserved for sparse close views. Dense views are
	# automatically stepped down before they can materialize a huge retained
	# command buffer. The estimate intentionally accounts for styles such as
	# pencil/highlighter whose exact FULL rendering costs more than one simple
	# polyline segment per source segment.
	if _lod_level == int(BoardRenderPolicy.LodLevel.FULL) and estimated_full_cost > target_segments:
		_lod_level = int(BoardRenderPolicy.LodLevel.MEDIUM)
		target_segments = mini(_segment_budget, _target_segments_for_lod(_lod_level))
	# Apply the hard retained-geometry target even for sparse FULL views. Stage
	# 9.4 originally returned before this assignment for FULL, accidentally
	# falling back to the much larger profile-wide segment allowance.
	_effective_segment_budget = target_segments
	var lod_cap: int = _maximum_points_for_lod(_lod_level)
	if lod_cap <= 0:
		return
	var fair_segment_share: int = maxi(1, int(floor(float(target_segments) / float(stroke_count))))
	var fair_point_limit: int = maxi(MIN_ADAPTIVE_POINTS_PER_STROKE, fair_segment_share + 1)
	_adaptive_point_limit = mini(lod_cap, fair_point_limit)
	_adaptive_spray_particle_limit = maxi(8, fair_segment_share)


func _estimated_full_source_cost(entity_id: int, point_count: int) -> int:
	if runtime == null:
		return 0
	var style_id: int = runtime.model.strokes.get_style_id(entity_id)
	if style_id == StrokeStore.STYLE_SPRAY:
		return _estimated_spray_cost(entity_id)
	var segments: int = maxi(1, point_count - 1)
	match style_id:
		StrokeStore.STYLE_PENCIL, StrokeStore.STYLE_HIGHLIGHTER:
			return segments * 2
		_:
			return segments


func _target_segments_for_lod(lod_level: int) -> int:
	match lod_level:
		BoardRenderPolicy.LodLevel.MEDIUM:
			return TARGET_RETAINED_STROKE_SEGMENTS_MEDIUM
		BoardRenderPolicy.LodLevel.LOW:
			return TARGET_RETAINED_STROKE_SEGMENTS_LOW
		BoardRenderPolicy.LodLevel.PLACEHOLDER:
			return TARGET_RETAINED_STROKE_SEGMENTS_PLACEHOLDER
		_:
			return TARGET_RETAINED_STROKE_SEGMENTS_FULL


func _maximum_points_for_lod(lod_level: int) -> int:
	match lod_level:
		BoardRenderPolicy.LodLevel.MEDIUM:
			return MEDIUM_MAX_POINTS
		BoardRenderPolicy.LodLevel.LOW:
			return LOW_MAX_POINTS
		BoardRenderPolicy.LodLevel.PLACEHOLDER:
			return PLACEHOLDER_MAX_POINTS
		_:
			return 0


func _effective_point_limit_for_lod(lod_level: int) -> int:
	var lod_cap: int = _maximum_points_for_lod(lod_level)
	if lod_cap <= 0:
		return 0
	return mini(lod_cap, _adaptive_point_limit) if _adaptive_point_limit > 1 else lod_cap


func _draw_cached_spray(entity_id: int) -> void:
	if runtime == null:
		return
	var record: Dictionary = _spray_cache_record(entity_id)
	var multimesh: MultiMesh = record.get("multimesh") as MultiMesh
	if multimesh == null or multimesh.instance_count <= 0:
		return
	var bounds: Rect2 = runtime.model.get_entity_bounds(entity_id)
	var original_size: Vector2 = runtime.model.strokes.get_original_size(entity_id)
	var scale: Vector2 = Vector2(
		bounds.size.x / maxf(original_size.x, 0.001),
		bounds.size.y / maxf(original_size.y, 0.001)
	)
	draw_set_transform(bounds.position, 0.0, scale)
	draw_multimesh(multimesh, _get_spray_texture())
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _spray_cache_record(entity_id: int) -> Dictionary:
	var strokes: StrokeStore = runtime.model.strokes
	var revision: int = strokes.get_revision(entity_id)
	var density: float = _effective_spray_density()
	var particle_limit: int = _effective_spray_particle_limit()
	var quality_key: String = "%d|%.3f|%d" % [particle_limit, density, _lod_level]
	var existing: Dictionary = _spray_cache.get(entity_id, {}) as Dictionary
	if int(existing.get("revision", -1)) == revision and str(existing.get("quality", "")) == quality_key:
		return existing
	var points: PackedVector2Array = strokes.get_local_points(entity_id)
	var width: float = strokes.get_base_width(entity_id)
	var spread: float = strokes.get_spray_spread(entity_id)
	var mm: MultiMesh = _build_spray_multimesh(
		points,
		strokes.get_color(entity_id),
		width,
		spread,
		entity_id,
		density,
		particle_limit
	)
	var result: Dictionary = {"revision": revision, "quality": quality_key, "multimesh": mm}
	_spray_cache[entity_id] = result
	return result


func _build_spray_multimesh(
	points: PackedVector2Array,
	color: Color,
	width: float,
	spread: float,
	stable_seed: int,
	density: float,
	max_particles: int
) -> MultiMesh:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = _get_spray_quad_mesh()
	if points.is_empty():
		mm.instance_count = 0
		return mm
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = stable_seed if stable_seed != 0 else 1337
	var clean_width: float = maxf(width, 0.75)
	var clean_spread: float = clampf(spread, StrokeStore.MIN_SPRAY_SPREAD, StrokeStore.MAX_SPRAY_SPREAD)
	var clean_density: float = clampf(density, 0.10, 1.5)
	# Keep this minimum aligned with _effective_spray_particle_limit(). A higher
	# hidden minimum would let the MultiMesh materialize more particles than the
	# retained-geometry budget accounted for on dense LOW/PLACEHOLDER views.
	var particle_limit: int = clampi(max_particles, 8, 6000)
	var sample_spacing: float = maxf(1.2, clean_width * 0.34 / clean_density)
	var dots_per_sample: int = clampi(int(round((1.6 + clean_width * 0.22) * clean_density)), 1, 7)
	var transforms: Array[Transform2D] = []
	var particle_colors: Array[Color] = []
	if points.size() == 1:
		_append_spray_cloud(transforms, particle_colors, rng, points[0], color, clean_width, clean_spread, dots_per_sample, particle_limit)
	else:
		for segment_index: int in range(points.size() - 1):
			var a: Vector2 = points[segment_index]
			var b: Vector2 = points[segment_index + 1]
			var length: float = a.distance_to(b)
			var samples: int = maxi(1, int(ceil(length / sample_spacing)))
			for sample_index: int in range(samples):
				if transforms.size() >= particle_limit:
					break
				var t: float = (float(sample_index) + 0.5) / float(samples)
				_append_spray_cloud(transforms, particle_colors, rng, a.lerp(b, t), color, clean_width, clean_spread, dots_per_sample, particle_limit)
			if transforms.size() >= particle_limit:
				break
	mm.instance_count = transforms.size()
	for index: int in range(transforms.size()):
		mm.set_instance_transform_2d(index, transforms[index])
		mm.set_instance_color(index, particle_colors[index])
	return mm


func _append_spray_cloud(
	transforms: Array[Transform2D],
	particle_colors: Array[Color],
	rng: RandomNumberGenerator,
	center: Vector2,
	base_color: Color,
	width: float,
	spread: float,
	count: int,
	limit: int
) -> void:
	for _dot: int in range(count):
		if transforms.size() >= limit:
			return
		var angle: float = rng.randf_range(0.0, TAU)
		var radial: float = pow(rng.randf(), 0.72) * width * (0.62 + spread * 0.78)
		var position: Vector2 = center + Vector2(cos(angle), sin(angle)) * radial
		var diameter: float = maxf(0.8, width * rng.randf_range(0.09, 0.23))
		transforms.append(Transform2D(0.0, Vector2.ONE * diameter, 0.0, position))
		var dot_color: Color = base_color
		dot_color.a *= rng.randf_range(0.18, 0.48)
		particle_colors.append(dot_color)


func _estimated_spray_cost(entity_id: int) -> int:
	var strokes: StrokeStore = runtime.model.strokes
	var revision: int = strokes.get_revision(entity_id)
	var density: float = _effective_spray_density()
	var particle_limit: int = _effective_spray_particle_limit()
	var quality_key: String = "%d|%.3f|%d" % [particle_limit, density, _lod_level]
	var existing: Dictionary = _spray_cache.get(entity_id, {}) as Dictionary
	if int(existing.get("revision", -1)) == revision and str(existing.get("quality", "")) == quality_key:
		var cached: MultiMesh = existing.get("multimesh") as MultiMesh
		if cached != null:
			return maxi(1, cached.instance_count)
	# Before a cache entry exists we deliberately charge the full allowed particle
	# count. Estimating from point count can undercount a sparse stroke with long
	# segments because spray sampling is distance-based. The conservative value
	# guarantees that the retained budget is a real upper bound; once materialized,
	# the exact MultiMesh instance_count is used on subsequent draws.
	return particle_limit


func _effective_spray_density() -> float:
	if runtime == null:
		return 0.72
	var base_density: float = runtime.render_policy.spray_density
	match _lod_level:
		BoardRenderPolicy.LodLevel.MEDIUM:
			return base_density * 0.75
		BoardRenderPolicy.LodLevel.LOW:
			return base_density * 0.35
		BoardRenderPolicy.LodLevel.PLACEHOLDER:
			return base_density * 0.12
		_:
			return base_density


func _effective_spray_particle_limit() -> int:
	if runtime == null:
		return 600
	var base_limit: int = runtime.render_policy.max_spray_particles_per_stroke
	var lod_limit: int = base_limit
	match _lod_level:
		BoardRenderPolicy.LodLevel.MEDIUM:
			lod_limit = mini(base_limit, maxi(180, int(round(float(base_limit) * 0.55))))
		BoardRenderPolicy.LodLevel.LOW:
			lod_limit = mini(base_limit, 220)
		BoardRenderPolicy.LodLevel.PLACEHOLDER:
			lod_limit = mini(base_limit, 60)
		_:
			pass
	if _adaptive_spray_particle_limit > 0 and _lod_level != int(BoardRenderPolicy.LodLevel.FULL):
		lod_limit = mini(lod_limit, _adaptive_spray_particle_limit)
	return maxi(8, lod_limit)


func _prune_spray_cache() -> void:
	if runtime == null:
		_spray_cache.clear()
		return
	for raw_id: Variant in _spray_cache.keys():
		var entity_id: int = int(raw_id)
		if not runtime.model.strokes.contains(entity_id):
			_spray_cache.erase(raw_id)


func _prune_simplified_cache() -> void:
	if runtime == null:
		_simplified_cache.clear()
		return
	for raw_id: Variant in _simplified_cache.keys():
		var entity_id: int = int(raw_id)
		if not runtime.model.strokes.contains(entity_id):
			_simplified_cache.erase(raw_id)


func _get_spray_quad_mesh() -> QuadMesh:
	if _spray_quad_mesh != null:
		return _spray_quad_mesh
	_spray_quad_mesh = QuadMesh.new()
	_spray_quad_mesh.size = Vector2.ONE
	return _spray_quad_mesh


func _get_spray_texture() -> Texture2D:
	if _spray_texture != null:
		return _spray_texture
	var image: Image = Image.create(SPRAY_TEXTURE_SIZE, SPRAY_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var center: Vector2 = Vector2(SPRAY_TEXTURE_SIZE - 1, SPRAY_TEXTURE_SIZE - 1) * 0.5
	var radius: float = float(SPRAY_TEXTURE_SIZE) * 0.5
	for y: int in range(SPRAY_TEXTURE_SIZE):
		for x: int in range(SPRAY_TEXTURE_SIZE):
			var distance: float = Vector2(float(x), float(y)).distance_to(center) / radius
			var alpha: float = clampf(1.0 - distance, 0.0, 1.0)
			alpha = alpha * alpha * (3.0 - 2.0 * alpha)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_spray_texture = ImageTexture.create_from_image(image)
	return _spray_texture


func _estimated_render_cost_for_lod(point_count: int, style_id: int) -> int:
	var segments: int = maxi(1, point_count - 1)
	if _lod_level >= int(BoardRenderPolicy.LodLevel.MEDIUM):
		return segments
	return segments * 2 if style_id == StrokeStore.STYLE_PENCIL else segments


static func _draw_far_lod_stroke(
	canvas: CanvasItem,
	points: PackedVector2Array,
	style_id: int,
	color: Color,
	width: float
) -> void:
	if points.is_empty():
		return
	var draw_color: Color = color
	var draw_width: float = maxf(0.75, width)
	match style_id:
		StrokeStore.STYLE_HIGHLIGHTER:
			draw_color.a *= 0.27
			draw_width *= 2.2
		StrokeStore.STYLE_PENCIL:
			draw_color.a *= 0.82
			draw_width *= 0.90
	if points.size() == 1:
		canvas.draw_circle(points[0], draw_width * 0.5, draw_color, true, -1.0, true)
		return
	# At LOW/PLACEHOLDER LOD the endpoint caps and the pencil's secondary pass
	# are sub-pixel at typical screen sizes. One anti-aliased polyline preserves
	# the silhouette while reducing retained CanvasItem work substantially.
	canvas.draw_polyline(points, draw_color, draw_width, true)


static func draw_stroke(
	canvas: CanvasItem,
	points: PackedVector2Array,
	style_id: int,
	color: Color,
	width: float,
	stable_seed: int = 0,
	spray_spread: float = 1.0,
	spray_particle_limit: int = 110
) -> void:
	if points.is_empty():
		return
	var clean_width: float = maxf(0.75, width)
	match style_id:
		StrokeStore.STYLE_HIGHLIGHTER:
			_draw_highlighter(canvas, points, color, clean_width)
		StrokeStore.STYLE_PENCIL:
			var soft: Color = color
			soft.a *= 0.18
			_draw_round_polyline(canvas, points, soft, clean_width * 1.55)
			var core: Color = color
			core.a *= 0.78
			_draw_round_polyline(canvas, points, core, clean_width * 0.72)
		StrokeStore.STYLE_SPRAY:
			_draw_spray_preview(canvas, points, color, clean_width, stable_seed, spray_spread, spray_particle_limit)
		_:
			_draw_round_polyline(canvas, points, color, clean_width)


static func _draw_highlighter(canvas: CanvasItem, points: PackedVector2Array, color: Color, width: float) -> void:
	var marker: Color = color
	marker.a *= 0.27
	# Geometry2D.offset_polyline() returns filled polygons. When a single marker
	# stroke loops back around itself, that outline can contain the loop interior
	# and CanvasItem correctly fills it — visually turning a hollow ring into a
	# dark blob. A wide anti-aliased polyline represents marker ink directly and
	# leaves every enclosed region untouched. The 2.2 multiplier preserves the
	# previous total marker width (offset radius was width * 1.1).
	_draw_round_polyline(canvas, points, marker, width * 2.2)


static func _draw_round_polyline(canvas: CanvasItem, points: PackedVector2Array, color: Color, width: float) -> void:
	if points.size() == 1:
		canvas.draw_circle(points[0], width * 0.5, color, true, -1.0, true)
		return
	canvas.draw_polyline(points, color, width, true)
	var radius: float = width * 0.5
	canvas.draw_circle(points[0], radius, color, true, -1.0, true)
	canvas.draw_circle(points[points.size() - 1], radius, color, true, -1.0, true)


static func _draw_spray_preview(
	canvas: CanvasItem,
	points: PackedVector2Array,
	color: Color,
	width: float,
	stable_seed: int,
	spread: float,
	particle_limit: int
) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = stable_seed if stable_seed != 0 else points.size() * 7919 + int(points[0].x * 17.0) + int(points[0].y * 31.0)
	var clean_limit: int = clampi(particle_limit, 16, 260)
	var clean_spread: float = clampf(spread, StrokeStore.MIN_SPRAY_SPREAD, StrokeStore.MAX_SPRAY_SPREAD)
	var stride: int = maxi(1, int(ceil(float(points.size()) / maxf(1.0, float(clean_limit) / 3.0))))
	var dots: int = 0
	for point_index: int in range(0, points.size(), stride):
		for _dot: int in range(3):
			if dots >= clean_limit:
				return
			var angle: float = rng.randf_range(0.0, TAU)
			var radius: float = pow(rng.randf(), 0.72) * width * (0.62 + clean_spread * 0.78)
			var dot_color: Color = color
			dot_color.a *= rng.randf_range(0.20, 0.42)
			canvas.draw_circle(points[point_index] + Vector2(cos(angle), sin(angle)) * radius, maxf(0.65, width * rng.randf_range(0.08, 0.17)), dot_color, true, -1.0, true)
			dots += 1
