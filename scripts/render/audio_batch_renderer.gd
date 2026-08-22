# SPDX-License-Identifier: GPL-3.0-or-later
class_name AudioBatchRenderer
extends Node2D

var _runtime: BoardRuntime
var _media: AudioMediaService
var _visible_ids: PackedInt64Array = PackedInt64Array()
var _hidden_ids: Dictionary = {}
var _zoom: float = 1.0
var _card_style: StyleBoxFlat = StyleBoxFlat.new()


func rebuild(
	runtime: BoardRuntime,
	media: AudioMediaService,
	candidate_ids: PackedInt64Array,
	max_visible: int,
	zoom: float,
	focus_world: Vector2 = Vector2.ZERO
) -> void:
	_runtime = runtime
	_media = media
	_zoom = maxf(zoom, 0.001)
	_visible_ids = PackedInt64Array()
	if runtime == null:
		queue_redraw()
		return
	var ids: Array[int] = []
	for entity_id: int in candidate_ids:
		if runtime.model.audios.contains(entity_id) and runtime.model.transforms.is_visible(entity_id):
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


func notify_waveform_ready(_asset_id: String) -> void:
	queue_redraw()


func _draw() -> void:
	if _runtime == null:
		return
	_configure_card_style()
	for entity_id: int in _visible_ids:
		if _hidden_ids.has(entity_id) or not _runtime.model.audios.contains(entity_id):
			continue
		_draw_audio_card(_runtime.model.get_entity_bounds(entity_id), entity_id)


func _draw_audio_card(bounds: Rect2, entity_id: int) -> void:
	if not bounds.has_area():
		return
	var asset_id: String = _runtime.model.audios.get_asset_id(entity_id)
	var screen_size: Vector2 = bounds.size * _zoom
	var compact: bool = screen_size.x < 170.0 or screen_size.y < 64.0
	var tiny: bool = screen_size.x < 72.0 or screen_size.y < 28.0
	var border: Color = Color(0.16, 0.42, 0.31, 0.38)
	draw_style_box(_card_style, bounds)

	var inner_margin: float = minf(14.0 / _zoom, bounds.size.y * 0.18)
	var inner: Rect2 = bounds.grow(-inner_margin)
	if not inner.has_area():
		return
	var button_extent: float = minf(inner.size.y, 42.0 / _zoom)
	if tiny:
		button_extent = minf(inner.size.y, inner.size.x * 0.22)
	var button_rect: Rect2 = Rect2(inner.position, Vector2(button_extent, inner.size.y))
	var button_center: Vector2 = button_rect.get_center()
	var button_radius: float = minf(button_rect.size.x, button_rect.size.y) * 0.38
	draw_circle(button_center, button_radius, NotLightTheme.semantic_color("accent"))
	var triangle_size: float = button_radius * 0.82
	var triangle: PackedVector2Array = PackedVector2Array([
		button_center + Vector2(-triangle_size * 0.24, -triangle_size * 0.48),
		button_center + Vector2(-triangle_size * 0.24, triangle_size * 0.48),
		button_center + Vector2(triangle_size * 0.56, 0.0),
	])
	var triangle_color: Color = Color("#fbfcf8")
	draw_primitive(
		triangle,
		PackedColorArray([triangle_color, triangle_color, triangle_color]),
		PackedVector2Array()
	)

	if tiny:
		var line_left: float = button_rect.end.x + minf(8.0 / _zoom, inner.size.x * 0.06)
		var line_y: float = inner.get_center().y
		draw_line(Vector2(line_left, line_y), Vector2(inner.end.x, line_y), border, maxf(1.0 / _zoom, bounds.size.y * 0.035), true)
		return

	var info_left: float = button_rect.end.x + minf(12.0 / _zoom, inner.size.x * 0.06)
	var info_rect: Rect2 = Rect2(Vector2(info_left, inner.position.y), Vector2(maxf(1.0, inner.end.x - info_left), inner.size.y))
	var waveform_height_ratio: float = 0.76 if compact else 0.55
	var waveform_rect: Rect2 = Rect2(info_rect.position, Vector2(info_rect.size.x, info_rect.size.y * waveform_height_ratio))
	if not compact:
		waveform_rect.position.y += info_rect.size.y * 0.15
	# Far-zoom cards intentionally use the cheap placeholder and do not enqueue
	# hundreds of FFmpeg waveform jobs merely because they became visible.
	var request_waveform: bool = not compact
	var waveform: Texture2D = _media.get_waveform(asset_id, request_waveform) if _media != null else null
	if waveform != null:
		draw_texture_rect(waveform, waveform_rect, false, Color(0.13, 0.46, 0.32, 0.80))
	else:
		_draw_waveform_placeholder(waveform_rect)

	if compact:
		return
	var duration: float = _runtime.model.audios.get_duration(entity_id)
	var duration_text: String = _format_time(duration)
	var title: String = _runtime.model.audios.get_instance_title(entity_id)
	if title.is_empty() and _media != null and _media.library != null:
		var asset: Dictionary = _media.library.get_asset(asset_id)
		title = str(asset.get("display_name", NotLightL10n.text("board.asset.audio")))
	if title.is_empty():
		title = NotLightL10n.text("board.asset.audio")
	var font: Font = ThemeDB.fallback_font
	var font_size: int = clampi(int(round(13.0 / _zoom)), 8, 30)
	var baseline_y: float = info_rect.end.y - minf(5.0 / _zoom, info_rect.size.y * 0.08)
	var duration_width: float = font.get_string_size(duration_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	draw_string(font, Vector2(info_rect.position.x, baseline_y), title, HORIZONTAL_ALIGNMENT_LEFT, maxf(0.0, info_rect.size.x - duration_width - 10.0 / _zoom), font_size, Color("#303633"))
	if duration > 0.0:
		draw_string(font, Vector2(info_rect.end.x - duration_width, baseline_y), duration_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color("#6d756f"))


func _draw_waveform_placeholder(rect: Rect2) -> void:
	if not rect.has_area():
		return
	var bars: int = clampi(int(rect.size.x * _zoom / 8.0), 8, 48)
	var width: float = rect.size.x / float(bars)
	var center_y: float = rect.get_center().y
	for index: int in range(bars):
		var phase: float = float((index * 37 + 11) % 17) / 16.0
		var amplitude: float = rect.size.y * (0.14 + 0.28 * phase)
		var x: float = rect.position.x + (float(index) + 0.5) * width
		draw_line(Vector2(x, center_y - amplitude), Vector2(x, center_y + amplitude), Color(0.18, 0.48, 0.35, 0.30), maxf(width * 0.34, 0.75 / _zoom), true)


func _configure_card_style() -> void:
	_card_style.bg_color = Color("#f3f3ed")
	_card_style.border_color = Color(0.16, 0.42, 0.31, 0.38)
	var border_size: int = maxi(1, int(round(1.0 / _zoom)))
	_card_style.border_width_left = border_size
	_card_style.border_width_top = border_size
	_card_style.border_width_right = border_size
	_card_style.border_width_bottom = border_size
	var corner: int = maxi(1, int(round(14.0 / _zoom)))
	_card_style.corner_radius_top_left = corner
	_card_style.corner_radius_top_right = corner
	_card_style.corner_radius_bottom_right = corner
	_card_style.corner_radius_bottom_left = corner


func _format_time(seconds: float) -> String:
	var total: int = maxi(0, int(round(seconds)))
	var hours: int = total / 3600
	var minutes: int = (total % 3600) / 60
	var secs: int = total % 60
	if hours > 0:
		return NotLightL10n.text("ui.format.time_hms") % [hours, minutes, secs]
	return NotLightL10n.text("ui.format.time_ms") % [minutes, secs]
