# SPDX-License-Identifier: GPL-3.0-or-later
class_name UpdateStrokeStyleCommand
extends BoardCommand

var entity_id: int
var before_style: int
var before_color: Color
var before_width: float
var before_spread: float = 1.0
var before_bounds: Rect2 = Rect2()
var after_style: int
var after_color: Color
var after_width: float
var after_spread: float = 1.0
var after_bounds: Rect2 = Rect2()


func _init(runtime: BoardRuntime, target_id: int, style_id: int, color: Color, width: float, spray_spread: float = 1.0) -> void:
	label = NotLightL10n.text("command.stroke.update")
	entity_id = target_id
	after_style = clampi(style_id, StrokeStore.STYLE_PEN, StrokeStore.STYLE_SPRAY)
	after_color = color
	after_width = clampf(width, StrokeStore.MIN_WIDTH, StrokeStore.MAX_WIDTH)
	after_spread = clampf(spray_spread, StrokeStore.MIN_SPRAY_SPREAD, StrokeStore.MAX_SPRAY_SPREAD)
	if runtime == null or not runtime.model.strokes.contains(entity_id) or not runtime.model.contains(entity_id):
		return
	before_style = runtime.model.strokes.get_style_id(entity_id)
	before_color = runtime.model.strokes.get_color(entity_id)
	before_bounds = runtime.model.get_entity_bounds(entity_id)
	before_width = runtime.model.strokes.get_effective_width(entity_id, before_bounds)
	before_spread = runtime.model.strokes.get_spray_spread(entity_id)
	var world_points: PackedVector2Array = runtime.model.strokes.get_world_points(entity_id, before_bounds)
	after_bounds = StrokeStore.recommended_bounds_for_world_points(world_points, after_style, after_width, after_spread)


func execute(runtime: BoardRuntime) -> bool:
	return _apply(runtime, after_style, after_color, after_width, after_spread, after_bounds)


func undo(runtime: BoardRuntime) -> bool:
	return _apply(runtime, before_style, before_color, before_width, before_spread, before_bounds)


func can_merge_with(other: BoardCommand) -> bool:
	return other is UpdateStrokeStyleCommand and (other as UpdateStrokeStyleCommand).entity_id == entity_id


func merge_from(other: BoardCommand) -> void:
	if other is UpdateStrokeStyleCommand:
		var update: UpdateStrokeStyleCommand = other as UpdateStrokeStyleCommand
		after_style = update.after_style
		after_color = update.after_color
		after_width = update.after_width
		after_spread = update.after_spread
		after_bounds = update.after_bounds


func _apply(runtime: BoardRuntime, style_id: int, color: Color, width: float, spray_spread: float, target_bounds: Rect2) -> bool:
	if runtime == null or not runtime.model.strokes.contains(entity_id) or not runtime.model.contains(entity_id):
		return false
	var current_bounds: Rect2 = runtime.model.get_entity_bounds(entity_id)
	var world_points: PackedVector2Array = runtime.model.strokes.get_world_points(entity_id, current_bounds)
	if world_points.is_empty():
		return false
	var rotation: float = runtime.model.transforms.get_rotation(entity_id)
	runtime.begin_change_batch()
	var style_applied: bool = runtime.model.strokes.apply_style_with_world_geometry(
		entity_id,
		style_id,
		color,
		width,
		spray_spread,
		world_points,
		target_bounds
	)
	var transform_applied: bool = false
	if style_applied:
		transform_applied = runtime.set_entity_transform(entity_id, target_bounds, rotation)
	if style_applied and transform_applied:
		runtime.notify_content_changed()
	runtime.end_change_batch()
	return style_applied and transform_applied
