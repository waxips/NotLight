# SPDX-License-Identifier: GPL-3.0-or-later
class_name CreateStrokeCommand
extends BoardCommand

var raw_points: PackedVector2Array
var style_id: int = StrokeStore.STYLE_PEN
var color: Color = Color("#24885a")
var width: float = 4.0
var spray_spread: float = 1.0
var smoothing_steps: int = 3
var spacing_scale: float = 1.0
var created_entity_id: int = 0
var created_z_order: int = 0
var _record: Dictionary = {}
var _bounds: Rect2 = Rect2()


func _init(points: PackedVector2Array, new_style_id: int, new_color: Color, new_width: float, new_spray_spread: float = 1.0, new_smoothing_steps: int = 3, new_spacing_scale: float = 1.0) -> void:
	label = NotLightL10n.text("command.stroke.create")
	raw_points = points.duplicate()
	style_id = new_style_id
	color = new_color
	width = new_width
	spray_spread = clampf(new_spray_spread, StrokeStore.MIN_SPRAY_SPREAD, StrokeStore.MAX_SPRAY_SPREAD)
	smoothing_steps = clampi(new_smoothing_steps, 1, 8)
	spacing_scale = clampf(new_spacing_scale, 0.45, 1.8)
	_prepare_geometry()


func execute(runtime: BoardRuntime) -> bool:
	if runtime == null or _record.is_empty():
		return false
	runtime.begin_change_batch()
	if created_entity_id > 0:
		if not runtime.restore_entity(
			created_entity_id,
			BoardEntityTypes.STROKE,
			_bounds,
			0.0,
			created_z_order,
			BoardTransformStore.FLAG_VISIBLE
		):
			runtime.end_change_batch()
			return false
		var restore_record: Dictionary = _record.duplicate(true)
		restore_record["entity_id"] = str(created_entity_id)
		if not runtime.model.strokes.restore_record(restore_record):
			runtime.remove_entity(created_entity_id)
			runtime.end_change_batch()
			return false
		runtime.notify_content_changed()
		runtime.end_change_batch()
		return true
	created_z_order = runtime.model.get_max_z_order() + 1
	created_entity_id = runtime.create_entity(
		BoardEntityTypes.STROKE,
		_bounds,
		0.0,
		created_z_order,
		BoardTransformStore.FLAG_VISIBLE
	)
	if created_entity_id <= 0:
		runtime.end_change_batch()
		return false
	var add_record: Dictionary = _record.duplicate(true)
	add_record["entity_id"] = str(created_entity_id)
	if not runtime.model.strokes.restore_record(add_record):
		runtime.remove_entity(created_entity_id)
		created_entity_id = 0
		runtime.end_change_batch()
		return false
	_record["entity_id"] = str(created_entity_id)
	runtime.notify_content_changed()
	runtime.end_change_batch()
	return true


func undo(runtime: BoardRuntime) -> bool:
	if runtime == null or created_entity_id <= 0 or not runtime.model.contains(created_entity_id):
		return false
	_record = runtime.model.strokes.capture_record(created_entity_id)
	_bounds = runtime.model.get_entity_bounds(created_entity_id)
	created_z_order = runtime.model.get_entity_z_order(created_entity_id)
	return runtime.remove_entity(created_entity_id)


func _prepare_geometry() -> void:
	var smooth: PackedVector2Array = StrokeGeometry.build_smooth_path(raw_points, 1.2 * spacing_scale, smoothing_steps)
	if smooth.is_empty():
		return
	_bounds = StrokeStore.recommended_bounds_for_world_points(smooth, style_id, width, spray_spread)
	_record = {
		"entity_id": "0",
		"style_id": clampi(style_id, StrokeStore.STYLE_PEN, StrokeStore.STYLE_SPRAY),
		"color": color.to_html(true),
		"width": clampf(width, StrokeStore.MIN_WIDTH, StrokeStore.MAX_WIDTH),
		"spray_spread": spray_spread,
		"original_width": _bounds.size.x,
		"original_height": _bounds.size.y,
		"points": StrokeGeometry.to_local_points(smooth, _bounds),
	}
