# SPDX-License-Identifier: GPL-3.0-or-later
class_name StrokeGeometry
extends RefCounted

const EPSILON: float = 0.0001


static func build_smooth_path(source: PackedVector2Array, min_spacing: float = 1.25, curve_steps: int = 3) -> PackedVector2Array:
	if source.size() <= 2:
		return source.duplicate()
	var decimated: PackedVector2Array = _decimate(source, maxf(0.25, min_spacing))
	if decimated.size() <= 2:
		return decimated
	var filtered: PackedVector2Array = PackedVector2Array()
	filtered.resize(decimated.size())
	filtered[0] = decimated[0]
	for index: int in range(1, decimated.size() - 1):
		filtered[index] = decimated[index - 1] * 0.18 + decimated[index] * 0.64 + decimated[index + 1] * 0.18
	filtered[filtered.size() - 1] = decimated[decimated.size() - 1]
	return _quadratic_midpoint_path(filtered, clampi(curve_steps, 1, 8))


static func bounds_for_points(points: PackedVector2Array, padding: float = 0.0) -> Rect2:
	if points.is_empty():
		return Rect2()
	var minimum: Vector2 = points[0]
	var maximum: Vector2 = points[0]
	for point: Vector2 in points:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	var pad: float = maxf(0.0, padding)
	return Rect2(minimum - Vector2.ONE * pad, maximum - minimum + Vector2.ONE * pad * 2.0)


static func to_local_points(points: PackedVector2Array, bounds: Rect2) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	result.resize(points.size())
	for index: int in range(points.size()):
		result[index] = points[index] - bounds.position
	return result


static func transformed_points(local_points: PackedVector2Array, original_size: Vector2, bounds: Rect2) -> PackedVector2Array:
	var safe_original: Vector2 = Vector2(maxf(original_size.x, EPSILON), maxf(original_size.y, EPSILON))
	var scale: Vector2 = Vector2(bounds.size.x / safe_original.x, bounds.size.y / safe_original.y)
	var result: PackedVector2Array = PackedVector2Array()
	result.resize(local_points.size())
	for index: int in range(local_points.size()):
		result[index] = bounds.position + local_points[index] * scale
	return result


static func simplify_polyline(points: PackedVector2Array, tolerance: float, maximum_points: int = 0) -> PackedVector2Array:
	if points.size() <= 2:
		return points.duplicate()
	var safe_tolerance: float = maxf(0.0, tolerance)
	if safe_tolerance <= EPSILON and (maximum_points <= 0 or points.size() <= maximum_points):
		return points.duplicate()
	# Bound the input to the geometric simplifier when a far-zoom point budget
	# is present. This keeps a single exceptionally dense stroke from turning an
	# otherwise cheap LOD transition into a long main-thread spike.
	var working_points: PackedVector2Array = points
	if maximum_points > 1 and points.size() > maximum_points * 4:
		working_points = _decimate_to_maximum(points, maximum_points * 4)
	var keep: PackedByteArray = PackedByteArray()
	keep.resize(working_points.size())
	keep[0] = 1
	keep[working_points.size() - 1] = 1
	var spans: Array[Vector2i] = []
	spans.append(Vector2i(0, working_points.size() - 1))
	var tolerance_squared: float = safe_tolerance * safe_tolerance
	while not spans.is_empty():
		var span: Vector2i = spans.pop_back()
		if span.y - span.x <= 1:
			continue
		var start: Vector2 = working_points[span.x]
		var finish: Vector2 = working_points[span.y]
		var farthest_index: int = -1
		var farthest_distance_squared: float = tolerance_squared
		for index: int in range(span.x + 1, span.y):
			var distance_squared: float = point_segment_distance_squared(working_points[index], start, finish)
			if distance_squared > farthest_distance_squared:
				farthest_distance_squared = distance_squared
				farthest_index = index
		if farthest_index < 0:
			continue
		keep[farthest_index] = 1
		spans.append(Vector2i(span.x, farthest_index))
		spans.append(Vector2i(farthest_index, span.y))
	var simplified: PackedVector2Array = PackedVector2Array()
	for index: int in range(working_points.size()):
		if keep[index] != 0:
			simplified.append(working_points[index])
	if maximum_points > 1 and simplified.size() > maximum_points:
		return _decimate_to_maximum(simplified, maximum_points)
	return simplified


static func simplify_polyline_fast(points: PackedVector2Array, tolerance: float, maximum_points: int = 0) -> PackedVector2Array:
	if points.size() <= 2:
		return points.duplicate()
	var safe_tolerance: float = maxf(0.0, tolerance)
	var working_points: PackedVector2Array = points
	# The fast path is intentionally linear and bounded. Unlike RDP it never walks
	# the same span repeatedly, which makes zoom-triggered render LOD preparation
	# predictable even for exceptionally dense handwriting.
	if maximum_points > 1 and points.size() > maximum_points * 3:
		working_points = _decimate_to_maximum(points, maximum_points * 3)
	var simplified: PackedVector2Array = PackedVector2Array()
	simplified.append(working_points[0])
	var tolerance_squared: float = safe_tolerance * safe_tolerance
	for index: int in range(1, working_points.size() - 1):
		if tolerance_squared <= EPSILON or simplified[simplified.size() - 1].distance_squared_to(working_points[index]) >= tolerance_squared:
			simplified.append(working_points[index])
	var last_point: Vector2 = working_points[working_points.size() - 1]
	if simplified[simplified.size() - 1] != last_point:
		simplified.append(last_point)
	if maximum_points > 1 and simplified.size() > maximum_points:
		return _decimate_to_maximum(simplified, maximum_points)
	return simplified


static func point_hits_polyline(point: Vector2, points: PackedVector2Array, radius: float) -> bool:
	if points.is_empty():
		return false
	var radius_sq: float = radius * radius
	if points.size() == 1:
		return point.distance_squared_to(points[0]) <= radius_sq
	for index: int in range(points.size() - 1):
		if point_segment_distance_squared(point, points[index], points[index + 1]) <= radius_sq:
			return true
	return false


static func segment_hits_polyline(a: Vector2, b: Vector2, points: PackedVector2Array, radius: float) -> bool:
	if points.is_empty():
		return false
	var radius_sq: float = radius * radius
	if points.size() == 1:
		return point_segment_distance_squared(points[0], a, b) <= radius_sq
	for index: int in range(points.size() - 1):
		if segment_distance_squared(a, b, points[index], points[index + 1]) <= radius_sq:
			return true
	return false


static func point_segment_distance_squared(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var length_sq: float = ab.length_squared()
	if length_sq <= EPSILON:
		return point.distance_squared_to(a)
	var t: float = clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
	return point.distance_squared_to(a + ab * t)


static func segment_distance_squared(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> float:
	if _segments_intersect(a0, a1, b0, b1):
		return 0.0
	return minf(
		minf(point_segment_distance_squared(a0, b0, b1), point_segment_distance_squared(a1, b0, b1)),
		minf(point_segment_distance_squared(b0, a0, a1), point_segment_distance_squared(b1, a0, a1))
	)


static func _decimate_to_maximum(source: PackedVector2Array, maximum_points: int) -> PackedVector2Array:
	var limit: int = maxi(2, maximum_points)
	if source.size() <= limit:
		return source.duplicate()
	var result: PackedVector2Array = PackedVector2Array()
	result.resize(limit)
	var last_source_index: int = source.size() - 1
	var last_target_index: int = limit - 1
	for target_index: int in range(limit):
		var source_index: int = int(round(float(target_index) * float(last_source_index) / float(last_target_index)))
		result[target_index] = source[clampi(source_index, 0, last_source_index)]
	return result


static func _decimate(source: PackedVector2Array, spacing: float) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	if source.is_empty():
		return result
	result.append(source[0])
	var spacing_sq: float = spacing * spacing
	for index: int in range(1, source.size() - 1):
		if result[result.size() - 1].distance_squared_to(source[index]) >= spacing_sq:
			result.append(source[index])
	if source.size() > 1 and result[result.size() - 1] != source[source.size() - 1]:
		result.append(source[source.size() - 1])
	return result


static func _quadratic_midpoint_path(points: PackedVector2Array, steps: int) -> PackedVector2Array:
	if points.size() <= 2:
		return points.duplicate()
	var result: PackedVector2Array = PackedVector2Array()
	result.append(points[0])
	for index: int in range(1, points.size() - 1):
		var previous: Vector2 = points[index - 1]
		var current: Vector2 = points[index]
		var next: Vector2 = points[index + 1]
		var start: Vector2 = (previous + current) * 0.5
		var finish: Vector2 = (current + next) * 0.5
		if index == 1:
			start = points[0]
		for step: int in range(1, steps + 1):
			var t: float = float(step) / float(steps)
			var inv: float = 1.0 - t
			result.append(inv * inv * start + 2.0 * inv * t * current + t * t * finish)
	result.append(points[points.size() - 1])
	return result


static func _segments_intersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var ab_c: float = (b - a).cross(c - a)
	var ab_d: float = (b - a).cross(d - a)
	var cd_a: float = (d - c).cross(a - c)
	var cd_b: float = (d - c).cross(b - c)
	return ((ab_c > 0.0 and ab_d < 0.0) or (ab_c < 0.0 and ab_d > 0.0)) and ((cd_a > 0.0 and cd_b < 0.0) or (cd_a < 0.0 and cd_b > 0.0))
