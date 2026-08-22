# SPDX-License-Identifier: GPL-3.0-or-later
class_name FormulaBatchRenderer
extends Node2D

var _runtime: BoardRuntime
var _service: FormulaRenderService
var _visible_ids: PackedInt64Array = PackedInt64Array()
var _hidden_ids: Dictionary = {}
var _zoom: float = 1.0


func rebuild(
	runtime: BoardRuntime,
	service: FormulaRenderService,
	candidate_ids: PackedInt64Array,
	max_visible: int,
	zoom: float,
	focus_world: Vector2 = Vector2.ZERO
) -> void:
	_runtime = runtime
	_service = service
	_zoom = maxf(zoom, 0.08)
	var ids: Array[int] = []
	if runtime != null:
		for entity_id: int in candidate_ids:
			if runtime.model.formulas.contains(entity_id) and runtime.model.transforms.is_visible(entity_id):
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
	_visible_ids.resize(ids.size())
	for index: int in range(ids.size()):
		_visible_ids[index] = ids[index]
	queue_redraw()


func set_hidden_entity_ids(hidden_ids: Dictionary) -> void:
	_hidden_ids = hidden_ids.duplicate()
	queue_redraw()


func notify_texture_ready(_cache_key: String) -> void:
	queue_redraw()


func _draw() -> void:
	if _runtime == null:
		return
	for entity_id: int in _visible_ids:
		if _hidden_ids.has(entity_id) or not _runtime.model.formulas.contains(entity_id):
			continue
		_draw_formula(entity_id)


func _draw_formula(entity_id: int) -> void:
	var bounds: Rect2 = _runtime.model.get_entity_bounds(entity_id)
	var record: Dictionary = _runtime.model.formulas.get_record(entity_id)
	var desired_extent: float = maxf(bounds.size.x, bounds.size.y) * _zoom
	var texture: Texture2D = _service.request_texture(record, desired_extent) if _service != null else null
	var cache_key: String = _service.cache_key_for_record(record, desired_extent) if _service != null else ""
	var failure: String = _service.get_failure_message(cache_key) if _service != null and not cache_key.is_empty() else ""
	if texture != null:
		# Formula textures are neutral white alpha masks. Apply the canonical FormulaStore
		# foreground here so color changes remain a cheap redraw and never recompile Typst.
		var foreground: Color = _runtime.model.formulas.get_foreground(entity_id)
		foreground.a = 1.0
		var inset: float = minf(4.0, minf(bounds.size.x, bounds.size.y) * 0.04)
		var fitted: Rect2 = _fit_texture_rect(texture, bounds.grow(-inset))
		draw_texture_rect(texture, fitted, false, foreground)
	else:
		_draw_placeholder(bounds, failure)

	# A failed derived render gets a subtle diagnostic outline without turning the
	# FormulaObject back into an opaque card. Normal successful formulas draw no
	# background and no persistent border.
	if not failure.is_empty():
		var danger: Color = NotLightTheme.semantic_color("danger")
		draw_rect(bounds, Color(danger, 0.055), true)
		draw_rect(bounds, Color(danger, 0.72), false, 1.15, true)


func _draw_placeholder(bounds: Rect2, failure: String) -> void:
	var font: Font = ThemeDB.fallback_font
	var label: String = NotLightL10n.text("ui.badge.formula")
	if not failure.is_empty():
		label = NotLightL10n.text("ui.format.failure_badge") % label
	var font_size: int = clampi(int(round(22.0 / maxf(_zoom, 0.7))), 13, 24)
	var text_size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var color: Color = NotLightTheme.semantic_color("accent") if failure.is_empty() else NotLightTheme.semantic_color("danger")
	draw_string(font, bounds.get_center() + Vector2(-text_size.x * 0.5, text_size.y * 0.25), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _fit_texture_rect(texture: Texture2D, bounds: Rect2) -> Rect2:
	var source_size: Vector2 = texture.get_size()
	if source_size.x <= 0.0 or source_size.y <= 0.0 or bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return bounds
	var scale_value: float = minf(bounds.size.x / source_size.x, bounds.size.y / source_size.y)
	var fitted_size: Vector2 = source_size * scale_value
	return Rect2(bounds.get_center() - fitted_size * 0.5, fitted_size)
