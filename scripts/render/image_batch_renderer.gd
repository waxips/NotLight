# SPDX-License-Identifier: GPL-3.0-or-later
class_name ImageBatchRenderer
extends Node2D

var _runtime: BoardRuntime
var _cache: ImageAssetCache
var _visible_ids: PackedInt64Array = PackedInt64Array()
var _hidden_ids: Dictionary = {}
var _zoom: float = 1.0


func configure(runtime: BoardRuntime, cache: ImageAssetCache) -> void:
	_runtime = runtime
	_cache = cache
	queue_redraw()


func rebuild(runtime: BoardRuntime, cache: ImageAssetCache, candidate_ids: PackedInt64Array, maximum_images: int, zoom: float) -> void:
	_runtime = runtime
	_cache = cache
	_zoom = maxf(zoom, 0.08)
	_visible_ids = PackedInt64Array()
	if runtime == null:
		queue_redraw()
		return
	var ids: Array[int] = []
	for entity_id: int in candidate_ids:
		if runtime.model.get_entity_type(entity_id) == BoardEntityTypes.IMAGE and runtime.model.images.contains(entity_id):
			ids.append(entity_id)
	if ids.size() > maxi(1, maximum_images):
		ids.sort_custom(func(left_id: int, right_id: int) -> bool:
			var left_bounds: Rect2 = runtime.model.get_entity_bounds(left_id)
			var right_bounds: Rect2 = runtime.model.get_entity_bounds(right_id)
			var left_area: float = left_bounds.size.x * left_bounds.size.y
			var right_area: float = right_bounds.size.x * right_bounds.size.y
			if not is_equal_approx(left_area, right_area):
				return left_area > right_area
			return left_id < right_id
		)
		ids.resize(maxi(1, maximum_images))
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


func notify_texture_ready(_asset_id: String) -> void:
	queue_redraw()


func clear() -> void:
	_runtime = null
	_visible_ids = PackedInt64Array()
	_hidden_ids.clear()
	queue_redraw()


func _draw() -> void:
	if _runtime == null:
		return
	for entity_id: int in _visible_ids:
		if _hidden_ids.has(entity_id) or not _runtime.model.images.contains(entity_id):
			continue
		var bounds: Rect2 = _runtime.model.get_entity_bounds(entity_id)
		var asset_id: String = _runtime.model.images.get_asset_id(entity_id)
		var desired_extent: float = maxf(bounds.size.x, bounds.size.y) * _zoom
		var texture: Texture2D = null
		if _cache != null:
			texture = _cache.request_texture(asset_id, desired_extent)
		if texture != null:
			draw_texture_rect(texture, bounds, false)
		else:
			_draw_placeholder(bounds, asset_id)


func _draw_placeholder(bounds: Rect2, asset_id: String) -> void:
	var background: Color = Color("#edf2ea")
	var border: Color = Color("#b8c5b8")
	if _cache != null and _cache.has_failure(asset_id):
		background = Color("#f8eeee")
		border = Color("#c98989")
	draw_rect(bounds, background, true)
	draw_rect(bounds, border, false, 1.0, true)
	var cross_color: Color = Color(border, 0.62)
	draw_line(bounds.position, bounds.end, cross_color, 1.0, true)
	draw_line(Vector2(bounds.end.x, bounds.position.y), Vector2(bounds.position.x, bounds.end.y), cross_color, 1.0, true)
