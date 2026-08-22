# SPDX-License-Identifier: GPL-3.0-or-later
class_name UpdatePdfPageCommand
extends BoardCommand

var entity_id: int = 0
var before_page: int = 0
var after_page: int = 0


func _init(target_entity_id: int, previous_page: int, next_page: int) -> void:
	entity_id = target_entity_id
	before_page = maxi(0, previous_page)
	after_page = maxi(0, next_page)
	label = NotLightL10n.text("runtime.core.update_pdf_page_command.baf10b9d63")


func execute(runtime: BoardRuntime) -> bool:
	return runtime != null and runtime.model.pdfs.set_page_index(entity_id, after_page)


func undo(runtime: BoardRuntime) -> bool:
	return runtime != null and runtime.model.pdfs.set_page_index(entity_id, before_page)
