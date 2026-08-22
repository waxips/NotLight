# SPDX-License-Identifier: GPL-3.0-or-later
class_name EditTextBlockCommand
extends BoardCommand

var entity_id: int = 0
var before_text: String = ""
var after_text: String = ""
var before_bounds: Rect2 = Rect2()
var after_bounds: Rect2 = Rect2()


func _init(
	new_entity_id: int,
	new_before_text: String,
	new_after_text: String,
	new_before_bounds: Rect2 = Rect2(),
	new_after_bounds: Rect2 = Rect2()
) -> void:
	label = NotLightL10n.text("runtime.core.edit_text_block_command.1c0ed46897")
	entity_id = new_entity_id
	before_text = new_before_text
	after_text = new_after_text
	before_bounds = new_before_bounds
	after_bounds = new_after_bounds


func execute(runtime: BoardRuntime) -> bool:
	return _apply(runtime, after_text, after_bounds)


func undo(runtime: BoardRuntime) -> bool:
	return _apply(runtime, before_text, before_bounds)


func _apply(runtime: BoardRuntime, value: String, bounds: Rect2) -> bool:
	if runtime == null or not runtime.model.text_blocks.contains(entity_id):
		return false
	runtime.begin_change_batch()
	if not runtime.model.text_blocks.set_text(entity_id, value):
		runtime.end_change_batch()
		return false
	if bounds.size.x > 0.0 and bounds.size.y > 0.0:
		if not runtime.set_entity_transform(entity_id, bounds, runtime.model.transforms.get_rotation(entity_id)):
			runtime.end_change_batch()
			return false
	runtime.end_change_batch()
	return true
