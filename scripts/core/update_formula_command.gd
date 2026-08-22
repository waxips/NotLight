# SPDX-License-Identifier: GPL-3.0-or-later
class_name UpdateFormulaCommand
extends BoardCommand

var entity_id: int = 0
var before_record: Dictionary = {}
var after_record: Dictionary = {}


func _init(target_entity_id: int, previous_record: Dictionary, next_record: Dictionary) -> void:
	entity_id = target_entity_id
	before_record = previous_record.duplicate(true)
	after_record = next_record.duplicate(true)
	label = NotLightL10n.text("command.formula.update")


func execute(runtime: BoardRuntime) -> bool:
	return _apply(runtime, after_record)


func undo(runtime: BoardRuntime) -> bool:
	return _apply(runtime, before_record)


func can_merge_with(other: BoardCommand) -> bool:
	return other is UpdateFormulaCommand and (other as UpdateFormulaCommand).entity_id == entity_id


func merge_from(other: BoardCommand) -> void:
	if other is UpdateFormulaCommand:
		after_record = (other as UpdateFormulaCommand).after_record.duplicate(true)


func _apply(runtime: BoardRuntime, record: Dictionary) -> bool:
	if runtime == null or not runtime.model.formulas.contains(entity_id):
		return false
	return runtime.model.formulas.apply_record(entity_id, record)
