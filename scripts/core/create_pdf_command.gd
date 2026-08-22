# SPDX-License-Identifier: GPL-3.0-or-later
class_name CreatePdfCommand
extends BoardCommand

var bounds: Rect2 = Rect2()
var asset_id: String = ""
var page_count: int = 1
var page_size: Vector2i = PdfStore.DEFAULT_PAGE_SIZE
var z_order: int = 0
var created_entity_id: int = 0


func _init(new_bounds: Rect2, new_asset_id: String, new_page_count: int, new_page_size: Vector2i, new_z_order: int = 0) -> void:
	label = NotLightL10n.text("runtime.core.create_pdf_command.c77a732950")
	bounds = new_bounds
	asset_id = new_asset_id.strip_edges()
	page_count = maxi(1, new_page_count)
	page_size = Vector2i(maxi(1, new_page_size.x), maxi(1, new_page_size.y))
	z_order = new_z_order


func execute(runtime: BoardRuntime) -> bool:
	if runtime == null or asset_id.is_empty():
		return false
	runtime.begin_change_batch()
	if created_entity_id > 0:
		if not runtime.restore_entity(created_entity_id, BoardEntityTypes.PDF, bounds, 0.0, z_order, BoardTransformStore.FLAG_VISIBLE):
			runtime.end_change_batch()
			return false
	else:
		created_entity_id = runtime.create_entity(BoardEntityTypes.PDF, bounds, 0.0, z_order, BoardTransformStore.FLAG_VISIBLE)
		if created_entity_id <= 0:
			runtime.end_change_batch()
			return false
	var added: bool = runtime.model.pdfs.add_pdf(created_entity_id, asset_id, page_count, page_size)
	if not added:
		runtime.remove_entity(created_entity_id)
	runtime.end_change_batch()
	return added


func undo(runtime: BoardRuntime) -> bool:
	return runtime != null and created_entity_id > 0 and runtime.remove_entity(created_entity_id)
