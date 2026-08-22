# SPDX-License-Identifier: GPL-3.0-or-later
class_name ConnectorGeometry
extends RefCounted

const ANCHOR_TOP: int = 0
const ANCHOR_RIGHT: int = 1
const ANCHOR_BOTTOM: int = 2
const ANCHOR_LEFT: int = 3
const ANCHOR_COUNT: int = 4
const DEFAULT_SAMPLES: int = 32
const MIN_SEGMENT_SAMPLES: int = 10
const MAX_SEGMENT_SAMPLES: int = 96
const DIRECTION_NONE: int = 0
const DIRECTION_FORWARD: int = 1
const DIRECTION_REVERSE: int = 2
const DIRECTION_BOTH: int = 3
const DEFAULT_DIRECTION: int = DIRECTION_FORWARD


static func anchor_position(bounds: Rect2, anchor: int) -> Vector2:
	match clampi(anchor, ANCHOR_TOP, ANCHOR_LEFT):
		ANCHOR_TOP:
			return Vector2(bounds.get_center().x, bounds.position.y)
		ANCHOR_RIGHT:
			return Vector2(bounds.end.x, bounds.get_center().y)
		ANCHOR_BOTTOM:
			return Vector2(bounds.get_center().x, bounds.end.y)
		_:
			return Vector2(bounds.position.x, bounds.get_center().y)


static func anchor_normal(anchor: int) -> Vector2:
	match clampi(anchor, ANCHOR_TOP, ANCHOR_LEFT):
		ANCHOR_TOP:
			return Vector2.UP
		ANCHOR_RIGHT:
			return Vector2.RIGHT
		ANCHOR_BOTTOM:
			return Vector2.DOWN
		_:
			return Vector2.LEFT


static func nearest_anchor(bounds: Rect2, world_position: Vector2) -> int:
	var best_anchor: int = ANCHOR_TOP
	var best_distance: float = INF
	for anchor: int in range(ANCHOR_COUNT):
		var distance: float = anchor_position(bounds, anchor).distance_squared_to(world_position)
		if distance < best_distance:
			best_distance = distance
			best_anchor = anchor
	return best_anchor


static func control_points(
	start: Vector2,
	start_anchor: int,
	finish: Vector2,
	finish_anchor: int
) -> PackedVector2Array:
	var distance: float = start.distance_to(finish)
	var tangent_length: float = clampf(distance * 0.42, 52.0, 260.0)
	var start_control: Vector2 = start + anchor_normal(start_anchor) * tangent_length
	var finish_control: Vector2 = finish + anchor_normal(finish_anchor) * tangent_length
	return PackedVector2Array([start, start_control, finish_control, finish])


static func sample_curve(
	start: Vector2,
	start_anchor: int,
	finish: Vector2,
	finish_anchor: int,
	sample_count: int = DEFAULT_SAMPLES
) -> PackedVector2Array:
	var controls: PackedVector2Array = control_points(start, start_anchor, finish, finish_anchor)
	return _sample_cubic(controls[0], controls[1], controls[2], controls[3], maxi(4, sample_count), true)


static func sample_routed_curve(
	start: Vector2,
	start_anchor: int,
	finish: Vector2,
	finish_anchor: int,
	router_points: PackedVector2Array,
	zoom: float = 1.0,
	maximum_total_samples: int = 240
) -> PackedVector2Array:
	if router_points.is_empty():
		return sample_curve(
			start,
			start_anchor,
			finish,
			finish_anchor,
			_recommended_samples(start.distance_to(finish), zoom, maximum_total_samples)
		)
	var knots: PackedVector2Array = PackedVector2Array()
	knots.append(start)
	for point: Vector2 in router_points:
		knots.append(point)
	knots.append(finish)
	var tangents: PackedVector2Array = PackedVector2Array()
	tangents.resize(knots.size())
	tangents[0] = anchor_normal(start_anchor)
	tangents[knots.size() - 1] = -anchor_normal(finish_anchor)
	for index: int in range(1, knots.size() - 1):
		var tangent: Vector2 = (knots[index + 1] - knots[index - 1]).normalized()
		if tangent.is_zero_approx():
			tangent = (knots[index + 1] - knots[index]).normalized()
		tangents[index] = tangent
	var result: PackedVector2Array = PackedVector2Array()
	var remaining_budget: int = maxi(16, maximum_total_samples)
	var segment_count: int = knots.size() - 1
	for segment_index: int in range(segment_count):
		var p0: Vector2 = knots[segment_index]
		var p3: Vector2 = knots[segment_index + 1]
		var segment_distance: float = p0.distance_to(p3)
		var previous_distance: float = segment_distance
		var next_distance: float = segment_distance
		if segment_index > 0:
			previous_distance = knots[segment_index - 1].distance_to(p0)
		if segment_index + 2 < knots.size():
			next_distance = p3.distance_to(knots[segment_index + 2])
		var outgoing_handle: float = minf(segment_distance, previous_distance) * 0.32
		var incoming_handle: float = minf(segment_distance, next_distance) * 0.32
		if segment_index == 0:
			outgoing_handle = clampf(segment_distance * 0.38, 36.0, 220.0)
		if segment_index == segment_count - 1:
			incoming_handle = clampf(segment_distance * 0.38, 36.0, 220.0)
		var p1: Vector2 = p0 + tangents[segment_index] * outgoing_handle
		var p2: Vector2 = p3 - tangents[segment_index + 1] * incoming_handle
		var segments_left: int = segment_count - segment_index
		var segment_budget: int = maxi(MIN_SEGMENT_SAMPLES, int(remaining_budget / maxi(segments_left, 1)))
		var samples: int = _recommended_samples(segment_distance, zoom, segment_budget)
		var sampled: PackedVector2Array = _sample_cubic(p0, p1, p2, p3, samples, segment_index == 0)
		for point: Vector2 in sampled:
			result.append(point)
		remaining_budget = maxi(0, remaining_budget - samples)
	return result


static func router_insertion_index(
	start: Vector2,
	finish: Vector2,
	router_points: PackedVector2Array,
	world_position: Vector2
) -> int:
	var knots: PackedVector2Array = PackedVector2Array()
	knots.append(start)
	for point: Vector2 in router_points:
		knots.append(point)
	knots.append(finish)
	var best_segment: int = 0
	var best_distance: float = INF
	for segment_index: int in range(knots.size() - 1):
		var distance: float = _distance_squared_to_segment(
			world_position,
			knots[segment_index],
			knots[segment_index + 1]
		)
		if distance < best_distance:
			best_distance = distance
			best_segment = segment_index
	return clampi(best_segment, 0, router_points.size())


static func curve_bounds(
	start: Vector2,
	start_anchor: int,
	finish: Vector2,
	finish_anchor: int,
	router_points: PackedVector2Array = PackedVector2Array()
) -> Rect2:
	var points: PackedVector2Array = sample_routed_curve(start, start_anchor, finish, finish_anchor, router_points, 1.0, 96)
	if points.is_empty():
		return Rect2(start, Vector2.ONE)
	var minimum: Vector2 = points[0]
	var maximum: Vector2 = points[0]
	for point: Vector2 in points:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	return Rect2(minimum, maximum - minimum).grow(18.0)


static func distance_squared_to_curve(
	start: Vector2,
	start_anchor: int,
	finish: Vector2,
	finish_anchor: int,
	world_position: Vector2,
	router_points: PackedVector2Array = PackedVector2Array(),
	sample_count: int = 48
) -> float:
	var points: PackedVector2Array = sample_routed_curve(
		start,
		start_anchor,
		finish,
		finish_anchor,
		router_points,
		1.0,
		maxi(16, sample_count)
	)
	var best_distance: float = INF
	for index: int in range(1, points.size()):
		best_distance = minf(
			best_distance,
			_distance_squared_to_segment(world_position, points[index - 1], points[index])
		)
	return best_distance


static func append_curve_segments(
	target: PackedVector2Array,
	points: PackedVector2Array,
	arrow_length: float = 13.0,
	arrow_width: float = 7.0,
	arrow_at_start: bool = false,
	arrow_at_end: bool = true
) -> PackedVector2Array:
	for index: int in range(1, points.size()):
		target.append(points[index - 1])
		target.append(points[index])
	if points.size() < 2:
		return target
	if arrow_at_start:
		_append_arrowhead(target, points[0], points[1], arrow_length, arrow_width)
	if arrow_at_end:
		_append_arrowhead(
			target,
			points[points.size() - 1],
			points[points.size() - 2],
			arrow_length,
			arrow_width
		)
	return target


static func direction_has_source_arrow(direction: int) -> bool:
	return direction == DIRECTION_REVERSE or direction == DIRECTION_BOTH


static func direction_has_target_arrow(direction: int) -> bool:
	return direction == DIRECTION_FORWARD or direction == DIRECTION_BOTH


static func _append_arrowhead(
	target: PackedVector2Array,
	tip: Vector2,
	previous: Vector2,
	arrow_length: float,
	arrow_width: float
) -> void:
	var direction: Vector2 = (tip - previous).normalized()
	if direction.is_zero_approx():
		return
	var perpendicular: Vector2 = Vector2(-direction.y, direction.x)
	var base: Vector2 = tip - direction * arrow_length
	target.append(tip)
	target.append(base + perpendicular * arrow_width)
	target.append(tip)
	target.append(base - perpendicular * arrow_width)


static func _recommended_samples(distance: float, zoom: float, maximum: int) -> int:
	var screen_distance: float = distance * maxf(zoom, 0.08)
	var desired: int = int(ceil(screen_distance / 7.0))
	return clampi(desired, MIN_SEGMENT_SAMPLES, mini(MAX_SEGMENT_SAMPLES, maxi(MIN_SEGMENT_SAMPLES, maximum)))


static func _sample_cubic(
	p0: Vector2,
	p1: Vector2,
	p2: Vector2,
	p3: Vector2,
	sample_count: int,
	include_start: bool
) -> PackedVector2Array:
	var safe_count: int = maxi(4, sample_count)
	var result: PackedVector2Array = PackedVector2Array()
	var first_index: int = 0 if include_start else 1
	result.resize(safe_count + 1 - first_index)
	var write_index: int = 0
	for index: int in range(first_index, safe_count + 1):
		var t: float = float(index) / float(safe_count)
		var inverse: float = 1.0 - t
		result[write_index] = (
			p0 * inverse * inverse * inverse
			+ p1 * 3.0 * inverse * inverse * t
			+ p2 * 3.0 * inverse * t * t
			+ p3 * t * t * t
		)
		write_index += 1
	return result


static func _distance_squared_to_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment: Vector2 = finish - start
	var length_squared: float = segment.length_squared()
	if length_squared <= 0.000001:
		return point.distance_squared_to(start)
	var factor: float = clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_squared_to(start + segment * factor)
