# SPDX-License-Identifier: GPL-3.0-or-later
class_name PdfBatchRenderer
extends Node2D

var _runtime: BoardRuntime
var _media: PdfMediaService
var _visible_ids: PackedInt64Array = PackedInt64Array()
var _hidden_ids: Dictionary = {}
var _zoom: float = 1.0


func rebuild(runtime: BoardRuntime, media: PdfMediaService, candidate_ids: PackedInt64Array, max_visible: int, zoom: float, focus_world: Vector2 = Vector2.ZERO) -> void:
	_runtime = runtime
	_media = media
	_zoom = maxf(zoom, 0.08)
	var ids: Array[int] = []
	if runtime != null:
		for entity_id: int in candidate_ids:
			if runtime.model.pdfs.contains(entity_id) and runtime.model.transforms.is_visible(entity_id):
				ids.append(entity_id)
	var limit: int = maxi(1, max_visible)
	if ids.size() > limit:
		ids.sort_custom(func(left_id: int, right_id: int) -> bool:
			var left_distance: float = runtime.model.get_entity_bounds(left_id).get_center().distance_squared_to(focus_world)
			var right_distance: float = runtime.model.get_entity_bounds(right_id).get_center().distance_squared_to(focus_world)
			return left_distance < right_distance if not is_equal_approx(left_distance, right_distance) else left_id < right_id
		)
		ids.resize(limit)
	ids.sort_custom(func(left_id: int, right_id: int) -> bool:
		var left_z: int = runtime.model.get_entity_z_order(left_id)
		var right_z: int = runtime.model.get_entity_z_order(right_id)
		return left_z < right_z if left_z != right_z else left_id < right_id
	)
	_visible_ids = PackedInt64Array()
	_visible_ids.resize(ids.size())
	for index: int in range(ids.size()):
		_visible_ids[index] = ids[index]
	queue_redraw()


func set_hidden_entity_ids(hidden_ids: Dictionary) -> void:
	_hidden_ids = hidden_ids.duplicate()
	queue_redraw()


func notify_page_ready(_asset_id: String, _page_index: int) -> void:
	queue_redraw()


func _draw() -> void:
	if _runtime == null:
		return
	for entity_id: int in _visible_ids:
		if _hidden_ids.has(entity_id) or not _runtime.model.pdfs.contains(entity_id):
			continue
		_draw_pdf(entity_id)


func _draw_pdf(entity_id: int) -> void:
	var bounds: Rect2 = _runtime.model.get_entity_bounds(entity_id)
	var asset_id: String = _runtime.model.pdfs.get_asset_id(entity_id)
	var page_index: int = _runtime.model.pdfs.get_page_index(entity_id)
	var desired_extent: float = maxf(bounds.size.x, bounds.size.y) * _zoom
	var texture: Texture2D = _media.request_page(asset_id, page_index, desired_extent) if _media != null else null
	var paper: Color = Color("#fffdf5")
	var border: Color = Color("#9fb09e")
	if _media != null and not _media.get_failure_message(asset_id).is_empty():
		paper = Color("#f8eeee")
		border = NotLightTheme.semantic_color("danger")
	draw_rect(bounds, paper, true)
	if texture != null:
		var fitted: Rect2 = _fit_texture_rect(texture, bounds.grow(-2.0))
		draw_texture_rect(texture, fitted, false)
	draw_rect(bounds, Color(border, 0.75), false, 1.2, true)
	if texture == null:
		_draw_placeholder(bounds, asset_id, page_index)
	elif bounds.size.x >= 120.0 and bounds.size.y >= 90.0:
		_draw_page_badge(bounds, page_index, _runtime.model.pdfs.get_page_count(entity_id))


func _draw_placeholder(bounds: Rect2, asset_id: String, page_index: int) -> void:
	var font: Font = ThemeDB.fallback_font
	var failure: String = _media.get_failure_message(asset_id) if _media != null else ""
	var label: String = NotLightL10n.text("library.kind.pdf")
	if not failure.is_empty():
		label = NotLightL10n.text("ui.format.failure_badge") % label
	var font_size: int = clampi(int(round(22.0 / maxf(_zoom, 0.6))), 13, 24)
	var text_size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	draw_string(font, bounds.get_center() + Vector2(-text_size.x * 0.5, text_size.y * 0.25), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, NotLightTheme.semantic_color("accent"))
	if bounds.size.x >= 150.0 and bounds.size.y >= 110.0:
		_draw_page_badge(bounds, page_index, 0)


func _draw_page_badge(bounds: Rect2, page_index: int, page_count: int) -> void:
	var font: Font = ThemeDB.fallback_font
	var text: String = NotLightL10n.text("ui.format.page_index_total") % [page_index + 1, page_count] if page_count > 0 else NotLightL10n.text("ui.format.integer") % (page_index + 1)
	var font_size: int = clampi(int(round(11.0 / maxf(_zoom, 0.65))), 9, 12)
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var badge_size: Vector2 = text_size + Vector2(14.0, 8.0)
	var badge: Rect2 = Rect2(bounds.end - badge_size - Vector2(8.0, 8.0), badge_size)
	draw_rect(badge, Color(0.18, 0.28, 0.22, 0.82), true)
	draw_string(font, badge.position + Vector2(7.0, 5.0 + text_size.y * 0.72), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color("#f5f1df"))


func _fit_texture_rect(texture: Texture2D, bounds: Rect2) -> Rect2:
	var source_size: Vector2 = texture.get_size()
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return bounds
	var scale_value: float = minf(bounds.size.x / source_size.x, bounds.size.y / source_size.y)
	var fitted_size: Vector2 = source_size * scale_value
	return Rect2(bounds.get_center() - fitted_size * 0.5, fitted_size)
