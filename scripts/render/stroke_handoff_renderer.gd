# SPDX-License-Identifier: GPL-3.0-or-later
class_name StrokeHandoffRenderer
extends Node2D

# A tiny retained bridge for freshly committed strokes.
#
# NativeBoardView used to redraw those strokes in screen space while the main
# StrokeBatchRenderer waited for its quiet-input rebuild window. If the user
# started panning or zooming immediately after drawing, that transient overlay
# was rebuilt on every camera frame. Keeping the handoff under BoardWorld lets
# RenderingServer move/scale the already-built canvas item with the camera.

var runtime: BoardRuntime
var _entity_ids: Dictionary = {}
var _hidden_entity_ids: Dictionary = {}


func configure(board_runtime: BoardRuntime) -> void:
	runtime = board_runtime
	_entity_ids.clear()
	_hidden_entity_ids.clear()
	queue_redraw()


func set_state(entity_ids: Dictionary, hidden_entity_ids: Dictionary) -> void:
	_entity_ids = entity_ids.duplicate()
	_hidden_entity_ids = hidden_entity_ids.duplicate()
	queue_redraw()


func set_hidden_entity_ids(hidden_entity_ids: Dictionary) -> void:
	_hidden_entity_ids = hidden_entity_ids.duplicate()
	queue_redraw()


func _draw() -> void:
	if runtime == null or _entity_ids.is_empty():
		return
	var ordered_ids: Array[int] = []
	for raw_id: Variant in _entity_ids.keys():
		var entity_id: int = int(raw_id)
		if _hidden_entity_ids.has(entity_id) or not runtime.model.strokes.contains(entity_id):
			continue
		ordered_ids.append(entity_id)
	ordered_ids.sort_custom(func(left_id: int, right_id: int) -> bool:
		var left_z: int = runtime.model.get_entity_z_order(left_id)
		var right_z: int = runtime.model.get_entity_z_order(right_id)
		return left_z < right_z if left_z != right_z else left_id < right_id
	)
	var preview_limit: int = maxi(24, runtime.render_policy.spray_preview_particles)
	for entity_id: int in ordered_ids:
		_draw_stroke(entity_id, preview_limit)


func _draw_stroke(entity_id: int, spray_preview_limit: int) -> void:
	var strokes: StrokeStore = runtime.model.strokes
	var bounds: Rect2 = runtime.model.get_entity_bounds(entity_id)
	var style_id: int = strokes.get_style_id(entity_id)
	var world_points: PackedVector2Array
	if style_id == StrokeStore.STYLE_SPRAY:
		# The bridge exists for a fraction of a second. Bound spray geometry just as
		# the interactive overlay does, while preserving both endpoints.
		var local_points: PackedVector2Array = strokes.get_local_points_decimated(
			entity_id,
			maxi(24, int(spray_preview_limit / 2))
		)
		world_points = StrokeGeometry.transformed_points(local_points, strokes.get_original_size(entity_id), bounds)
	else:
		world_points = strokes.get_world_points(entity_id, bounds)
	if world_points.is_empty():
		return
	StrokeBatchRenderer.draw_stroke(
		self,
		world_points,
		style_id,
		strokes.get_color(entity_id),
		strokes.get_effective_width(entity_id, bounds),
		entity_id,
		strokes.get_spray_spread(entity_id),
		spray_preview_limit
	)
