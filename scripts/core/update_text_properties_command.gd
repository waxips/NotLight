# SPDX-License-Identifier: GPL-3.0-or-later
class_name UpdateTextPropertiesCommand
extends BoardCommand

var entity_ids: PackedInt64Array = PackedInt64Array()
var before_records: Array[Dictionary] = []
var after_records: Array[Dictionary] = []
var before_bounds: Array[Rect2] = []
var after_bounds: Array[Rect2] = []


func _init(
	new_entity_ids: PackedInt64Array,
	new_before_records: Array[Dictionary],
	new_after_records: Array[Dictionary],
	new_label: String = NotLightL10n.text("runtime.core.update_text_properties_command.1af7b842ad"),
	new_before_bounds: Array[Rect2] = [],
	new_after_bounds: Array[Rect2] = []
) -> void:
	label = new_label
	entity_ids = new_entity_ids.duplicate()
	before_records = new_before_records.duplicate(true)
	after_records = new_after_records.duplicate(true)
	before_bounds = new_before_bounds.duplicate()
	after_bounds = new_after_bounds.duplicate()


func execute(runtime: BoardRuntime) -> bool:
	return _apply(runtime, after_records, after_bounds)


func undo(runtime: BoardRuntime) -> bool:
	return _apply(runtime, before_records, before_bounds)


func _apply(runtime: BoardRuntime, records: Array[Dictionary], bounds_values: Array[Rect2]) -> bool:
	if runtime == null or records.size() != entity_ids.size():
		return false
	var apply_bounds: bool = bounds_values.size() == entity_ids.size()
	for entity_id: int in entity_ids:
		if not runtime.model.text_blocks.contains(entity_id):
			return false
	runtime.begin_change_batch()
	for index: int in range(entity_ids.size()):
		var entity_id: int = int(entity_ids[index])
		if not runtime.model.text_blocks.apply_record(entity_id, records[index]):
			runtime.end_change_batch()
			return false
		if apply_bounds:
			if not runtime.set_entity_transform(
				entity_id,
				bounds_values[index],
				runtime.model.transforms.get_rotation(entity_id)
			):
				runtime.end_change_batch()
				return false
	runtime.end_change_batch()
	return true
