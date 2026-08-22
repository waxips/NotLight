# SPDX-License-Identifier: GPL-3.0-or-later
class_name VideoBatchRenderer
extends Node2D

var _runtime: BoardRuntime
var _media: VideoMediaService
var _visible_ids: PackedInt64Array = PackedInt64Array()
var _hidden_ids: Dictionary = {}
var _zoom: float = 1.0


func rebuild(
	runtime: BoardRuntime,
	media: VideoMediaService,
	candidate_ids: PackedInt64Array,
	max_visible: int,
	zoom: float,
	focus_world: Vector2 = Vector2.ZERO
) -> void:
	_runtime = runtime
	_media = media
	_zoom = zoom
	_visible_ids = PackedInt64Array()
	if runtime == null:
		queue_redraw()
		return
	var ids: Array[int] = []
	for entity_id: int in candidate_ids:
		if runtime.model.videos.contains(entity_id) and runtime.model.transforms.is_visible(entity_id):
			ids.append(entity_id)
	var limit: int = maxi(1, max_visible)
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
	_visible_ids.resize(ids.size())
	for index: int in range(ids.size()):
		_visible_ids[index] = ids[index]
	queue_redraw()


func set_hidden_entity_ids(hidden_ids: Dictionary) -> void:
	_hidden_ids = hidden_ids.duplicate()
	queue_redraw()


func notify_thumbnail_ready(_asset_id: String) -> void:
	queue_redraw()


func _draw() -> void:
	if _runtime == null:
		return
	for entity_id: int in _visible_ids:
		if _hidden_ids.has(entity_id) or not _runtime.model.videos.contains(entity_id):
			continue
		var bounds: Rect2 = _runtime.model.get_entity_bounds(entity_id)
		var asset_id: String = _runtime.model.videos.get_asset_id(entity_id)
		_draw_video_card(bounds, asset_id, entity_id)


func _draw_video_card(bounds: Rect2, asset_id: String, entity_id: int) -> void:
	var background: Color = Color("#202623")
	draw_rect(bounds, background, true)
	var texture: Texture2D = _media.get_thumbnail(asset_id) if _media != null else null
	if texture != null:
		var target: Rect2 = _fit_texture_rect(texture, bounds)
		draw_texture_rect(texture, target, false)
	var overlay_height: float = minf(42.0, bounds.size.y * 0.18)
	var footer: Rect2 = Rect2(
		Vector2(bounds.position.x, bounds.end.y - overlay_height),
		Vector2(bounds.size.x, overlay_height)
	)
	draw_rect(footer, Color(0.05, 0.08, 0.06, 0.72), true)

	var radius: float = clampf(minf(bounds.size.x, bounds.size.y) * 0.095, 14.0, 36.0)
	var center: Vector2 = bounds.get_center()
	draw_circle(center, radius, Color(0.96, 0.98, 0.95, 0.92))
	var triangle_size: float = radius * 0.82
	var triangle: PackedVector2Array = PackedVector2Array([
		center + Vector2(-triangle_size * 0.28, -triangle_size * 0.50),
		center + Vector2(-triangle_size * 0.28, triangle_size * 0.50),
		center + Vector2(triangle_size * 0.58, 0.0),
	])
	var triangle_color: Color = NotLightTheme.semantic_color("accent")
	draw_primitive(
		triangle,
		PackedColorArray([triangle_color, triangle_color, triangle_color]),
		PackedVector2Array()
	)

	if bounds.size.x >= 140.0 and bounds.size.y >= 90.0:
		var duration: float = _runtime.model.videos.get_duration(entity_id)
		if duration > 0.0:
			var font: Font = ThemeDB.fallback_font
			var font_size: int = clampi(int(round(12.0 / maxf(_zoom, 0.55))), 9, 14)
			draw_string(
				font,
				Vector2(bounds.position.x + 12.0, bounds.end.y - 13.0),
				_format_time(duration),
				HORIZONTAL_ALIGNMENT_LEFT,
				-1.0,
				font_size,
				Color(0.95, 0.97, 0.95, 0.95)
			)


func _fit_texture_rect(texture: Texture2D, bounds: Rect2) -> Rect2:
	var size_value: Vector2 = texture.get_size()
	if size_value.x <= 0.0 or size_value.y <= 0.0:
		return bounds
	var scale_value: float = minf(bounds.size.x / size_value.x, bounds.size.y / size_value.y)
	var fitted: Vector2 = size_value * scale_value
	return Rect2(bounds.get_center() - fitted * 0.5, fitted)


func _format_time(seconds: float) -> String:
	var total: int = maxi(0, int(round(seconds)))
	var hours: int = total / 3600
	var minutes: int = (total % 3600) / 60
	var secs: int = total % 60
	if hours > 0:
		return NotLightL10n.text("ui.format.time_hms") % [hours, minutes, secs]
	return NotLightL10n.text("ui.format.time_ms") % [minutes, secs]
