# SPDX-License-Identifier: GPL-3.0-or-later
class_name UpdateModuleStateCommand
extends BoardCommand

var entity_id: int = 0
var before_record: Dictionary = {}
var after_record: Dictionary = {}


func _init(target_entity_id: int, previous_record: Dictionary, next_record: Dictionary, action_label: String = "") -> void:
	entity_id = target_entity_id
	before_record = previous_record.duplicate(true)
	after_record = next_record.duplicate(true)
	label = action_label.strip_edges()
	if label.is_empty():
		label = NotLightL10n.text("command.module.update")


func execute(runtime: BoardRuntime) -> bool:
	return _apply(runtime, after_record)


func undo(runtime: BoardRuntime) -> bool:
	return _apply(runtime, before_record)


func can_merge_with(other: BoardCommand) -> bool:
	return other is UpdateModuleStateCommand and (other as UpdateModuleStateCommand).entity_id == entity_id and (other as UpdateModuleStateCommand).label == label


func merge_from(other: BoardCommand) -> void:
	if other is UpdateModuleStateCommand:
		after_record = (other as UpdateModuleStateCommand).after_record.duplicate(true)


func _apply(runtime: BoardRuntime, record: Dictionary) -> bool:
	if runtime == null or not runtime.model.modules.contains(entity_id):
		return false
	return runtime.model.modules.apply_record(entity_id, record)
