# SPDX-License-Identifier: GPL-3.0-or-later
class_name UpdateAssetInstanceTitleCommand
extends BoardCommand

var entity_id: int = 0
var before_title: String = ""
var after_title: String = ""


func _init(target_entity_id: int, previous_title: String, next_title: String) -> void:
	entity_id = target_entity_id
	before_title = previous_title
	after_title = next_title
	label = NotLightL10n.text("runtime.core.update_asset_instance_title_command.98be03811a")


func execute(runtime: BoardRuntime) -> bool:
	return _apply(runtime, after_title)


func undo(runtime: BoardRuntime) -> bool:
	return _apply(runtime, before_title)


func _apply(runtime: BoardRuntime, title: String) -> bool:
	if runtime == null or not runtime.model.contains(entity_id):
		return false
	var type_id: StringName = runtime.model.get_entity_type(entity_id)
	if type_id == BoardEntityTypes.IMAGE:
		return runtime.model.images.set_instance_title(entity_id, title)
	if type_id == BoardEntityTypes.PDF:
		return runtime.model.pdfs.set_instance_title(entity_id, title)
	if type_id == BoardEntityTypes.VIDEO:
		return runtime.model.videos.set_instance_title(entity_id, title)
	if type_id == BoardEntityTypes.AUDIO:
		return runtime.model.audios.set_instance_title(entity_id, title)
	return false
