# SPDX-License-Identifier: GPL-3.0-or-later
class_name CreateVideoCommand
extends BoardCommand

var bounds: Rect2 = Rect2()
var asset_id: String = ""
var pixel_size: Vector2i = VideoStore.DEFAULT_PIXEL_SIZE
var duration_seconds: float = 0.0
var z_order: int = 0
var created_entity_id: int = 0


func _init(
	new_bounds: Rect2,
	new_asset_id: String,
	new_pixel_size: Vector2i,
	new_duration_seconds: float = 0.0,
	new_z_order: int = 0
) -> void:
	label = NotLightL10n.text("runtime.core.create_video_command.5350e04e4a")
	bounds = new_bounds
	asset_id = new_asset_id.strip_edges()
	pixel_size = Vector2i(maxi(1, new_pixel_size.x), maxi(1, new_pixel_size.y))
	duration_seconds = maxf(0.0, new_duration_seconds)
	z_order = new_z_order


func execute(runtime: BoardRuntime) -> bool:
	if runtime == null or asset_id.is_empty():
		return false
	runtime.begin_change_batch()
	if created_entity_id > 0:
		if not runtime.restore_entity(
			created_entity_id,
			BoardEntityTypes.VIDEO,
			bounds,
			0.0,
			z_order,
			BoardTransformStore.FLAG_VISIBLE
		):
			runtime.end_change_batch()
			return false
	else:
		created_entity_id = runtime.create_entity(
			BoardEntityTypes.VIDEO,
			bounds,
			0.0,
			z_order,
			BoardTransformStore.FLAG_VISIBLE
		)
		if created_entity_id <= 0:
			runtime.end_change_batch()
			return false
	var added: bool = runtime.model.videos.add_video(
		created_entity_id,
		asset_id,
		pixel_size,
		duration_seconds
	)
	if not added:
		runtime.remove_entity(created_entity_id)
	runtime.end_change_batch()
	return added


func undo(runtime: BoardRuntime) -> bool:
	return runtime != null and created_entity_id > 0 and runtime.remove_entity(created_entity_id)
